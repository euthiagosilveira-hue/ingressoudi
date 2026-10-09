-- =============================================================================
-- GZ1 Ingresso - Bloquear automacoes de lote em eventos finalizados
-- Migration: bloquear_automacoes_evento_finalizado
--
-- Correcao defensiva (defesa em profundidade): eventos CANCELADO e REALIZADO
-- nao podem sofrer automacao de lote, mesmo que a funcao seja chamada
-- diretamente e mesmo que exista lote ATIVO indevido.
--
-- Funcoes substituidas (CREATE OR REPLACE, mesma assinatura):
--   * public.processar_virada_lote_esgotamento(uuid)
--   * public.processar_viradas_lote_por_data(uuid default null)
--   * public.processar_manutencao_eventos()
--
-- Nao altera criar_reserva, ativar_lote_manual, encerrar_evento,
-- processar_reservas_expiradas, processar_inicio_eventos, regras de
-- disponibilidade, sequencia, indices, triggers, RLS ou policies.
-- SECURITY INVOKER (default), SET search_path = '', objetos qualificados.
-- Sem DROP/DELETE/TRUNCATE destrutivo.
-- =============================================================================

-- VIRADA POR ESGOTAMENTO (protecao CANCELADO/REALIZADO) ----------------------
create or replace function public.processar_virada_lote_esgotamento(p_evento_id uuid)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_evento public.eventos%rowtype;
  v_ativo public.lotes%rowtype;
  v_prox public.lotes%rowtype;
  v_disp_lote integer;
  v_disp_evento integer;
  v_ts timestamptz := now();
