-- =============================================================================
-- GZ1 Ingresso - Lotes administrativos (leitura + criacao) via RPC segura
-- Migration: lotes_admin
--
-- Superficie ADMIN (sem SELECT/INSERT direto nas tabelas):
--   public.listar_lotes_admin(p_evento_id)  -> private (SECURITY DEFINER, admin)
--   public.criar_lote_admin(...)            -> private (SECURITY DEFINER, admin)
--
-- Regras seguem o dominio real ja existente (nao inventar):
--   - ordem calculada no backend: max(ordem)+1
--   - novo lote nasce sempre INATIVO (nao existe regra de "primeiro lote ATIVO")
--   - MANUAL/ESGOTAMENTO => ativacao_em null
--   - DATA_HORA => ativacao_em obrigatorio
--   - ativacao real reutiliza public.ativar_lote_manual
--   - vendidos/disponiveis calculados no backend
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Leitura: evento + lotes (+ vendidos/disponiveis calculados)
-- -----------------------------------------------------------------------------
create or replace function private.listar_lotes_admin(p_evento_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_evento jsonb;
  v_lotes jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  if not exists (select 1 from public.eventos e where e.id = p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  select jsonb_build_object(
           'evento_id', e.id,
           'nome', e.nome,
           'status', e.status,
           'vendas_status', e.vendas_status,
           'publicacao_status', e.publicacao_status,
           'inicio_em', e.inicio_em,
           'local', e.local,
           'imagem_url', e.imagem_url,
           'capacidade_total', e.capacidade_total,
           'estoque_antecipado', e.estoque_antecipado,
           'vendidos', (
             select count(*) from public.ingressos i
              where i.evento_id = e.id and i.status in ('VALIDO', 'UTILIZADO')
           ),
           'disponiveis', private.calcular_disponibilidade_evento(e.id)
         )
    into v_evento
    from public.eventos e
   where e.id = p_evento_id;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'lote_id', l.id,
               'nome', l.nome,
               'ordem', l.ordem,
               'quantidade', l.quantidade,
               'preco', l.preco,
               'tipo_ativacao', l.tipo_ativacao,
               'ativacao_em', l.ativacao_em,
               'ativado_em', l.ativado_em,
               'encerrado_em', l.encerrado_em,
               'status', l.status,
               'quantidade_vendida', (
                 select count(*) from public.ingressos i
                  where i.lote_id = l.id and i.status in ('VALIDO', 'UTILIZADO')
               ),
               'quantidade_disponivel', private.calcular_disponibilidade_lote(l.id)
             )
             order by l.ordem asc
           ),
           '[]'::jsonb
         )
    into v_lotes
    from public.lotes l
   where l.evento_id = p_evento_id;

  return jsonb_build_object('evento', v_evento, 'lotes', v_lotes);
end;
$$;

-- -----------------------------------------------------------------------------
-- Criacao: ordem automatica, status INATIVO, validacoes de dominio
-- -----------------------------------------------------------------------------
create or replace function private.criar_lote_admin(
  p_evento_id uuid,
  p_nome text,
  p_quantidade integer,
  p_preco numeric,
  p_tipo_ativacao public.tipo_ativacao_lote,
  p_ativacao_em timestamptz default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_status_evento public.status_evento;
  v_ordem integer;
  v_ativacao timestamptz;
  v_id uuid;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select e.status into v_status_evento from public.eventos e where e.id = p_evento_id;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if v_status_evento in ('REALIZADO', 'CANCELADO') then
    raise exception 'Evento % nao permite criar lote (status=%)', p_evento_id, v_status_evento using errcode = '23514';
  end if;

  if p_nome is null or btrim(p_nome) = '' then
    raise exception 'Informe o nome do lote' using errcode = '23514';
  end if;
  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'A quantidade deve ser maior que zero' using errcode = '23514';
  end if;
  if p_preco is null or p_preco < 0 then
    raise exception 'O preco deve ser maior ou igual a zero' using errcode = '23514';
  end if;
  if p_tipo_ativacao is null then
    raise exception 'Selecione o tipo de ativacao' using errcode = '23514';
  end if;

  if p_tipo_ativacao = 'DATA_HORA' then
    if p_ativacao_em is null then
      raise exception 'Informe a data e hora de ativacao' using errcode = '23514';
    end if;
    v_ativacao := p_ativacao_em;
  else
    v_ativacao := null;
  end if;

  select coalesce(max(l.ordem), 0) + 1 into v_ordem
    from public.lotes l
   where l.evento_id = p_evento_id;

  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, ativacao_em, status)
  values (p_evento_id, btrim(p_nome), v_ordem, p_quantidade, p_preco, p_tipo_ativacao, v_ativacao, 'INATIVO')
  returning id into v_id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos)
  values (
    auth.uid(),
    'LOTE_CRIADO_ADMIN',
    'lotes',
    v_id,
    jsonb_build_object(
      'evento_id', p_evento_id,
      'ordem', v_ordem,
      'quantidade', p_quantidade,
      'preco', p_preco,
      'tipo_ativacao', p_tipo_ativacao,
      'ativacao_em', v_ativacao
    )
  );

  return jsonb_build_object(
    'lote_id', v_id,
    'evento_id', p_evento_id,
    'nome', btrim(p_nome),
    'ordem', v_ordem,
    'status', 'INATIVO'
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Wrappers publicos (SECURITY INVOKER)
-- -----------------------------------------------------------------------------
create or replace function public.listar_lotes_admin(p_evento_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.listar_lotes_admin(p_evento_id);
$$;

create or replace function public.criar_lote_admin(
  p_evento_id uuid,
  p_nome text,
  p_quantidade integer,
  p_preco numeric,
  p_tipo_ativacao public.tipo_ativacao_lote,
  p_ativacao_em timestamptz default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.criar_lote_admin(p_evento_id, p_nome, p_quantidade, p_preco, p_tipo_ativacao, p_ativacao_em);
$$;

-- -----------------------------------------------------------------------------
-- ACL (admin-only via check interno; anon sem EXECUTE)
-- -----------------------------------------------------------------------------
grant usage on schema private to authenticated, service_role;

revoke all on function private.listar_lotes_admin(uuid) from public;
grant execute on function private.listar_lotes_admin(uuid) to authenticated, service_role;

revoke all on function private.criar_lote_admin(
  uuid, text, integer, numeric, public.tipo_ativacao_lote, timestamptz
) from public;
grant execute on function private.criar_lote_admin(
  uuid, text, integer, numeric, public.tipo_ativacao_lote, timestamptz
) to authenticated, service_role;

revoke execute on function public.listar_lotes_admin(uuid) from public, anon, authenticated, service_role;
grant execute on function public.listar_lotes_admin(uuid) to authenticated, service_role;

revoke execute on function public.criar_lote_admin(
  uuid, text, integer, numeric, public.tipo_ativacao_lote, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.criar_lote_admin(
  uuid, text, integer, numeric, public.tipo_ativacao_lote, timestamptz
) to authenticated, service_role;

comment on function public.listar_lotes_admin(uuid) is
  'Listagem administrativa de lotes de um evento (ADMINISTRADOR), com vendidos/disponiveis calculados.';
comment on function public.criar_lote_admin(
  uuid, text, integer, numeric, public.tipo_ativacao_lote, timestamptz
) is 'Cria lote real (ADMINISTRADOR). Ordem automatica; nasce INATIVO.';
