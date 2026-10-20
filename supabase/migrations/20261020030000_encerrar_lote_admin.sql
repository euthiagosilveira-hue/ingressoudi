-- =============================================================================
-- Ingressoudi - Encerrar lote manualmente pelo painel
-- 1) encerrar_lote_admin(p_lote_id, p_ativar_proximo): o ADMINISTRADOR da
--    organizacao encerra o lote ATIVO agora. Opcionalmente ativa o proximo lote
--    INATIVO (menor ordem acima do encerrado), se as vendas estiverem abertas.
-- 2) Reservas ja abertas do lote encerrado continuam valendo: o Pix que o
--    comprador ja recebeu ainda pode ser pago (confirmar_pagamento nao olha o
--    status do lote). Se ainda houver ingressos, o lote pode ser reativado.
-- =============================================================================

create or replace function private.encerrar_lote_admin(p_lote_id uuid, p_ativar_proximo boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lote public.lotes%rowtype;
  v_evento public.eventos%rowtype;
  v_prox public.lotes%rowtype;
  v_usuario_id uuid;
  v_ts timestamptz := now();
begin
  v_usuario_id := auth.uid();
  if v_usuario_id is null or not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  -- [multiempresa] registro precisa ser da organizacao ativa
  if not exists (select 1 from public.lotes l where l.id = p_lote_id and l.organizacao_id = (select private.organizacao_atual_id())) then
    raise exception 'Lote % nao encontrado', p_lote_id using errcode = '23503';
  end if;

  select * into v_lote from public.lotes l where l.id = p_lote_id for update;
  if not found then
    raise exception 'Lote % nao encontrado', p_lote_id using errcode = '23503';
  end if;

  select * into v_evento from public.eventos e where e.id = v_lote.evento_id for update;
  if not found then
    raise exception 'Evento % nao encontrado', v_lote.evento_id using errcode = '23503';
  end if;

  if v_evento.status in ('REALIZADO', 'CANCELADO') then
    raise exception 'Evento % nao permite encerrar lote (status=%)', v_evento.id, v_evento.status using errcode = '23514';
  end if;

  if v_lote.status <> 'ATIVO' then
    raise exception 'Lote % nao esta ativo (status=%)', v_lote.id, v_lote.status using errcode = '23514';
  end if;

  update public.lotes set status = 'ENCERRADO', encerrado_em = v_ts where id = v_lote.id;

  if p_ativar_proximo and v_evento.vendas_status = 'ABERTAS' then
    select * into v_prox from public.lotes l
     where l.evento_id = v_lote.evento_id and l.status = 'INATIVO' and l.ordem > v_lote.ordem
     order by l.ordem
     limit 1
     for update;

    if v_prox.id is not null then
      update public.lotes set status = 'ATIVO', ativado_em = v_ts, encerrado_em = null where id = v_prox.id;
    end if;
  end if;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values (v_usuario_id, 'LOTE_ENCERRADO_MANUALMENTE', 'lotes', v_lote.id,
    jsonb_build_object('status_anterior', v_lote.status, 'ordem', v_lote.ordem),
    jsonb_build_object('lote_id', v_lote.id, 'encerrado_em', v_ts, 'lote_ativado_id', v_prox.id, 'lote_ativado_ordem', v_prox.ordem));

  return jsonb_build_object(
    'resultado', case when v_prox.id is not null then 'ENCERRADO_E_PROXIMO_ATIVADO' else 'ENCERRADO' end,
    'lote_encerrado_id', v_lote.id,
    'lote_ativado_id', v_prox.id,
    'lote_ativado_nome', v_prox.nome,
    'encerrado_em', v_ts);
end;
$$;

create or replace function public.encerrar_lote_admin(p_lote_id uuid, p_ativar_proximo boolean default false)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.encerrar_lote_admin(p_lote_id, p_ativar_proximo); $$;

revoke all on function private.encerrar_lote_admin(uuid, boolean) from public, anon;
grant execute on function private.encerrar_lote_admin(uuid, boolean) to authenticated, service_role;
revoke all on function public.encerrar_lote_admin(uuid, boolean) from public, anon;
grant execute on function public.encerrar_lote_admin(uuid, boolean) to authenticated, service_role;
