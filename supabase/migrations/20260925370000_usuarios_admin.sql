-- =============================================================================
-- GZ1 Ingresso - Gerenciamento de usuarios (Configuracoes > Usuarios)
-- Migration: usuarios_admin
--
-- RPCs ADMIN-only (public SECURITY DEFINER + check private.usuario_e_admin()):
--   public.listar_usuarios_admin(p_busca)   -> lista usuarios (sem auth.users)
--   public.atualizar_usuario_admin(...)     -> nome/perfil/ativo + auditoria
--
-- Regras de negocio no backend:
--   * nome obrigatorio;
--   * auto-desativacao sempre bloqueada;
--   * nunca ficar sem ao menos um ADMINISTRADOR ativo;
--   * sem DELETE (usuario pode ter historico operacional).
--
-- Nao expoe tokens/senhas. Nao altera RLS/ACL de tabelas.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Listagem administrativa de usuarios
-- ---------------------------------------------------------------------------
create or replace function public.listar_usuarios_admin(p_busca text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_itens jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'id', u.id,
               'nome', u.nome,
               'email', u.email,
               'perfil', u.perfil,
               'ativo', u.ativo,
               'ultimo_acesso_em', u.ultimo_acesso_em,
               'criado_em', u.criado_em
             )
             order by u.ativo desc, u.perfil, u.nome
           ),
           '[]'::jsonb
         )
    into v_itens
    from public.usuarios u
   where p_busca is null
      or btrim(p_busca) = ''
      or u.nome ilike '%' || p_busca || '%'
      or u.email ilike '%' || p_busca || '%';

  return v_itens;
end;
$$;

revoke execute on function public.listar_usuarios_admin(text) from public, anon, authenticated, service_role;
grant execute on function public.listar_usuarios_admin(text) to authenticated, service_role;

comment on function public.listar_usuarios_admin(text) is 'Lista usuarios (ADMINISTRADOR). Campos: id, nome, email, perfil, ativo, ultimo_acesso_em, criado_em. Sem auth.users.';

-- ---------------------------------------------------------------------------
-- Atualizacao administrativa de usuario (nome/perfil/ativo)
-- ---------------------------------------------------------------------------
create or replace function public.atualizar_usuario_admin(
  p_usuario_id uuid,
  p_nome text,
  p_perfil public.perfil_usuario,
  p_ativo boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_anterior public.usuarios%rowtype;
  v_nome text;
  v_outros_admins integer;
  v_acao text;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  v_nome := btrim(coalesce(p_nome, ''));
  if v_nome = '' then
    raise exception 'Informe o nome do usuario.' using errcode = '23514';
  end if;

  if p_perfil is null or p_ativo is null then
    raise exception 'Dados invalidos: perfil e status sao obrigatorios.' using errcode = '23514';
  end if;

  select * into v_anterior
    from public.usuarios u
   where u.id = p_usuario_id
   for update;

  if not found then
    raise exception 'Usuario nao encontrado.' using errcode = '23503';
  end if;

  -- Nunca permitir auto-desativacao
  if p_usuario_id = auth.uid() and p_ativo = false then
    raise exception 'Voce nao pode desativar o seu proprio usuario.' using errcode = '42501';
  end if;

  -- Nunca ficar sem ADMINISTRADOR ativo:
  -- bloqueia desativar ou rebaixar o ultimo administrador ativo.
  if v_anterior.perfil = 'ADMINISTRADOR'
     and v_anterior.ativo = true
     and (p_ativo = false or p_perfil <> 'ADMINISTRADOR') then
    select count(*) into v_outros_admins
      from public.usuarios u
     where u.perfil = 'ADMINISTRADOR'
       and u.ativo = true
       and u.id <> p_usuario_id;

    if v_outros_admins = 0 then
      raise exception 'E necessario manter pelo menos um administrador ativo.' using errcode = '23514';
    end if;
  end if;

  update public.usuarios
     set nome = v_nome,
         perfil = p_perfil,
         ativo = p_ativo
   where id = p_usuario_id;

  v_acao := case
    when v_anterior.ativo <> p_ativo and p_ativo then 'USUARIO_ATIVADO'
    when v_anterior.ativo <> p_ativo and not p_ativo then 'USUARIO_DESATIVADO'
    when v_anterior.perfil <> p_perfil then 'USUARIO_PERFIL_ALTERADO'
    else 'USUARIO_ATUALIZADO'
  end;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values (
    auth.uid(),
    v_acao,
    'usuarios',
    p_usuario_id,
    jsonb_build_object('nome', v_anterior.nome, 'perfil', v_anterior.perfil, 'ativo', v_anterior.ativo),
    jsonb_build_object('nome', v_nome, 'perfil', p_perfil, 'ativo', p_ativo)
  );

  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function public.atualizar_usuario_admin(uuid, text, public.perfil_usuario, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.atualizar_usuario_admin(uuid, text, public.perfil_usuario, boolean)
  to authenticated, service_role;

comment on function public.atualizar_usuario_admin(uuid, text, public.perfil_usuario, boolean) is 'Atualiza nome/perfil/ativo de um usuario (ADMINISTRADOR). Bloqueia auto-desativacao e remocao do ultimo admin ativo. Registra auditoria.';
