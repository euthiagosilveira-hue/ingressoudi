-- =============================================================================
-- Ingressoudi - Venda online continua ate 3 horas depois do inicio do evento
--
-- Antes: o link de venda parava exatamente no horario de inicio (inicio_em).
-- Agora: a compra online segue aberta ate inicio_em + 3 horas, desde que as
-- vendas do evento estejam ABERTAS (o produtor continua podendo encerrar a
-- venda a qualquer momento pelo painel).
--
--  * private.fim_vendas_online(inicio): unico lugar com o prazo de 3 horas.
--  * private.criar_reserva: aceita evento EM_ANDAMENTO e usa o novo prazo.
--  * private.calcular_situacao_venda: evento EM_ANDAMENTO com vendas abertas
--    dentro do prazo aparece como disponivel.
--  * listar_eventos_publicos(_organizacao): o evento segue na vitrine ate o fim
--    do prazo.
--  * private.processar_inicio_eventos: ao iniciar, nao fecha mais as vendas;
--    fecha so os eventos cujo prazo de venda online ja passou.
-- =============================================================================

create or replace function private.fim_vendas_online(p_inicio_em timestamptz)
returns timestamptz
language sql
immutable
set search_path to ''
as $$
  select p_inicio_em + interval '3 hours';
$$;

revoke all on function private.fim_vendas_online(timestamptz) from public, anon, authenticated;

-- 1) RESERVA ONLINE -------------------------------------------------------------
-- criar_reserva e grande; troca apenas as duas checagens de status/horario.
do $$
declare
  v_def text;
  v_status_antigo text := 'if v_evento.status <> ''AGENDADO'' then';
  v_status_novo   text := 'if v_evento.status not in (''AGENDADO'', ''EM_ANDAMENTO'') then';
  v_hora_antiga   text := 'if now() >= v_evento.inicio_em then';
  v_hora_nova     text := 'if now() >= private.fim_vendas_online(v_evento.inicio_em) then';
begin
  v_def := pg_get_functiondef('private.criar_reserva(uuid,text,text,text,text[],boolean[])'::regprocedure);

  -- Ja aplicada (migracao reexecutada): nada a fazer.
  if position(v_hora_nova in v_def) > 0 and position(v_status_novo in v_def) > 0 then
    return;
  end if;

  if position(v_status_antigo in v_def) = 0 or position(v_hora_antiga in v_def) = 0 then
    raise exception 'criar_reserva nao tem o texto esperado; migracao abortada';
  end if;

  v_def := replace(v_def, v_status_antigo, v_status_novo);
  v_def := replace(v_def, v_hora_antiga, v_hora_nova);
  execute v_def;
end;
$$;

-- 2) SITUACAO DE VENDA (pagina publica, vitrine, checkout) -------------------------
create or replace function private.calcular_situacao_venda(p_evento_id uuid)
returns text
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_e public.eventos%rowtype;
  v_lote_id uuid;
  v_disp_e integer;
  v_disp_l integer;
begin
  select * into v_e from public.eventos e where e.id = p_evento_id;
  if not found then
    return null;
  end if;

  if v_e.status = 'CANCELADO' then
    return 'CANCELADO';
  end if;
  if v_e.status = 'REALIZADO' then
    return 'ENCERRADO';
  end if;

  -- Passou o prazo da venda online (ou o produtor encerrou as vendas).
  if v_e.vendas_status <> 'ABERTAS' or now() >= private.fim_vendas_online(v_e.inicio_em) then
    if v_e.status = 'EM_ANDAMENTO' then
      return 'EVENTO_EM_ANDAMENTO';
    end if;
    return 'VENDAS_ENCERRADAS';
  end if;

  select l.id into v_lote_id
    from public.lotes l
   where l.evento_id = v_e.id and l.status = 'ATIVO'
   limit 1;

  if v_lote_id is null then
    return 'SEM_LOTE';
  end if;

  v_disp_e := private.calcular_disponibilidade_evento(v_e.id);
  if v_disp_e <= 0 then
    return 'ESGOTADO';
  end if;

  v_disp_l := private.calcular_disponibilidade_lote(v_lote_id);
  if v_disp_l <= 0 then
    return 'ESGOTADO';
  end if;

  return 'DISPONIVEL';
end;
$function$;

