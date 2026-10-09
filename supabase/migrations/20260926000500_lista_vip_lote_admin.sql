-- =============================================================================
-- GZ1 Ingresso - Lista VIP: cadastro em lote (ADMINISTRADOR)
-- Migration: lista_vip_lote_admin
--
-- Adiciona RPC transacional para incluir VARIOS convidados de uma vez,
-- preservando o cadastro individual existente.
--
--   public/private.criar_lista_vip_em_lote_admin(p_evento_id uuid, p_nomes text[])
--
-- Regras:
--   * somente ADMINISTRADOR ativo;
--   * evento obrigatorio; nao pode estar REALIZADO/CANCELADO
--     (mesma regra do cadastro individual);
--   * array obrigatorio, no maximo 100 nomes;
--   * cada nome nao vazio; comprimento maximo 120 caracteres;
--   * nomes duplicados SAO permitidos (sem UNIQUE);
--   * telefone = null e observacao = null nesta versao;
--   * criado_por_usuario_id = auth.uid() para todos.
--
-- Atomicidade: e uma unica funcao; qualquer nome invalido levanta excecao e
-- nada e inserido.
--
-- Auditoria: uma unica acao VIP_LOTE_ADICIONADO, com evento_id e quantidade
-- (sem registrar a lista inteira de nomes).
--
-- Nao altera tabelas existentes, RLS, portaria, financeiro ou dashboard.
-- =============================================================================

create or replace function private.criar_lista_vip_em_lote_admin(
  p_evento_id uuid,
  p_nomes text[]
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_evento public.eventos%rowtype;
  v_qtd integer;
  v_quantidade integer := 0;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  if p_nomes is null or cardinality(p_nomes) < 1 then
    raise exception 'Informe pelo menos um nome' using errcode = '23514';
  end if;

  v_qtd := cardinality(p_nomes);

  if v_qtd > 100 then
    raise exception 'Limite de 100 convidados por inclusao excedido' using errcode = '23514';
  end if;

  if exists (
    select 1 from unnest(p_nomes) as n(nome)
     where n.nome is null or btrim(n.nome) = ''
  ) then
    raise exception 'Ha um nome invalido na lista' using errcode = '23514';
  end if;

  if exists (
    select 1 from unnest(p_nomes) as n(nome)
     where length(btrim(n.nome)) > 120
  ) then
    raise exception 'Nome de convidado muito longo' using errcode = '23514';
  end if;

  -- mesma regra de evento do cadastro individual
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
  select p_evento_id, btrim(n.nome), null, null, auth.uid()
    from unnest(p_nomes) as n(nome);

  get diagnostics v_quantidade = row_count;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos)
  values (
    auth.uid(),
    'VIP_LOTE_ADICIONADO',
    'lista_vip',
    p_evento_id,
    jsonb_build_object(
      'evento_id', p_evento_id,
      'quantidade', v_quantidade,
      'admin_usuario_id', auth.uid()
    )
  );

  return jsonb_build_object('quantidade_criada', v_quantidade);
end;
$$;

create or replace function public.criar_lista_vip_em_lote_admin(
  p_evento_id uuid,
  p_nomes text[]
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select private.criar_lista_vip_em_lote_admin(p_evento_id, p_nomes); $$;

-- ACL (admin-only via check interno; anon sem EXECUTE)
grant usage on schema private to authenticated, service_role;

revoke all on function private.criar_lista_vip_em_lote_admin(uuid, text[]) from public;
grant execute on function private.criar_lista_vip_em_lote_admin(uuid, text[]) to authenticated, service_role;

revoke execute on function public.criar_lista_vip_em_lote_admin(uuid, text[])
  from public, anon, authenticated, service_role;
grant execute on function public.criar_lista_vip_em_lote_admin(uuid, text[]) to authenticated, service_role;

comment on function public.criar_lista_vip_em_lote_admin(uuid, text[]) is
  'Adiciona varios convidados VIP de uma vez (ADMINISTRADOR). Ate 100 nomes; telefone/observacao null; duplicados permitidos.';
