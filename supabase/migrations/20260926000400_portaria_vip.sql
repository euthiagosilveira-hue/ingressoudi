-- =============================================================================
-- GZ1 Ingresso - Portaria: busca unificada (ingresso + VIP) e entrada VIP
-- Migration: portaria_vip
--
-- 1) private.buscar_ingressos_por_nome passa a retornar, numa UNICA consulta,
--    ingressos normais e convidados da Lista VIP do evento, com discriminante
--    'origem' = 'INGRESSO' | 'VIP'. Preserva os campos antigos e a assinatura.
--
-- 2) public/private.registrar_entrada_vip(p_evento_id, p_vip_id): registra a
--    entrada do convidado VIP de forma atomica, com lock, tentativas e
--    auditoria. Permitida a ADMINISTRADOR e PORTARIA.
--
-- VIP NAO altera ingressos/pedidos/pagamentos/financeiro. A entrada fica em
-- public.entradas_vip; a tentativa (inclusive duplicada) em tentativas_entrada
-- com ingresso_id null, preservando rastreabilidade sem tocar no schema atual.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) BUSCA UNIFICADA POR NOME
-- -----------------------------------------------------------------------------
create or replace function private.buscar_ingressos_por_nome(p_evento_id uuid, p_nome text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_alvo text;
begin
  if not private.usuario_pode_operar_portaria() then
    raise exception 'Permissao negada para operar portaria' using errcode = '42501';
  end if;

  v_alvo := translate(
    lower(btrim(coalesce(p_nome, ''))),
    'áàâãäéèêëíìîïóòôõöúùûüçñ',
    'aaaaaeeeeiiiiooooouuuucn'
  );

  if v_alvo = '' then
    return '[]'::jsonb;
  end if;

  return (
    select coalesce(
             jsonb_agg(item order by item->>'participante_nome', item->>'origem'),
             '[]'::jsonb
           )
      from (
        -- Ingressos normais
        select jsonb_build_object(
                 'origem', 'INGRESSO',
                 'ingresso_id', i.id,
                 'vip_id', null,
                 'codigo', i.codigo,
                 'participante_nome', i.participante_nome,
                 'status', i.status,
                 'utilizado_em', i.utilizado_em,
                 'entrada_em', i.utilizado_em
               ) as item
          from public.ingressos i
         where i.evento_id = p_evento_id
           and not exists (
             select 1
               from unnest(string_to_array(v_alvo, ' ')) as tok
              where btrim(tok) <> ''
                and position(
                      btrim(tok) in translate(
                        lower(i.participante_nome),
                        'áàâãäéèêëíìîïóòôõöúùûüçñ',
                        'aaaaaeeeeiiiiooooouuuucn'
                      )
                    ) = 0
           )
        union all
        -- Lista VIP (apenas ativos); status derivado da entrada
        select jsonb_build_object(
                 'origem', 'VIP',
                 'ingresso_id', null,
                 'vip_id', lv.id,
                 'codigo', null,
                 'participante_nome', lv.nome,
                 'status', case when ev.id is null then 'VALIDO' else 'UTILIZADO' end,
                 'utilizado_em', ev.entrada_em,
                 'entrada_em', ev.entrada_em
               ) as item
          from public.lista_vip lv
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
           and not exists (
             select 1
               from unnest(string_to_array(v_alvo, ' ')) as tok
              where btrim(tok) <> ''
                and position(
                      btrim(tok) in translate(
                        lower(lv.nome),
                        'áàâãäéèêëíìîïóòôõöúùûüçñ',
                        'aaaaaeeeeiiiiooooouuuucn'
                      )
                    ) = 0
           )
      ) t
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 2) REGISTRAR ENTRADA VIP
-- -----------------------------------------------------------------------------
create or replace function private.registrar_entrada_vip(
  p_evento_id uuid,
  p_vip_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_vip public.lista_vip%rowtype;
  v_evento public.eventos%rowtype;
  v_entrada public.entradas_vip%rowtype;
  v_usuario_id uuid;
  v_ts timestamptz := now();
  v_entrada_id uuid;
begin
  v_usuario_id := auth.uid();
  if v_usuario_id is null or not private.usuario_pode_operar_portaria() then
    raise exception 'Permissao negada para operar portaria' using errcode = '42501';
  end if;

  perform 1 from public.eventos e where e.id = p_evento_id;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  -- lock do convidado: serializa tentativas concorrentes
  select * into v_vip
    from public.lista_vip lv
   where lv.id = p_vip_id
   for update;

  if not found then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, null, v_usuario_id, 'NOME', 'NAO_ENCONTRADO', 'VIP_NAO_ENCONTRADO');
    return jsonb_build_object(
      'resultado', 'NAO_ENCONTRADO', 'vip_id', null, 'ingresso_id', null, 'codigo', null,
      'participante_nome', null, 'entrada_id', null, 'entrada_em', null,
      'mensagem', 'Convidado VIP nao encontrado'
    );
  end if;

  if v_vip.evento_id <> p_evento_id then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (v_vip.evento_id, null, v_usuario_id, 'NOME', 'EVENTO_INCORRETO', 'VIP_DE_OUTRO_EVENTO');
    return jsonb_build_object(
      'resultado', 'EVENTO_INCORRETO', 'vip_id', v_vip.id, 'ingresso_id', null, 'codigo', null,
      'participante_nome', v_vip.nome, 'entrada_id', null, 'entrada_em', null,
      'mensagem', 'Convidado VIP pertence a outro evento'
    );
  end if;

  if not v_vip.ativo then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, null, v_usuario_id, 'NOME', 'CANCELADO', 'VIP_CANCELADO');
    return jsonb_build_object(
      'resultado', 'CANCELADO', 'vip_id', v_vip.id, 'ingresso_id', null, 'codigo', null,
      'participante_nome', v_vip.nome, 'entrada_id', null, 'entrada_em', null,
      'mensagem', 'Convidado VIP cancelado'
    );
  end if;

  select * into v_evento from public.eventos e where e.id = p_evento_id;

  if v_evento.status = 'CANCELADO' then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, null, v_usuario_id, 'NOME', 'CANCELADO', 'EVENTO_CANCELADO');
    return jsonb_build_object(
      'resultado', 'CANCELADO', 'vip_id', v_vip.id, 'ingresso_id', null, 'codigo', null,
      'participante_nome', v_vip.nome, 'entrada_id', null, 'entrada_em', null,
      'mensagem', 'Evento cancelado'
    );
  elsif v_evento.status = 'REALIZADO' then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, null, v_usuario_id, 'NOME', 'INVALIDO', 'EVENTO_REALIZADO');
    return jsonb_build_object(
      'resultado', 'INVALIDO', 'vip_id', v_vip.id, 'ingresso_id', null, 'codigo', null,
      'participante_nome', v_vip.nome, 'entrada_id', null, 'entrada_em', null,
      'mensagem', 'Evento ja realizado'
    );
  elsif v_evento.status = 'AGENDADO' and now() < v_evento.inicio_em then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, null, v_usuario_id, 'NOME', 'INVALIDO', 'EVENTO_NAO_INICIADO');
    return jsonb_build_object(
      'resultado', 'INVALIDO', 'vip_id', v_vip.id, 'ingresso_id', null, 'codigo', null,
      'participante_nome', v_vip.nome, 'entrada_id', null, 'entrada_em', null,
      'mensagem', 'Evento ainda nao iniciado'
    );
  end if;

  -- entrada efetiva existente -> dupla entrada
  select * into v_entrada
    from public.entradas_vip ev
   where ev.lista_vip_id = v_vip.id
     and ev.anulada_em is null
   order by ev.entrada_em desc
   limit 1;

  if found then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, null, v_usuario_id, 'NOME', 'JA_UTILIZADO', 'VIP_JA_UTILIZADO');
    return jsonb_build_object(
      'resultado', 'JA_UTILIZADO', 'vip_id', v_vip.id, 'ingresso_id', null, 'codigo', null,
      'participante_nome', v_vip.nome, 'entrada_id', v_entrada.id, 'entrada_em', v_entrada.entrada_em,
      'mensagem', 'Convidado VIP ja registrou entrada'
    );
  end if;

  insert into public.entradas_vip (lista_vip_id, evento_id, usuario_id, metodo_validacao, entrada_em)
  values (v_vip.id, p_evento_id, v_usuario_id, 'NOME', v_ts)
  returning id into v_entrada_id;

  insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
  values (p_evento_id, null, v_usuario_id, 'NOME', 'LIBERADO', null);

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos)
  values (
    v_usuario_id,
    'VIP_ENTRADA_REGISTRADA',
    'entradas_vip',
    v_entrada_id,
    jsonb_build_object(
      'evento_id', p_evento_id,
      'lista_vip_id', v_vip.id,
      'entrada_em', v_ts
    )
  );

  return jsonb_build_object(
    'resultado', 'LIBERADO', 'vip_id', v_vip.id, 'ingresso_id', null, 'codigo', null,
    'participante_nome', v_vip.nome, 'entrada_id', v_entrada_id, 'entrada_em', v_ts,
    'mensagem', 'Entrada liberada'
  );