begin
  select * into v_evento from public.eventos e where e.id = p_evento_id for update;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if v_evento.status = 'CANCELADO' then
    return jsonb_build_object('resultado', 'EVENTO_CANCELADO');
  end if;

  if v_evento.status = 'REALIZADO' then
    return jsonb_build_object('resultado', 'EVENTO_REALIZADO');
  end if;

  select * into v_ativo
    from public.lotes l
   where l.evento_id = p_evento_id
     and l.status = 'ATIVO'
   for update;

  if not found then
    return jsonb_build_object('resultado', 'SEM_LOTE_ATIVO');
  end if;

  v_disp_lote := public.calcular_disponibilidade_lote(v_ativo.id);
  if v_disp_lote > 0 then
    return jsonb_build_object('resultado', 'SEM_VIRADA', 'disponibilidade_lote', v_disp_lote);
  end if;

  -- lote esgotado: se o estoque global tambem acabou, nao abre lote novo
  v_disp_evento := public.calcular_disponibilidade_evento(p_evento_id);
  if v_disp_evento <= 0 then
    return jsonb_build_object('resultado', 'ESTOQUE_EVENTO_ESGOTADO');
  end if;

  select * into v_prox
    from public.lotes l
   where l.evento_id = p_evento_id
     and l.status = 'INATIVO'
     and l.tipo_ativacao = 'ESGOTAMENTO'
     and l.ordem > v_ativo.ordem
   order by l.ordem asc
   limit 1
   for update;

  if not found then
    update public.lotes set status = 'ENCERRADO', encerrado_em = v_ts where id = v_ativo.id;
    return jsonb_build_object('resultado', 'ESGOTADO_SEM_PROXIMO_LOTE', 'lote_encerrado_id', v_ativo.id);
  end if;

  update public.lotes set status = 'ENCERRADO', encerrado_em = v_ts where id = v_ativo.id;
  update public.lotes
     set status = 'ATIVO', ativado_em = v_ts, encerrado_em = null
   where id = v_prox.id;

  insert into public.auditoria
    (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values
    (
      null, 'LOTE_VIRADO_POR_ESGOTAMENTO', 'lotes', v_prox.id,
      jsonb_build_object('lote_anterior_id', v_ativo.id, 'lote_anterior_ordem', v_ativo.ordem),
      jsonb_build_object('lote_novo_id', v_prox.id, 'lote_novo_ordem', v_prox.ordem, 'ativado_em', v_ts)
    );

  return jsonb_build_object(
    'resultado', 'VIRADO',
    'lote_anterior_id', v_ativo.id,
    'lote_novo_id', v_prox.id,
    'lote_novo_ordem', v_prox.ordem
  );
end;
$$;

-- VIRADA POR DATA/HORA (protecao CANCELADO/REALIZADO) -------------------------
create or replace function public.processar_viradas_lote_por_data(p_evento_id uuid default null)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_rec record;
  v_evento public.eventos%rowtype;
  v_ativo public.lotes%rowtype;
  v_cand public.lotes%rowtype;
  v_ordem_ref integer;
  v_ts timestamptz;
  v_viradas jsonb := '[]'::jsonb;
begin
  for v_rec in
    select distinct l.evento_id
      from public.lotes l
     where l.status = 'INATIVO'
       and l.tipo_ativacao = 'DATA_HORA'
       and l.ativacao_em <= now()
       and (p_evento_id is null or l.evento_id = p_evento_id)
  loop
    select * into v_evento from public.eventos e where e.id = v_rec.evento_id for update;

    -- eventos finalizados nao recebem automacao de lote
    if v_evento.status in ('CANCELADO', 'REALIZADO') then
      continue;
    end if;

    select * into v_ativo
      from public.lotes l
     where l.evento_id = v_rec.evento_id
       and l.status = 'ATIVO'
     for update;

    v_ordem_ref := coalesce(v_ativo.ordem, 0);

    -- maior ordem entre os DATA_HORA vencidos, a frente do lote ativo
    select * into v_cand
      from public.lotes l
     where l.evento_id = v_rec.evento_id
       and l.status = 'INATIVO'
       and l.tipo_ativacao = 'DATA_HORA'
       and l.ativacao_em <= now()
       and l.ordem > v_ordem_ref
     order by l.ordem desc
     limit 1
     for update;

    if not found then
      continue;
    end if;

    v_ts := now();

    if v_ativo.id is not null then
      update public.lotes set status = 'ENCERRADO', encerrado_em = v_ts where id = v_ativo.id;
    end if;

    update public.lotes
       set status = 'ATIVO', ativado_em = v_ts, encerrado_em = null
     where id = v_cand.id;

    insert into public.auditoria
      (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
    values
      (
        null, 'LOTE_VIRADO_POR_DATA', 'lotes', v_cand.id,
        jsonb_build_object('lote_anterior_id', v_ativo.id, 'lote_anterior_ordem', v_ativo.ordem),
        jsonb_build_object('lote_novo_id', v_cand.id, 'lote_novo_ordem', v_cand.ordem, 'ativado_em', v_ts)
      );

    v_viradas := v_viradas || jsonb_build_object(
      'evento_id', v_rec.evento_id,
      'lote_anterior_id', v_ativo.id,
      'lote_novo_id', v_cand.id
    );
  end loop;

  return jsonb_build_object('viradas', v_viradas, 'total', jsonb_array_length(v_viradas));
end;
$$;

-- MANUTENCAO CENTRAL (ignora CANCELADO/REALIZADO nas etapas de lote) ----------
create or replace function public.processar_manutencao_eventos()
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_reservas jsonb;
  v_data jsonb;
  v_esgotamento jsonb := '[]'::jsonb;
  v_inicio jsonb;
  v_rec record;
begin
  v_reservas := public.processar_reservas_expiradas(null);

  v_data := public.processar_viradas_lote_por_data(null);

  -- apenas eventos nao finalizados, mesmo que tenham lote ATIVO indevido
  for v_rec in
    select l.evento_id
      from public.lotes l
      join public.eventos e on e.id = l.evento_id
     where l.status = 'ATIVO'
       and e.status not in ('CANCELADO', 'REALIZADO')
     group by l.evento_id
  loop
    v_esgotamento := v_esgotamento || public.processar_virada_lote_esgotamento(v_rec.evento_id);
  end loop;

  v_inicio := public.processar_inicio_eventos(null);

  return jsonb_build_object(
    'reservas_expiradas', v_reservas,
    'lotes_por_data', v_data,
    'lotes_por_esgotamento', v_esgotamento,
    'eventos_iniciados', v_inicio
  );
end;
$$;
