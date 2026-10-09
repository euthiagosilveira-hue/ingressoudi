-- =============================================================================
-- GZ1 Ingresso - Portaria atomica
-- Migration: portaria_atomica
--
-- Escopo:
--   * registrar entrada por QR Code
--   * registrar entrada por nome (apos busca)
--   * registrar tentativas (validas e invalidas)
--   * impedir dupla utilizacao concorrente (lock + uq_entradas_ingresso_ativa)
--   * anular entrada (somente ADMINISTRADOR) + auditoria
--
-- Fora do escopo: RLS, policies, frontend, realtime, cron, Mercado Pago.
--
-- Linguagem plpgsql/sql. SECURITY INVOKER (default), SET search_path = '',
-- objetos qualificados com public. Nao ha DROP/DELETE/TRUNCATE destrutivo.
--
-- Observacao de seguranca: como RLS/auth ainda nao existem, as RPCs recebem
-- p_usuario_id e validam em public.usuarios (existe, ativo, perfil). Quando a
-- autenticacao for integrada, a identidade deve vir da sessao e nao do cliente.
-- As funcoes auxiliares public.validar_operador e public.processar_entrada
-- ficam no schema public e, sem grants/RLS, tambem sao expostas pelo PostgREST;
-- processar_entrada revalida usuario internamente para nao ser bypass.
-- =============================================================================

