-- =============================================================================
-- GZ1 Ingresso - Lista VIP: RPCs administrativas
-- Migration: lista_vip_admin
--
-- Superficie ADMIN (sem SELECT/INSERT direto nas tabelas):
--   public.listar_lista_vip_admin(p_evento_id, p_busca)
--   public.criar_lista_vip_admin(p_evento_id, p_nome, p_telefone, p_observacao)
--   public.atualizar_lista_vip_admin(p_vip_id, p_nome, p_telefone, p_observacao)
--   public.remover_lista_vip_admin(p_vip_id)
--     -> private (SECURITY DEFINER, admin-only)
--
-- Regras:
--   * somente ADMINISTRADOR ativo;
--   * evento obrigatorio e nao pode estar REALIZADO/CANCELADO;
--   * nome nao vazio; nomes duplicados permitidos (id proprio identifica);
--   * edicao bloqueada apos a entrada (preserva historico);
--   * remocao e logica (ativo=false) e so antes da entrada.
--
-- Auditoria: VIP_ADICIONADO, VIP_ATUALIZADO, VIP_REMOVIDO. Sem dados sensiveis.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- LISTAR
-- -----------------------------------------------------------------------------
create or replace function private.listar_lista_vip_admin(
  p_evento_id uuid,
  p_busca text default null
)
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

  if not exists (select 1 from public.eventos e where e.id = p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'vip_id', lv.id,
               'nome', lv.nome,
               'telefone', lv.telefone,
               'observacao', lv.observacao,
               'entrou', (ev.id is not null),
               'entrada_em', ev.entrada_em,
               'criado_em', lv.criado_em,
               'criado_por', u.nome
             )
             order by lv.nome asc, lv.criado_em asc
           ),
           '[]'::jsonb
         )
    into v_itens
    from public.lista_vip lv
    join public.usuarios u on u.id = lv.criado_por_usuario_id
    left join lateral (
      select e.id, e.entrada_em
        from public.entradas_vip e
       where e.lista_vip_id = lv.id
         and e.anulada_em is null
       order by e.entrada_em desc
       limit 1
    ) ev on true
   where lv.evento_id = p_evento_id
     and lv.ativo = true
     and (
       p_busca is null or btrim(p_busca) = ''
       or lv.nome ilike '%' || btrim(p_busca) || '%'
       or lv.telefone ilike '%' || btrim(p_busca) || '%'
     );

  return v_itens;
end;
$$;

