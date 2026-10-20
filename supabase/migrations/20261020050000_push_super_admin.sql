-- =============================================================================
-- Ingressoudi - Notificacao push para o super admin
-- 1) push_assinaturas: aparelhos do super admin que aceitaram notificacoes
--    (Web Push). Sem acesso direto pelo navegador: so via RPC ou service role.
-- 2) registrar_push_assinatura / remover_push_assinatura: o proprio super
--    admin liga e desliga o aviso em cada aparelho.
-- 3) organizacoes.aviso_cadastro_em + reservar_aviso_nova_organizacao: o
--    servidor (service role) marca a casa como avisada uma unica vez e recebe
--    os aparelhos para enviar "Nova casa cadastrada".
-- =============================================================================

create table public.push_assinaturas (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null
    constraint fk_push_assinaturas_usuario references public.usuarios (id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  user_agent text null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint uq_push_assinaturas_endpoint unique (endpoint),
  constraint ck_push_assinaturas_endpoint check (endpoint ~ '^https://'),
  constraint ck_push_assinaturas_chaves check (btrim(p256dh) <> '' and btrim(auth) <> '')
);

create index idx_push_assinaturas_usuario on public.push_assinaturas (usuario_id);

create trigger trg_push_assinaturas_atualizado_em
  before update on public.push_assinaturas
  for each row execute function public.definir_atualizado_em();

alter table public.push_assinaturas enable row level security;
revoke all on table public.push_assinaturas from public, anon, authenticated;
grant select, insert, update, delete on table public.push_assinaturas to service_role;

-- Casas ja existentes nao geram aviso.
alter table public.organizacoes add column aviso_cadastro_em timestamptz null;
update public.organizacoes set aviso_cadastro_em = criado_em where aviso_cadastro_em is null;

-- 2) Super admin liga/desliga o aviso no aparelho ----------------------------------
create or replace function private.registrar_push_assinatura(
  p_endpoint text, p_p256dh text, p_auth text, p_user_agent text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not private.usuario_e_super_admin() then
    raise exception 'Permissao negada: apenas super admin' using errcode = '42501';
  end if;
  if p_endpoint is null or p_endpoint !~ '^https://' or length(p_endpoint) > 1000 then
    raise exception 'Assinatura de notificacao invalida' using errcode = '23514';
  end if;
  if coalesce(btrim(p_p256dh), '') = '' or coalesce(btrim(p_auth), '') = '' then
    raise exception 'Assinatura de notificacao invalida' using errcode = '23514';
  end if;

  insert into public.push_assinaturas (usuario_id, endpoint, p256dh, auth, user_agent)
  values (v_uid, p_endpoint, btrim(p_p256dh), btrim(p_auth), left(p_user_agent, 300))
  on conflict (endpoint) do update
    set usuario_id = excluded.usuario_id,
        p256dh = excluded.p256dh,
        auth = excluded.auth,
        user_agent = excluded.user_agent;

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function private.remover_push_assinatura(p_endpoint text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Permissao negada' using errcode = '42501';
  end if;
  delete from public.push_assinaturas where endpoint = p_endpoint and usuario_id = v_uid;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.registrar_push_assinatura(
  p_endpoint text, p_p256dh text, p_auth text, p_user_agent text default null
)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.registrar_push_assinatura(p_endpoint, p_p256dh, p_auth, p_user_agent); $$;

create or replace function public.remover_push_assinatura(p_endpoint text)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.remover_push_assinatura(p_endpoint); $$;

revoke all on function private.registrar_push_assinatura(text, text, text, text) from public, anon;
grant execute on function private.registrar_push_assinatura(text, text, text, text) to authenticated, service_role;
revoke all on function public.registrar_push_assinatura(text, text, text, text) from public, anon;
grant execute on function public.registrar_push_assinatura(text, text, text, text) to authenticated, service_role;
revoke all on function private.remover_push_assinatura(text) from public, anon;
grant execute on function private.remover_push_assinatura(text) to authenticated, service_role;
revoke all on function public.remover_push_assinatura(text) from public, anon;
grant execute on function public.remover_push_assinatura(text) to authenticated, service_role;

-- 3) Aviso de casa nova (somente servidor) ------------------------------------------
-- Marca a casa como avisada (uma unica vez, ate 1 hora depois do cadastro) e
-- devolve os aparelhos dos super admins ativos. Quem chama precisa ser membro
-- da casa (o servidor confere antes).
create or replace function private.reservar_aviso_nova_organizacao(p_organizacao_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org public.organizacoes%rowtype;
  v_assinaturas jsonb;
begin
  update public.organizacoes o
     set aviso_cadastro_em = now()
   where o.id = p_organizacao_id
     and o.aviso_cadastro_em is null
     and o.criado_em > now() - interval '1 hour'
  returning o.* into v_org;

  if v_org.id is null then
    return jsonb_build_object('enviar', false);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('endpoint', a.endpoint, 'p256dh', a.p256dh, 'auth', a.auth)), '[]'::jsonb)
    into v_assinaturas
    from public.push_assinaturas a
    join public.usuarios u on u.id = a.usuario_id
   where u.super_admin and u.ativo;

  return jsonb_build_object(
    'enviar', true,
    'nome', v_org.nome,
    'slug', v_org.slug,
    'aprovada', v_org.aprovada,
    'assinaturas', v_assinaturas);
end;
$$;

create or replace function public.reservar_aviso_nova_organizacao(p_organizacao_id uuid)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.reservar_aviso_nova_organizacao(p_organizacao_id); $$;

revoke all on function private.reservar_aviso_nova_organizacao(uuid) from public, anon, authenticated;
grant execute on function private.reservar_aviso_nova_organizacao(uuid) to service_role;
revoke all on function public.reservar_aviso_nova_organizacao(uuid) from public, anon, authenticated;
grant execute on function public.reservar_aviso_nova_organizacao(uuid) to service_role;