-- 3) VITRINES PUBLICAS ------------------------------------------------------------
create or replace function private.listar_eventos_publicos()
returns table(evento_id uuid, slug text, nome text, descricao text, imagem_url text, inicio_em timestamptz, local text, endereco text, status public.status_evento, vendas_status public.status_vendas, lote_id uuid, lote_nome text, preco numeric, situacao_venda text)
language sql
stable security definer
set search_path to ''
as $function$
  select
    e.id, e.slug, e.nome, e.descricao, e.imagem_url, e.inicio_em, e.local, e.endereco,
    e.status, e.vendas_status,
    l.id, l.nome, l.preco,
    private.calcular_situacao_venda(e.id)
  from public.eventos e
  left join lateral (
    select lo.id, lo.nome, lo.preco
      from public.lotes lo
     where lo.evento_id = e.id and lo.status = 'ATIVO'
     limit 1
  ) l on true
  where e.publicacao_status = 'PUBLICADO'
    and (e.status = 'AGENDADO' or (e.status = 'EM_ANDAMENTO' and e.vendas_status = 'ABERTAS'))
    and private.fim_vendas_online(e.inicio_em) > now()
  order by e.inicio_em asc;
$function$;

create or replace function private.listar_eventos_publicos_organizacao(p_org_slug text)
returns table(evento_id uuid, slug text, nome text, descricao text, imagem_url text, inicio_em timestamptz, local text, endereco text, status public.status_evento, vendas_status public.status_vendas, lote_id uuid, lote_nome text, preco numeric, situacao_venda text)
language sql
stable security definer
set search_path to ''
as $function$
  select
    e.id, e.slug, e.nome, e.descricao, e.imagem_url, e.inicio_em, e.local, e.endereco,
    e.status, e.vendas_status,
    l.id, l.nome, l.preco,
    private.calcular_situacao_venda(e.id)
  from public.eventos e
  join public.organizacoes o on o.id = e.organizacao_id
  left join lateral (
    select lo.id, lo.nome, lo.preco
      from public.lotes lo
     where lo.evento_id = e.id and lo.status = 'ATIVO'
     limit 1
  ) l on true
  where o.slug = lower(btrim(coalesce(p_org_slug, '')))
    and o.ativo
    and o.aprovada
    and e.publicacao_status = 'PUBLICADO'
    and (e.status = 'AGENDADO' or (e.status = 'EM_ANDAMENTO' and e.vendas_status = 'ABERTAS'))
    and private.fim_vendas_online(e.inicio_em) > now()
  order by e.inicio_em asc;
$function$;

-- 4) INICIO AUTOMATICO DOS EVENTOS -------------------------------------------------
create or replace function private.processar_inicio_eventos(p_evento_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_rec record;
  v_ts timestamptz;
  v_iniciados jsonb := '[]'::jsonb;
  v_vendas_encerradas jsonb := '[]'::jsonb;
begin
  -- Inicia o evento, mas mantem as vendas como estao (a venda online segue
  -- ate private.fim_vendas_online).
  for v_rec in
    select e.id from public.eventos e
     where e.status = 'AGENDADO' and e.inicio_em <= now()
       and (p_evento_id is null or e.id = p_evento_id)
     order by e.id for update
  loop
    v_ts := now();
    update public.eventos set status = 'EM_ANDAMENTO' where id = v_rec.id;
    insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos)
    values (null, 'EVENTO_INICIADO', 'eventos', v_rec.id,
      jsonb_build_object('status', 'EM_ANDAMENTO', 'iniciado_em', v_ts));
    v_iniciados := v_iniciados || jsonb_build_object('evento_id', v_rec.id);
  end loop;

  -- Fecha as vendas de quem ja passou do prazo da venda online.
  for v_rec in
    select e.id from public.eventos e
     where e.status in ('AGENDADO', 'EM_ANDAMENTO') and e.vendas_status = 'ABERTAS'
       and private.fim_vendas_online(e.inicio_em) <= now()
       and (p_evento_id is null or e.id = p_evento_id)
     order by e.id for update
  loop
    update public.eventos set vendas_status = 'ENCERRADAS' where id = v_rec.id;
    insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos)
    values (null, 'VENDAS_ENCERRADAS_PRAZO', 'eventos', v_rec.id,
      jsonb_build_object('vendas_status', 'ENCERRADAS', 'encerrado_em', now()));
    v_vendas_encerradas := v_vendas_encerradas || jsonb_build_object('evento_id', v_rec.id);
  end loop;

  return jsonb_build_object(
    'iniciados', jsonb_array_length(v_iniciados), 'eventos', v_iniciados,
    'vendas_encerradas', jsonb_array_length(v_vendas_encerradas));
end;
$function$;