-- -----------------------------------------------------------------------------
-- CRIAR
-- -----------------------------------------------------------------------------
create or replace function private.criar_lista_vip_admin(
  p_evento_id uuid,
  p_nome text,
  p_telefone text default null,
  p_observacao text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_evento public.eventos%rowtype;
  v_id uuid;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  if p_nome is null or btrim(p_nome) = '' then
    raise exception 'Informe o nome do convidado' using errcode = '23514';
  end if;

  select * into v_evento
    from public.eventos e
   where e.id = p_evento_id
   for update;

  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if v_evento.status in ('REALIZADO', 'CANCELADO') then
    raise exception 'Evento % nao permite alterar a lista VIP (status=%)', p_evento_id, v_evento.status
      using errcode = '23514';
  end if;

  insert into public.lista_vip (evento_id, nome, telefone, observacao, criado_por_usuario_id)
  values (
    p_evento_id,
    btrim(p_nome),
    nullif(btrim(coalesce(p_telefone, '')), ''),
    nullif(btrim(coalesce(p_observacao, '')), ''),
    auth.uid()
  )
  returning id into v_id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos)
  values (
    auth.uid(),
    'VIP_ADICIONADO',
    'lista_vip',
    v_id,
    jsonb_build_object('evento_id', p_evento_id, 'nome', btrim(p_nome))
  );

  return jsonb_build_object(
    'vip_id', v_id,
    'evento_id', p_evento_id,
    'nome', btrim(p_nome)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- ATUALIZAR (bloqueado apos a entrada)
-- -----------------------------------------------------------------------------
create or replace function private.atualizar_lista_vip_admin(
  p_vip_id uuid,
  p_nome text,
  p_telefone text default null,
  p_observacao text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_vip public.lista_vip%rowtype;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  if p_nome is null or btrim(p_nome) = '' then
    raise exception 'Informe o nome do convidado' using errcode = '23514';
  end if;

  select * into v_vip
    from public.lista_vip lv
   where lv.id = p_vip_id
   for update;

  if not found then
    raise exception 'Convidado VIP % nao encontrado', p_vip_id using errcode = '23503';
  end if;

  if exists (
    select 1 from public.entradas_vip ev
     where ev.lista_vip_id = p_vip_id
       and ev.anulada_em is null
  ) then
    raise exception 'Nao e possivel editar um convidado que ja registrou entrada'
      using errcode = '23514';
  end if;

  update public.lista_vip
     set nome = btrim(p_nome),
         telefone = nullif(btrim(coalesce(p_telefone, '')), ''),
         observacao = nullif(btrim(coalesce(p_observacao, '')), ''),
         atualizado_em = now()
   where id = p_vip_id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values (
    auth.uid(),
    'VIP_ATUALIZADO',
    'lista_vip',
    p_vip_id,
    jsonb_build_object('nome', v_vip.nome, 'telefone', v_vip.telefone, 'observacao', v_vip.observacao),
    jsonb_build_object(
      'nome', btrim(p_nome),
      'telefone', nullif(btrim(coalesce(p_telefone, '')), ''),
      'observacao', nullif(btrim(coalesce(p_observacao, '')), '')
    )
  );

  return jsonb_build_object('vip_id', p_vip_id, 'nome', btrim(p_nome));
end;
$$;

-- -----------------------------------------------------------------------------
-- REMOVER (logico; so antes da entrada)
-- -----------------------------------------------------------------------------
create or replace function private.remover_lista_vip_admin(p_vip_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_vip public.lista_vip%rowtype;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select * into v_vip
    from public.lista_vip lv
   where lv.id = p_vip_id
   for update;

  if not found then
    raise exception 'Convidado VIP % nao encontrado', p_vip_id using errcode = '23503';
  end if;

  if exists (
    select 1 from public.entradas_vip ev
     where ev.lista_vip_id = p_vip_id
       and ev.anulada_em is null
  ) then
    raise exception 'Nao e possivel remover um convidado que ja registrou entrada'
      using errcode = '23514';
  end if;

  if not v_vip.ativo then
    return jsonb_build_object('vip_id', p_vip_id, 'ativo', false, 'resultado', 'ja_removido');
  end if;

  update public.lista_vip
     set ativo = false, atualizado_em = now()
   where id = p_vip_id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values (
    auth.uid(),
    'VIP_REMOVIDO',
    'lista_vip',
    p_vip_id,
    jsonb_build_object('ativo', true, 'nome', v_vip.nome),
    jsonb_build_object('ativo', false)
  );

  return jsonb_build_object('vip_id', p_vip_id, 'ativo', false, 'resultado', 'removido');
end;
$$;

-- -----------------------------------------------------------------------------
-- WRAPPERS PUBLICOS (SECURITY INVOKER)
-- -----------------------------------------------------------------------------
create or replace function public.listar_lista_vip_admin(
  p_evento_id uuid,
  p_busca text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select private.listar_lista_vip_admin(p_evento_id, p_busca); $$;

create or replace function public.criar_lista_vip_admin(
  p_evento_id uuid,
  p_nome text,
  p_telefone text default null,
  p_observacao text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select private.criar_lista_vip_admin(p_evento_id, p_nome, p_telefone, p_observacao); $$;

create or replace function public.atualizar_lista_vip_admin(
  p_vip_id uuid,
  p_nome text,
  p_telefone text default null,
  p_observacao text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select private.atualizar_lista_vip_admin(p_vip_id, p_nome, p_telefone, p_observacao); $$;

create or replace function public.remover_lista_vip_admin(p_vip_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select private.remover_lista_vip_admin(p_vip_id); $$;

-- -----------------------------------------------------------------------------
-- ACL (admin-only via check interno; anon sem EXECUTE)
-- -----------------------------------------------------------------------------
grant usage on schema private to authenticated, service_role;

revoke all on function private.listar_lista_vip_admin(uuid, text) from public;
grant execute on function private.listar_lista_vip_admin(uuid, text) to authenticated, service_role;

revoke all on function private.criar_lista_vip_admin(uuid, text, text, text) from public;
grant execute on function private.criar_lista_vip_admin(uuid, text, text, text) to authenticated, service_role;

revoke all on function private.atualizar_lista_vip_admin(uuid, text, text, text) from public;
grant execute on function private.atualizar_lista_vip_admin(uuid, text, text, text) to authenticated, service_role;

revoke all on function private.remover_lista_vip_admin(uuid) from public;
grant execute on function private.remover_lista_vip_admin(uuid) to authenticated, service_role;

revoke execute on function public.listar_lista_vip_admin(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.listar_lista_vip_admin(uuid, text) to authenticated, service_role;

revoke execute on function public.criar_lista_vip_admin(uuid, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.criar_lista_vip_admin(uuid, text, text, text) to authenticated, service_role;

revoke execute on function public.atualizar_lista_vip_admin(uuid, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.atualizar_lista_vip_admin(uuid, text, text, text) to authenticated, service_role;

revoke execute on function public.remover_lista_vip_admin(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.remover_lista_vip_admin(uuid) to authenticated, service_role;

comment on function public.listar_lista_vip_admin(uuid, text) is
  'Lista VIP do evento (ADMINISTRADOR). Status derivado de entradas_vip.';
comment on function public.criar_lista_vip_admin(uuid, text, text, text) is
  'Adiciona convidado VIP (ADMINISTRADOR). Sem preco/pedido/pagamento.';
