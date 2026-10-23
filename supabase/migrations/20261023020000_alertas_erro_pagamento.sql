-- =============================================================================
-- Ingressoudi - Alertas de erro em pagamentos
-- 1) erros_pagamento: historico de falhas de pagamento (criacao do Pix,
--    webhook, conexao/token do Mercado Pago, confirmacao, reembolso). Sem
--    acesso direto pelo navegador: so via RPC ou service role.
-- 2) registrar_erro_pagamento (somente servidor): grava o erro e decide se o
--    super admin recebe push. O mesmo tipo de erro da mesma casa avisa no
--    maximo uma vez a cada 15 minutos (o historico guarda todos).
-- 3) listar_erros_pagamento_plataforma (somente super admin): tela do painel.
-- =============================================================================

create table public.erros_pagamento (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid null
    constraint fk_erros_pagamento_organizacao references public.organizacoes (id) on delete set null,
  tipo text not null,
  mensagem text not null,
  detalhe jsonb null,
  referencia text null,
  avisado boolean not null default false,
  criado_em timestamptz not null default now(),
  constraint ck_erros_pagamento_tipo check (tipo in (
    'PIX_CRIACAO', 'CONTA_MP_DESCONECTADA', 'TOKEN_MP', 'OAUTH_MP', 'WEBHOOK',
    'CONFIRMACAO', 'VALOR_DIVERGENTE', 'REEMBOLSO', 'CONFIGURACAO'
  )),
  constraint ck_erros_pagamento_mensagem check (btrim(mensagem) <> '')
);

create index idx_erros_pagamento_criado_em on public.erros_pagamento (criado_em desc);
create index idx_erros_pagamento_aviso on public.erros_pagamento (tipo, organizacao_id, criado_em desc) where avisado;

alter table public.erros_pagamento enable row level security;
revoke all on table public.erros_pagamento from public, anon, authenticated;
grant select, insert, update, delete on table public.erros_pagamento to service_role;

-- 2) Registro + decisao do aviso (somente servidor) --------------------------------
create or replace function private.registrar_erro_pagamento(
  p_tipo text,
  p_organizacao_id uuid,
  p_mensagem text,
  p_detalhe jsonb default null,
  p_referencia text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := p_organizacao_id;
  v_org_nome text;
  v_enviar boolean;
  v_assinaturas jsonb := '[]'::jsonb;
begin
  if v_org_id is not null then
    select o.nome into v_org_nome from public.organizacoes o where o.id = v_org_id;
    if not found then v_org_id := null; end if;
  end if;

  -- Serializa avisos do mesmo tipo/casa para o anti-spam valer com chamadas simultaneas.
  perform pg_advisory_xact_lock(hashtext('erro_pagamento:' || p_tipo || ':' || coalesce(v_org_id::text, '-')));

  select not exists (
    select 1 from public.erros_pagamento e
     where e.avisado
       and e.tipo = p_tipo
       and e.organizacao_id is not distinct from v_org_id
       and e.criado_em > now() - interval '15 minutes'
  ) into v_enviar;

  insert into public.erros_pagamento (organizacao_id, tipo, mensagem, detalhe, referencia, avisado)
  values (
    v_org_id,
    p_tipo,
    left(coalesce(nullif(btrim(p_mensagem), ''), 'Erro sem descrição'), 500),
    p_detalhe,
    left(p_referencia, 200),
    v_enviar
  );

  if v_enviar then
    select coalesce(jsonb_agg(jsonb_build_object('endpoint', a.endpoint, 'p256dh', a.p256dh, 'auth', a.auth)), '[]'::jsonb)
      into v_assinaturas
      from public.push_assinaturas a
      join public.usuarios u on u.id = a.usuario_id
     where u.super_admin and u.ativo;
  end if;

  return jsonb_build_object(
    'enviar', v_enviar,
    'organizacao_nome', v_org_nome,
    'assinaturas', v_assinaturas);
end;
$$;

create or replace function public.registrar_erro_pagamento(
  p_tipo text, p_organizacao_id uuid, p_mensagem text, p_detalhe jsonb default null, p_referencia text default null
)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.registrar_erro_pagamento(p_tipo, p_organizacao_id, p_mensagem, p_detalhe, p_referencia); $$;

revoke all on function private.registrar_erro_pagamento(text, uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function private.registrar_erro_pagamento(text, uuid, text, jsonb, text) to service_role;
revoke all on function public.registrar_erro_pagamento(text, uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.registrar_erro_pagamento(text, uuid, text, jsonb, text) to service_role;

-- 3) Historico para o super admin ---------------------------------------------------
create or replace function private.listar_erros_pagamento_plataforma(p_limite integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.usuario_e_super_admin() then
    raise exception 'Permissao negada: apenas super administrador' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(linha order by (linha->>'criado_em') desc)
      from (
        select jsonb_build_object(
                 'id', e.id,
                 'tipo', e.tipo,
                 'mensagem', e.mensagem,
                 'detalhe', e.detalhe,
                 'referencia', e.referencia,
                 'avisado', e.avisado,
                 'criado_em', e.criado_em,
                 'organizacao_id', e.organizacao_id,
                 'organizacao_nome', o.nome) as linha
          from public.erros_pagamento e
          left join public.organizacoes o on o.id = e.organizacao_id
         order by e.criado_em desc
         limit greatest(1, least(coalesce(p_limite, 200), 500))
      ) t
  ), '[]'::jsonb);
end;
$$;

create or replace function public.listar_erros_pagamento_plataforma(p_limite integer default 200)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.listar_erros_pagamento_plataforma(p_limite); $$;

revoke all on function private.listar_erros_pagamento_plataforma(integer) from public, anon;
grant execute on function private.listar_erros_pagamento_plataforma(integer) to authenticated, service_role;
revoke all on function public.listar_erros_pagamento_plataforma(integer) from public, anon;
grant execute on function public.listar_erros_pagamento_plataforma(integer) to authenticated, service_role;
