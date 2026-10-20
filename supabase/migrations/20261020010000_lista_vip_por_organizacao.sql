-- =============================================================================
-- Migration: lista_vip_por_organizacao
--
-- A Lista VIP deixa de valer para todas as organizacoes:
--  * organizacoes.lista_vip_ativa (padrao false), ligada pelo super admin em
--    Plataforma > Organizacoes (definir_lista_vip_organizacao);
--  * o super admin ve e usa a Lista VIP em qualquer organizacao;
--  * gravar convidados (incluir/editar) exige a lista liberada (trigger);
--  * obter_sessao_operador devolve organizacao.lista_vip para o painel e
--    listar_organizacoes_plataforma devolve lista_vip_ativa.
-- A portaria continua encontrando convidados ja cadastrados.
-- =============================================================================

alter table public.organizacoes
  add column lista_vip_ativa boolean not null default false;

-- 1) GRAVACAO NA LISTA VIP EXIGE A LISTA LIBERADA ------------------------------
create or replace function private.exigir_lista_vip_liberada()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- sem usuario (servidor/manutencao) nao ha bloqueio
  if auth.uid() is null or private.usuario_e_super_admin() then
    return new;
  end if;
  if not exists (
    select 1 from public.organizacoes o
     where o.id = new.organizacao_id and o.lista_vip_ativa
  ) then
    raise exception 'Lista VIP nao liberada para esta organizacao' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function private.exigir_lista_vip_liberada() from public, anon, authenticated;

-- "zz" para rodar depois do trigger que preenche organizacao_id
create trigger trg_zz_lista_vip_exige_liberacao
  before insert or update on public.lista_vip
  for each row execute function private.exigir_lista_vip_liberada();

-- 2) SUPER ADMIN LIGA/DESLIGA A LISTA VIP DE UMA ORGANIZACAO --------------------
create or replace function private.definir_lista_vip_organizacao(p_organizacao_id uuid, p_ativa boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not private.usuario_e_super_admin() then
    raise exception 'Permissao negada: apenas super administrador' using errcode = '42501';
  end if;
  update public.organizacoes set lista_vip_ativa = coalesce(p_ativa, false) where id = p_organizacao_id;
  if not found then
    raise exception 'Organizacao % nao encontrada', p_organizacao_id using errcode = '23503';
  end if;
  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos, organizacao_id)
  values (auth.uid(),
          case when coalesce(p_ativa, false) then 'LISTA_VIP_LIBERADA' else 'LISTA_VIP_BLOQUEADA' end,
          'organizacoes', p_organizacao_id, jsonb_build_object('lista_vip_ativa', coalesce(p_ativa, false)), p_organizacao_id);
  return jsonb_build_object('organizacao_id', p_organizacao_id, 'lista_vip_ativa', coalesce(p_ativa, false));
end;
$$;

create or replace function public.definir_lista_vip_organizacao(p_organizacao_id uuid, p_ativa boolean)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.definir_lista_vip_organizacao(p_organizacao_id, p_ativa); $$;

revoke all on function private.definir_lista_vip_organizacao(uuid, boolean) from public, anon;
grant execute on function private.definir_lista_vip_organizacao(uuid, boolean) to authenticated, service_role;
revoke all on function public.definir_lista_vip_organizacao(uuid, boolean) from public, anon;
grant execute on function public.definir_lista_vip_organizacao(uuid, boolean) to authenticated, service_role;

-- 3) SESSAO DO OPERADOR DEVOLVE organizacao.lista_vip ---------------------------
CREATE OR REPLACE FUNCTION private.obter_sessao_operador()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_usuario public.usuarios%rowtype;
  v_org uuid;
  v_perfil public.perfil_usuario;
  v_org_json jsonb;
  v_lista jsonb;
begin
  if v_uid is null then
    return null;
  end if;

  select * into v_usuario from public.usuarios u where u.id = v_uid;
  if not found then
    return null;
  end if;

  v_org := private.organizacao_atual_id();

  if v_org is null and v_usuario.ativo then
    select m.organizacao_id into v_org
      from public.membros_organizacao m
      join public.organizacoes o on o.id = m.organizacao_id and o.ativo = true
     where m.usuario_id = v_uid and m.ativo = true
     order by o.nome
     limit 1;
    if v_org is not null then
      update public.usuarios set organizacao_ativa_id = v_org where id = v_uid;
    end if;
  end if;

  if v_org is not null then
    select m.perfil, jsonb_build_object('id', o.id, 'nome', o.nome, 'slug', o.slug, 'aprovada', o.aprovada,
                           'lista_vip', o.lista_vip_ativa)
      into v_perfil, v_org_json
      from public.membros_organizacao m
      join public.organizacoes o on o.id = m.organizacao_id
     where m.organizacao_id = v_org and m.usuario_id = v_uid;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'nome', o.nome, 'slug', o.slug, 'perfil', m.perfil) order by o.nome), '[]'::jsonb)
    into v_lista
    from public.membros_organizacao m
    join public.organizacoes o on o.id = m.organizacao_id and o.ativo = true
   where m.usuario_id = v_uid and m.ativo = true;

  return jsonb_build_object(
    'id', v_usuario.id,
    'nome', v_usuario.nome,
    'email', v_usuario.email,
    'perfil', v_perfil,
    'ativo', (v_usuario.ativo and v_perfil is not null),
    'super_admin', v_usuario.super_admin,
    'organizacao', v_org_json,
    'organizacoes', v_lista
  );
end;
$function$;

-- 4) LISTA DE CASAS DA PLATAFORMA DEVOLVE lista_vip_ativa -----------------------
create or replace function private.listar_organizacoes_plataforma()
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
    select jsonb_agg(jsonb_build_object(
             'organizacao_id', o.id,
             'nome', o.nome,
             'slug', o.slug,
             'ativo', o.ativo,
             'aprovada', o.aprovada,
             'lista_vip_ativa', o.lista_vip_ativa,
             'criado_em', o.criado_em,
             'mercado_pago_conectado', exists (
               select 1 from public.organizacoes_mercado_pago mp where mp.organizacao_id = o.id),
             'administradores', coalesce((
               select string_agg(u.email, ', ' order by u.email)
                 from public.membros_organizacao m
                 join public.usuarios u on u.id = m.usuario_id
                where m.organizacao_id = o.id and m.ativo and m.perfil = 'ADMINISTRADOR'), ''),
             'eventos', (select count(*) from public.eventos e where e.organizacao_id = o.id)
           ) order by o.aprovada, o.criado_em desc)
      from public.organizacoes o
  ), '[]'::jsonb);
end;
$$;