-- VALIDAR OPERADOR ------------------------------------------------------------
-- Existe, ativo e perfil permitido. p_somente_admin = true -> apenas ADMIN.
create or replace function public.validar_operador(
  p_usuario_id uuid,
  p_somente_admin boolean default false
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_ativo boolean;
  v_perfil public.perfil_usuario;
begin
  select u.ativo, u.perfil
    into v_ativo, v_perfil
    from public.usuarios u
   where u.id = p_usuario_id;

  if not found then
    raise exception 'Usuario % nao encontrado', p_usuario_id using errcode = '23503';
  end if;

  if not v_ativo then
    raise exception 'Usuario % inativo', p_usuario_id using errcode = '42501';
  end if;

  if p_somente_admin then
    if v_perfil <> 'ADMINISTRADOR' then
      raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
    end if;
  else
    if v_perfil not in ('ADMINISTRADOR', 'PORTARIA') then
      raise exception 'Perfil % sem permissao de portaria', v_perfil using errcode = '42501';
    end if;
  end if;
end;
$$;

-- PROCESSAR ENTRADA (nucleo compartilhado) ------------------------------------
-- Ordem: lock ingresso -> evento incorreto -> status do evento ->
--        status do ingresso -> entrada ativa -> cria entrada -> atualiza ->
--        tentativa.
create or replace function public.processar_entrada(
  p_evento_id uuid,
  p_ingresso_id uuid,
  p_usuario_id uuid,
  p_metodo public.metodo_validacao
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_ingresso public.ingressos%rowtype;
  v_evento public.eventos%rowtype;
  v_entrada_ativa public.entradas%rowtype;
  v_ts timestamptz := now();
  v_entrada_id uuid;
begin
  perform public.validar_operador(p_usuario_id, false);

  -- lock do ingresso (protecao contra dupla utilizacao concorrente)
  select * into v_ingresso
    from public.ingressos i
   where i.id = p_ingresso_id
   for update;

  if not found then
    insert into public.tentativas_entrada
      (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values
      (p_evento_id, null, p_usuario_id, p_metodo, 'NAO_ENCONTRADO', 'INGRESSO_NAO_ENCONTRADO');
    return jsonb_build_object(
      'resultado', 'NAO_ENCONTRADO', 'ingresso_id', null, 'codigo', null,
      'participante_nome', null, 'entrada_id', null, 'entrada_em', null,
      'mensagem', 'Ingresso nao encontrado'
    );
  end if;

  -- ingresso de outro evento tem precedencia sobre status do evento
  if v_ingresso.evento_id <> p_evento_id then
    insert into public.tentativas_entrada
      (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values
      (v_ingresso.evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'EVENTO_INCORRETO', 'INGRESSO_DE_OUTRO_EVENTO');
    return jsonb_build_object(
      'resultado', 'EVENTO_INCORRETO', 'ingresso_id', v_ingresso.id,
      'codigo', v_ingresso.codigo, 'participante_nome', v_ingresso.participante_nome,
      'entrada_id', null, 'entrada_em', null,
      'mensagem', 'Ingresso pertence a outro evento'
    );
  end if;

  select * into v_evento from public.eventos e where e.id = p_evento_id;

  if v_evento.status = 'CANCELADO' then
    insert into public.tentativas_entrada
      (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values
      (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'CANCELADO', 'EVENTO_CANCELADO');
    return jsonb_build_object(
      'resultado', 'CANCELADO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo,
      'participante_nome', v_ingresso.participante_nome, 'entrada_id', null,
      'entrada_em', null, 'mensagem', 'Evento cancelado'
    );
  elsif v_evento.status = 'REALIZADO' then
    insert into public.tentativas_entrada
      (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values
      (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'INVALIDO', 'EVENTO_REALIZADO');
    return jsonb_build_object(
      'resultado', 'INVALIDO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo,
      'participante_nome', v_ingresso.participante_nome, 'entrada_id', null,
      'entrada_em', null, 'mensagem', 'Evento ja realizado'
    );
  elsif v_evento.status = 'AGENDADO' and now() < v_evento.inicio_em then
    insert into public.tentativas_entrada
      (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values
      (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'INVALIDO', 'EVENTO_NAO_INICIADO');
    return jsonb_build_object(
      'resultado', 'INVALIDO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo,
      'participante_nome', v_ingresso.participante_nome, 'entrada_id', null,
      'entrada_em', null, 'mensagem', 'Evento ainda nao iniciado'
    );
  end if;

  -- status do ingresso
  if v_ingresso.status = 'CANCELADO' then
    insert into public.tentativas_entrada
      (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values
      (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'CANCELADO', 'INGRESSO_CANCELADO');
    return jsonb_build_object(
      'resultado', 'CANCELADO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo,
      'participante_nome', v_ingresso.participante_nome, 'entrada_id', null,
      'entrada_em', null, 'mensagem', 'Ingresso cancelado'
    );
  elsif v_ingresso.status = 'EXPIRADO' then
    insert into public.tentativas_entrada
      (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values
      (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'INVALIDO', 'INGRESSO_EXPIRADO');
    return jsonb_build_object(
      'resultado', 'INVALIDO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo,
      'participante_nome', v_ingresso.participante_nome, 'entrada_id', null,
      'entrada_em', null, 'mensagem', 'Ingresso expirado'
    );
  elsif v_ingresso.status = 'RESERVADO' then
    insert into public.tentativas_entrada
      (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values
      (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'INVALIDO', 'INGRESSO_NAO_PAGO');
    return jsonb_build_object(
      'resultado', 'INVALIDO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo,
      'participante_nome', v_ingresso.participante_nome, 'entrada_id', null,
      'entrada_em', null, 'mensagem', 'Ingresso ainda nao pago'
    );
  end if;

  -- entrada ativa existente -> ja utilizado
  select * into v_entrada_ativa
    from public.entradas en
   where en.ingresso_id = v_ingresso.id
     and en.anulada_em is null
   limit 1;

  if found then
    insert into public.tentativas_entrada
      (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values
      (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'JA_UTILIZADO', null);
    return jsonb_build_object(
      'resultado', 'JA_UTILIZADO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo,
      'participante_nome', v_ingresso.participante_nome, 'entrada_id', v_entrada_ativa.id,
      'entrada_em', v_entrada_ativa.entrada_em, 'mensagem', 'Ingresso ja utilizado'
    );
  end if;

  if v_ingresso.status = 'UTILIZADO' then
    insert into public.tentativas_entrada
      (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values
      (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'JA_UTILIZADO', null);
    return jsonb_build_object(
      'resultado', 'JA_UTILIZADO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo,
      'participante_nome', v_ingresso.participante_nome, 'entrada_id', null,
      'entrada_em', null, 'mensagem', 'Ingresso ja utilizado'
    );
  end if;

  if v_ingresso.status <> 'VALIDO' then
    insert into public.tentativas_entrada
      (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values
      (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'INVALIDO', 'STATUS_NAO_PERMITIDO');
    return jsonb_build_object(
      'resultado', 'INVALIDO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo,
      'participante_nome', v_ingresso.participante_nome, 'entrada_id', null,
      'entrada_em', null, 'mensagem', 'Ingresso nao esta valido'
    );
  end if;

  -- cria entrada, atualiza ingresso e registra tentativa (mesmo timestamp)
  insert into public.entradas
    (ingresso_id, evento_id, usuario_id, metodo_validacao, entrada_em)
  values
    (v_ingresso.id, p_evento_id, p_usuario_id, p_metodo, v_ts)
  returning id into v_entrada_id;

  update public.ingressos
     set status = 'UTILIZADO',
         utilizado_em = v_ts
   where id = v_ingresso.id;

  insert into public.tentativas_entrada
    (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
  values
    (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'LIBERADO', null);

  return jsonb_build_object(
    'resultado', 'LIBERADO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo,
    'participante_nome', v_ingresso.participante_nome, 'entrada_id', v_entrada_id,
    'entrada_em', v_ts, 'mensagem', 'Entrada liberada'
  );
end;
$$;

-- REGISTRAR ENTRADA POR QR ----------------------------------------------------
create or replace function public.registrar_entrada_qr(
  p_evento_id uuid,
  p_qr_token text,
  p_usuario_id uuid
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_ingresso public.ingressos%rowtype;
begin
  perform public.validar_operador(p_usuario_id, false);

  perform 1 from public.eventos e where e.id = p_evento_id;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if p_qr_token is null or btrim(p_qr_token) = '' then
    insert into public.tentativas_entrada
      (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values
      (p_evento_id, null, p_usuario_id, 'QR_CODE', 'NAO_ENCONTRADO', 'QR_VAZIO');
    return jsonb_build_object(
      'resultado', 'NAO_ENCONTRADO', 'ingresso_id', null, 'codigo', null,
      'participante_nome', null, 'entrada_id', null, 'entrada_em', null,
      'mensagem', 'QR nao informado'
    );
  end if;

  select * into v_ingresso
    from public.ingressos i
   where i.qr_token = p_qr_token;

  if not found then
    insert into public.tentativas_entrada
      (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values
      (p_evento_id, null, p_usuario_id, 'QR_CODE', 'NAO_ENCONTRADO', 'QR_NAO_ENCONTRADO');
    return jsonb_build_object(
      'resultado', 'NAO_ENCONTRADO', 'ingresso_id', null, 'codigo', null,
      'participante_nome', null, 'entrada_id', null, 'entrada_em', null,
      'mensagem', 'QR nao encontrado'
    );
  end if;

  return public.processar_entrada(p_evento_id, v_ingresso.id, p_usuario_id, 'QR_CODE');
end;
$$;

-- REGISTRAR ENTRADA POR NOME --------------------------------------------------
create or replace function public.registrar_entrada_nome(
  p_evento_id uuid,
  p_ingresso_id uuid,
  p_usuario_id uuid
)
returns jsonb
language plpgsql
set search_path = ''
as $$
begin
  perform public.validar_operador(p_usuario_id, false);

  perform 1 from public.eventos e where e.id = p_evento_id;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  return public.processar_entrada(p_evento_id, p_ingresso_id, p_usuario_id, 'NOME');
end;
$$;

-- BUSCAR INGRESSOS POR NOME ---------------------------------------------------
-- Igualdade case-insensitive com trim. Sem busca fuzzy.
create or replace function public.buscar_ingressos_por_nome(
  p_evento_id uuid,
  p_nome text
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'ingresso_id', i.id,
               'codigo', i.codigo,
               'participante_nome', i.participante_nome,
               'status', i.status,
               'utilizado_em', i.utilizado_em
             ) order by i.participante_nome, i.codigo
           ),
           '[]'::jsonb
         )
    from public.ingressos i
   where i.evento_id = p_evento_id
     and lower(btrim(i.participante_nome)) = lower(btrim(p_nome));
$$;

-- ANULAR ENTRADA --------------------------------------------------------------
create or replace function public.anular_entrada(
  p_entrada_id uuid,
  p_usuario_id uuid,
  p_motivo text
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_entrada public.entradas%rowtype;
  v_ingresso public.ingressos%rowtype;
  v_outras integer;
  v_ts timestamptz := now();
begin
  perform public.validar_operador(p_usuario_id, true);

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'motivo da anulacao obrigatorio' using errcode = '23514';
  end if;

  select * into v_entrada
    from public.entradas e
   where e.id = p_entrada_id
   for update;

  if not found then
    raise exception 'Entrada % nao encontrada', p_entrada_id using errcode = '23503';
  end if;

  if v_entrada.anulada_em is not null then
    return jsonb_build_object(
      'resultado', 'JA_ANULADA', 'entrada_id', v_entrada.id,
      'ingresso_id', v_entrada.ingresso_id, 'mensagem', 'Entrada ja anulada'
    );
  end if;

  select * into v_ingresso
    from public.ingressos i
   where i.id = v_entrada.ingresso_id
   for update;

  update public.entradas
     set anulada_em = v_ts,
         anulada_por_usuario_id = p_usuario_id,
         motivo_anulacao = p_motivo
   where id = p_entrada_id;

  select count(*)
    into v_outras
    from public.entradas en
   where en.ingresso_id = v_entrada.ingresso_id
     and en.anulada_em is null
     and en.id <> p_entrada_id;

  if v_outras = 0 then
    update public.ingressos
       set status = 'VALIDO',
           utilizado_em = null
     where id = v_entrada.ingresso_id;
  end if;

  insert into public.auditoria
    (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values
    (
      p_usuario_id,
      'ENTRADA_ANULADA',
      'entradas',
      v_entrada.id,
      jsonb_build_object(
        'anulada_em', v_entrada.anulada_em,
        'ingresso_id', v_entrada.ingresso_id,
        'entrada_em', v_entrada.entrada_em
      ),
      jsonb_build_object(
        'anulada_em', v_ts,
        'anulada_por_usuario_id', p_usuario_id,
        'motivo_anulacao', p_motivo
      )
    );

  return jsonb_build_object(
    'resultado', 'ANULADA', 'entrada_id', v_entrada.id,
    'ingresso_id', v_entrada.ingresso_id, 'ingresso_status', 'VALIDO',
    'anulada_em', v_ts, 'mensagem', 'Entrada anulada'
  );
end;
$$;
