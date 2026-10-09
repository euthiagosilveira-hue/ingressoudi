-- =============================================================================
-- GZ1 Ingresso - Edicao segura de lote (ADMINISTRADOR)
-- Migration: editar_lote_admin
--
--   public.atualizar_lote_admin(p_lote_id, p_nome, p_quantidade, p_preco,
--                              p_tipo_ativacao, p_ativacao_em)
--
-- Regras de dominio:
--   - ENCERRADO: nao pode ser editado
--   - ATIVO: edita apenas nome/quantidade/preco (tipo/ativacao preservados)
--   - INATIVO: edita tudo; DATA_HORA exige ativacao_em; MANUAL/ESGOTAMENTO
--     zeram ativacao_em
--   - quantidade nunca abaixo do comprometido (mesma regra de disponibilidade)
--   - nao altera evento_id, ordem, status, ativado_em, encerrado_em
--   - historico de pedidos/ingressos preservado (preco so vale para novas compras)
--   - FOR UPDATE serializa com criar_reserva (evita corrida/negativo)
-- =============================================================================

create or replace function private.atualizar_lote_admin(
  p_lote_id uuid,
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
  v_lote public.lotes%rowtype;
  v_comprometido integer;
  v_tipo public.tipo_ativacao_lote;
  v_ativacao timestamptz;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select * into v_lote from public.lotes l where l.id = p_lote_id for update;
  if not found then
    raise exception 'Lote % nao encontrado', p_lote_id using errcode = '23503';
  end if;

  if v_lote.status = 'ENCERRADO' then
    raise exception 'Lotes encerrados nao podem ser editados' using errcode = '23514';
  end if;

  if p_nome is null or btrim(p_nome) = '' then
    raise exception 'Informe o nome do lote' using errcode = '23514';
  end if;
  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'A quantidade deve ser maior que zero' using errcode = '23514';
  end if;
  if p_preco is null or p_preco < 0 then
    raise exception 'O preco nao pode ser negativo' using errcode = '23514';
  end if;

  -- Comprometido = quantidade atual - disponibilidade atual (mesma regra do dominio).
  v_comprometido := v_lote.quantidade - coalesce(private.calcular_disponibilidade_lote(p_lote_id), v_lote.quantidade);
  if p_quantidade < v_comprometido then
    raise exception 'A quantidade nao pode ser menor que os ingressos ja comprometidos (%)', v_comprometido
      using errcode = '23514';
  end if;

  if v_lote.status = 'ATIVO' then
    -- Regra de ativacao ja consumida: preserva tipo/ativacao.
    v_tipo := v_lote.tipo_ativacao;
    v_ativacao := v_lote.ativacao_em;
  else
    v_tipo := coalesce(p_tipo_ativacao, v_lote.tipo_ativacao);
    if v_tipo = 'DATA_HORA' then
      if p_ativacao_em is null then
        raise exception 'Informe a data e hora de ativacao' using errcode = '23514';
      end if;
      v_ativacao := p_ativacao_em;
    else
      v_ativacao := null;
    end if;
  end if;

  update public.lotes
     set nome = btrim(p_nome),
         quantidade = p_quantidade,
         preco = p_preco,
         tipo_ativacao = v_tipo,
         ativacao_em = v_ativacao
   where id = p_lote_id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values (
    auth.uid(),
    'LOTE_ATUALIZADO',
    'lotes',
    p_lote_id,
    jsonb_build_object(
      'nome', v_lote.nome,
      'quantidade', v_lote.quantidade,
      'preco', v_lote.preco,
      'tipo_ativacao', v_lote.tipo_ativacao,
      'ativacao_em', v_lote.ativacao_em
    ),
    jsonb_build_object(
      'nome', btrim(p_nome),
      'quantidade', p_quantidade,
      'preco', p_preco,
      'tipo_ativacao', v_tipo,
      'ativacao_em', v_ativacao
    )
  );

  return jsonb_build_object(
    'lote_id', p_lote_id,
    'evento_id', v_lote.evento_id,
    'nome', btrim(p_nome),
    'ordem', v_lote.ordem,
    'quantidade', p_quantidade,
    'preco', p_preco,
    'tipo_ativacao', v_tipo,
    'ativacao_em', v_ativacao,
    'status', v_lote.status
  );
end;
$$;

create or replace function public.atualizar_lote_admin(
  p_lote_id uuid,
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
  select private.atualizar_lote_admin(p_lote_id, p_nome, p_quantidade, p_preco, p_tipo_ativacao, p_ativacao_em);
$$;

revoke all on function private.atualizar_lote_admin(
  uuid, text, integer, numeric, public.tipo_ativacao_lote, timestamptz
) from public;
grant execute on function private.atualizar_lote_admin(
  uuid, text, integer, numeric, public.tipo_ativacao_lote, timestamptz
) to authenticated, service_role;

revoke execute on function public.atualizar_lote_admin(
  uuid, text, integer, numeric, public.tipo_ativacao_lote, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.atualizar_lote_admin(
  uuid, text, integer, numeric, public.tipo_ativacao_lote, timestamptz
) to authenticated, service_role;

comment on function public.atualizar_lote_admin(
  uuid, text, integer, numeric, public.tipo_ativacao_lote, timestamptz
) is 'Edita um lote real (ADMINISTRADOR). ENCERRADO bloqueado; ATIVO com restricoes; historico preservado.';