end;
$$;

create or replace function public.registrar_entrada_vip(p_evento_id uuid, p_vip_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select private.registrar_entrada_vip(p_evento_id, p_vip_id); $$;

-- -----------------------------------------------------------------------------
-- ACL
-- -----------------------------------------------------------------------------
grant usage on schema private to authenticated, service_role;

-- busca agora tambem e usada pela portaria (ja existia com a mesma assinatura)
revoke all on function private.buscar_ingressos_por_nome(uuid, text) from public;
grant execute on function private.buscar_ingressos_por_nome(uuid, text) to authenticated, service_role;

revoke execute on function public.buscar_ingressos_por_nome(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.buscar_ingressos_por_nome(uuid, text) to authenticated, service_role;

revoke all on function private.registrar_entrada_vip(uuid, uuid) from public;
grant execute on function private.registrar_entrada_vip(uuid, uuid) to authenticated, service_role;

revoke execute on function public.registrar_entrada_vip(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.registrar_entrada_vip(uuid, uuid) to authenticated, service_role;

comment on function public.buscar_ingressos_por_nome(uuid, text) is
  'Busca por nome no evento (ingressos + Lista VIP), tolerante a acento/ordem. Campo origem = INGRESSO|VIP.';
comment on function public.registrar_entrada_vip(uuid, uuid) is
  'Registra entrada de convidado VIP (ADMINISTRADOR/PORTARIA). Uma entrada por convidado.';
