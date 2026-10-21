-- =============================================================================
-- Ingressoudi - CRM comercial (Plataforma, somente super admin)
-- crm_produtores: produtores em prospeccao, com a etapa do funil e a proxima
-- acao. Quando o produtor ja tem casa na plataforma (organizacao_id), eventos,
-- ingressos e receita vem dos dados reais da casa.
-- crm_historico: cada mudanca de etapa, para os indicadores por periodo.
-- Sem acesso direto pelo navegador: tudo passa pelas RPCs abaixo, que exigem
-- private.usuario_e_super_admin().
-- =============================================================================

create table public.crm_produtores (
  id uuid primary key default gen_random_uuid(),
  nome_produtor text not null,
  empresa_evento text null,
  instagram text null,
  whatsapp text null,
  cidade text null,
  tipo_evento text null,
  ultimo_contato date null,
  etapa text not null default 'MAPEADO',
  proxima_acao text null,
  proxima_acao_em date null,
  observacoes text null,
  organizacao_id uuid null
    constraint fk_crm_produtores_organizacao references public.organizacoes (id) on delete set null,
  criado_por uuid null
    constraint fk_crm_produtores_criado_por references public.usuarios (id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint ck_crm_produtores_nome check (btrim(nome_produtor) <> ''),
  constraint ck_crm_produtores_etapa check (etapa in (
    'MAPEADO', 'CONTATADO', 'INTERESSADO', 'DEMO_AGENDADA', 'DEMO_REALIZADA',
    'CADASTRO_INICIADO', 'EVENTO_PUBLICADO', 'PRIMEIRA_VENDA', 'CLIENTE_RECORRENTE'))
);

create unique index uq_crm_produtores_organizacao on public.crm_produtores (organizacao_id)
  where organizacao_id is not null;
create index idx_crm_produtores_proxima_acao on public.crm_produtores (proxima_acao_em);

create trigger trg_crm_produtores_atualizado_em
  before update on public.crm_produtores
  for each row execute function public.definir_atualizado_em();

create table public.crm_historico (
  id uuid primary key default gen_random_uuid(),
  produtor_id uuid not null
    constraint fk_crm_historico_produtor references public.crm_produtores (id) on delete cascade,
  etapa_anterior text null,
  etapa_nova text not null,
  usuario_id uuid null
    constraint fk_crm_historico_usuario references public.usuarios (id) on delete set null,
  em timestamptz not null default now()
);

create index idx_crm_historico_produtor on public.crm_historico (produtor_id, em);

alter table public.crm_produtores enable row level security;
alter table public.crm_historico enable row level security;
revoke all on table public.crm_produtores from public, anon, authenticated;
revoke all on table public.crm_historico from public, anon, authenticated;
grant select, insert, update, delete on table public.crm_produtores to service_role;
grant select, insert, update, delete on table public.crm_historico to service_role;

-- Posicao da etapa no funil (1 = Mapeado ... 9 = Cliente recorrente) ----------------
create or replace function private.crm_etapa_ordem(p_etapa text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select array_position(array[
    'MAPEADO', 'CONTATADO', 'INTERESSADO', 'DEMO_AGENDADA', 'DEMO_REALIZADA',
    'CADASTRO_INICIADO', 'EVENTO_PUBLICADO', 'PRIMEIRA_VENDA', 'CLIENTE_RECORRENTE'], p_etapa);
$$;

create or replace function private.crm_exigir_super_admin()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not private.usuario_e_super_admin() then
    raise exception 'Permissao negada: apenas super administrador' using errcode = '42501';
  end if;
end;
$$;

-- Numeros reais de cada casa ligada ao CRM ------------------------------------------
create or replace function private.crm_numeros_casa(p_organizacao_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'eventos_publicados', (
      select count(*) from public.eventos e
       where e.organizacao_id = p_organizacao_id
         and (e.publicado_em is not null or e.publicacao_status = 'PUBLICADO')),
    'ingressos_vendidos', coalesce((
      select sum(p.quantidade) from public.pedidos p
       where p.organizacao_id = p_organizacao_id and p.status = 'PAGO'), 0),
    'receita_gerada', coalesce((
      select sum(p.valor_total) from public.pedidos p
       where p.organizacao_id = p_organizacao_id and p.status = 'PAGO'), 0)
  );
$$;

-- Lista do CRM ------------------------------------------------------------------------
create or replace function private.crm_listar_produtores()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.crm_exigir_super_admin();

  return coalesce((
    select jsonb_agg(
             jsonb_build_object(
               'id', c.id,
               'nome_produtor', c.nome_produtor,
               'empresa_evento', c.empresa_evento,
               'instagram', c.instagram,
               'whatsapp', c.whatsapp,
               'cidade', c.cidade,
               'tipo_evento', c.tipo_evento,
               'ultimo_contato', c.ultimo_contato,
               'etapa', c.etapa,
               'proxima_acao', c.proxima_acao,
               'proxima_acao_em', c.proxima_acao_em,
               'observacoes', c.observacoes,
               'organizacao_id', c.organizacao_id,
               'organizacao_nome', o.nome,
               'organizacao_slug', o.slug,
               'criado_em', c.criado_em,
               'atualizado_em', c.atualizado_em
             ) || case when c.organizacao_id is null
                       then jsonb_build_object('eventos_publicados', 0, 'ingressos_vendidos', 0, 'receita_gerada', 0)
                       else private.crm_numeros_casa(c.organizacao_id) end
             order by c.proxima_acao_em nulls last, c.atualizado_em desc)
      from public.crm_produtores c
      left join public.organizacoes o on o.id = c.organizacao_id
  ), '[]'::jsonb);
end;
$$;

-- Criar ou editar um produtor ----------------------------------------------------------
-- p_id null cria. p_dados: os campos do CRM (texto vazio vira null).
create or replace function private.crm_salvar_produtor(p_id uuid, p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_atual public.crm_produtores%rowtype;
  v_nome text := nullif(btrim(p_dados->>'nome_produtor'), '');
  v_etapa text := coalesce(nullif(btrim(p_dados->>'etapa'), ''), 'MAPEADO');
  v_org uuid := nullif(btrim(p_dados->>'organizacao_id'), '')::uuid;
  v_id uuid;
begin
  perform private.crm_exigir_super_admin();

  if v_nome is null then
    raise exception 'Informe o nome do produtor' using errcode = '23514';
  end if;
  if private.crm_etapa_ordem(v_etapa) is null then
    raise exception 'Etapa invalida: %', v_etapa using errcode = '23514';
  end if;
  if v_org is not null then
    if not exists (select 1 from public.organizacoes o where o.id = v_org) then
      raise exception 'Organizacao % nao encontrada', v_org using errcode = '23503';
    end if;
    if exists (select 1 from public.crm_produtores c
                where c.organizacao_id = v_org and c.id is distinct from p_id) then
      raise exception 'Essa casa ja esta ligada a outro produtor do CRM' using errcode = '23505';
    end if;
  end if;

  if p_id is null then
    insert into public.crm_produtores (
      nome_produtor, empresa_evento, instagram, whatsapp, cidade, tipo_evento,
      ultimo_contato, etapa, proxima_acao, proxima_acao_em, observacoes, organizacao_id, criado_por)
    values (
      left(v_nome, 160),
      left(nullif(btrim(p_dados->>'empresa_evento'), ''), 160),
      left(nullif(btrim(p_dados->>'instagram'), ''), 160),
      left(nullif(btrim(p_dados->>'whatsapp'), ''), 40),
      left(nullif(btrim(p_dados->>'cidade'), ''), 120),
      left(nullif(btrim(p_dados->>'tipo_evento'), ''), 120),
      nullif(btrim(p_dados->>'ultimo_contato'), '')::date,
      v_etapa,
      left(nullif(btrim(p_dados->>'proxima_acao'), ''), 300),
      nullif(btrim(p_dados->>'proxima_acao_em'), '')::date,
      left(nullif(btrim(p_dados->>'observacoes'), ''), 4000),
      v_org,
      v_uid)
    returning id into v_id;

    insert into public.crm_historico (produtor_id, etapa_anterior, etapa_nova, usuario_id)
    values (v_id, null, v_etapa, v_uid);
  else
    select * into v_atual from public.crm_produtores c where c.id = p_id for update;
    if not found then
      raise exception 'Produtor % nao encontrado', p_id using errcode = '23503';
    end if;

    update public.crm_produtores c
       set nome_produtor = left(v_nome, 160),
           empresa_evento = left(nullif(btrim(p_dados->>'empresa_evento'), ''), 160),
           instagram = left(nullif(btrim(p_dados->>'instagram'), ''), 160),
           whatsapp = left(nullif(btrim(p_dados->>'whatsapp'), ''), 40),
           cidade = left(nullif(btrim(p_dados->>'cidade'), ''), 120),
           tipo_evento = left(nullif(btrim(p_dados->>'tipo_evento'), ''), 120),
           ultimo_contato = nullif(btrim(p_dados->>'ultimo_contato'), '')::date,
           etapa = v_etapa,
           proxima_acao = left(nullif(btrim(p_dados->>'proxima_acao'), ''), 300),
           proxima_acao_em = nullif(btrim(p_dados->>'proxima_acao_em'), '')::date,
           observacoes = left(nullif(btrim(p_dados->>'observacoes'), ''), 4000),
           organizacao_id = v_org
     where c.id = p_id;

    if v_atual.etapa <> v_etapa then
      insert into public.crm_historico (produtor_id, etapa_anterior, etapa_nova, usuario_id)
      values (p_id, v_atual.etapa, v_etapa, v_uid);
    end if;
    v_id := p_id;
  end if;

  return jsonb_build_object('id', v_id);
end;
$$;

create or replace function private.crm_excluir_produtor(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.crm_exigir_super_admin();
  delete from public.crm_produtores c where c.id = p_id;
  if not found then
    raise exception 'Produtor % nao encontrado', p_id using errcode = '23503';
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

-- Trazer para o CRM as casas que ja estao na plataforma ---------------------------------
-- Cada casa ainda fora do CRM vira um produtor, com o dono como contato e a etapa
-- pelo que a casa ja fez (cadastro, evento publicado, venda, mais de um evento).
create or replace function private.crm_importar_casas()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_org record;
  v_dono uuid;
  v_nome text;
  v_numeros jsonb;
  v_etapa text;
  v_id uuid;
  v_total integer := 0;
begin
  perform private.crm_exigir_super_admin();

  for v_org in
    select o.id, o.nome from public.organizacoes o
     where not exists (select 1 from public.crm_produtores c where c.organizacao_id = o.id)
     order by o.criado_em
  loop
    select coalesce(
             (select a.usuario_id from public.auditoria a
               where a.acao = 'ORGANIZACAO_CADASTRADA' and a.entidade_id = v_org.id
               order by a.criado_em limit 1),
             (select m.usuario_id from public.membros_organizacao m
               where m.organizacao_id = v_org.id and m.ativo and m.perfil = 'ADMINISTRADOR'
               order by m.criado_em limit 1))
      into v_dono;
    select u.nome into v_nome from public.usuarios u where u.id = v_dono;

    v_numeros := private.crm_numeros_casa(v_org.id);
    v_etapa := case
      when (v_numeros->>'eventos_publicados')::int >= 2 and (v_numeros->>'ingressos_vendidos')::int > 0
        then 'CLIENTE_RECORRENTE'
      when (v_numeros->>'ingressos_vendidos')::int > 0 then 'PRIMEIRA_VENDA'
      when (v_numeros->>'eventos_publicados')::int > 0 then 'EVENTO_PUBLICADO'
      else 'CADASTRO_INICIADO'
    end;

    insert into public.crm_produtores (nome_produtor, empresa_evento, etapa, organizacao_id, criado_por)
    values (coalesce(nullif(btrim(v_nome), ''), v_org.nome), v_org.nome, v_etapa, v_org.id, v_uid)
    returning id into v_id;
    insert into public.crm_historico (produtor_id, etapa_anterior, etapa_nova, usuario_id)
    values (v_id, null, v_etapa, v_uid);
    v_total := v_total + 1;
  end loop;

  return jsonb_build_object('importados', v_total);
end;
$$;

-- Indicadores --------------------------------------------------------------------------
-- Funil atual (quantos estao em cada etapa) e, no periodo, quantos produtores
-- chegaram pela primeira vez a cada etapa ou alem (pular etapas conta as anteriores).
-- Datas no fuso de Sao Paulo. Periodo null = desde o inicio.
-- Eventos, ingressos e receita liquida: casas ligadas ao CRM, no periodo
-- (evento pela data de publicacao, venda pela data do pagamento).
create or replace function private.crm_indicadores(p_inicio date default null, p_fim date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ini timestamptz := case when p_inicio is null then null
                            else (p_inicio::timestamp at time zone 'America/Sao_Paulo') end;
  v_fim timestamptz := case when p_fim is null then null
                            else ((p_fim + 1)::timestamp at time zone 'America/Sao_Paulo') end;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_funil jsonb;
  v_negocio jsonb;
  v_acoes jsonb;
begin
  perform private.crm_exigir_super_admin();
  if p_inicio is not null and p_fim is not null and p_fim < p_inicio then
    raise exception 'Periodo invalido' using errcode = '22007';
  end if;

  with etapas(etapa, ordem) as (
    select e, o from unnest(array[
      'MAPEADO', 'CONTATADO', 'INTERESSADO', 'DEMO_AGENDADA', 'DEMO_REALIZADA',
      'CADASTRO_INICIADO', 'EVENTO_PUBLICADO', 'PRIMEIRA_VENDA', 'CLIENTE_RECORRENTE'])
      with ordinality as t(e, o)
  ),
  chegadas as (
    select et.ordem, h.produtor_id, min(h.em) as em
      from etapas et
      join public.crm_historico h on private.crm_etapa_ordem(h.etapa_nova) >= et.ordem
     group by et.ordem, h.produtor_id
  )
  select jsonb_agg(jsonb_build_object(
           'etapa', et.etapa,
           'atual', (select count(*) from public.crm_produtores c where c.etapa = et.etapa),
           'alcancaram', (select count(*) from chegadas ch
                           where ch.ordem = et.ordem
                             and (v_ini is null or ch.em >= v_ini)
                             and (v_fim is null or ch.em < v_fim))
         ) order by et.ordem)
    into v_funil
    from etapas et;

  with casas as (
    select distinct c.organizacao_id as id from public.crm_produtores c where c.organizacao_id is not null
  ),
  pagos as (
    select p.quantidade, p.valor_total, p.valor_taxa_total,
           exists (select 1 from public.pagamentos g
                    where g.pedido_id = p.id and g.status = 'APROVADO' and g.provedor = 'MERCADO_PAGO') as online
      from public.pedidos p
      join casas on casas.id = p.organizacao_id
     where p.status = 'PAGO'
       and (v_ini is null or coalesce(p.pago_em, p.criado_em) >= v_ini)
       and (v_fim is null or coalesce(p.pago_em, p.criado_em) < v_fim)
  )
  select jsonb_build_object(
           'eventos_publicados', (
             select count(*) from public.eventos e join casas on casas.id = e.organizacao_id
              where e.publicado_em is not null
                and (v_ini is null or e.publicado_em >= v_ini)
                and (v_fim is null or e.publicado_em < v_fim)),
           'ingressos_vendidos', coalesce((select sum(quantidade) from pagos), 0),
           'valor_vendido', coalesce((select sum(valor_total) from pagos), 0),
           'receita_liquida', coalesce((select sum(valor_taxa_total) from pagos where online), 0))
    into v_negocio;

  select jsonb_build_object(
           'atrasadas', count(*) filter (where c.proxima_acao_em < v_hoje),
           'hoje', count(*) filter (where c.proxima_acao_em = v_hoje),
           'total_produtores', count(*))
    into v_acoes
    from public.crm_produtores c;

  return jsonb_build_object('funil', coalesce(v_funil, '[]'::jsonb), 'negocio', v_negocio, 'acoes', v_acoes);
end;
$$;

-- Wrappers publicos -------------------------------------------------------------------
create or replace function public.crm_listar_produtores()
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.crm_listar_produtores(); $$;

create or replace function public.crm_salvar_produtor(p_id uuid, p_dados jsonb)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.crm_salvar_produtor(p_id, p_dados); $$;

create or replace function public.crm_excluir_produtor(p_id uuid)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.crm_excluir_produtor(p_id); $$;

create or replace function public.crm_importar_casas()
returns jsonb language sql security invoker set search_path = ''
as $$ select private.crm_importar_casas(); $$;

create or replace function public.crm_indicadores(p_inicio date default null, p_fim date default null)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.crm_indicadores(p_inicio, p_fim); $$;

revoke all on function private.crm_etapa_ordem(text) from public, anon;
revoke all on function private.crm_exigir_super_admin() from public, anon;
revoke all on function private.crm_numeros_casa(uuid) from public, anon, authenticated;
revoke all on function private.crm_listar_produtores() from public, anon;
revoke all on function private.crm_salvar_produtor(uuid, jsonb) from public, anon;
revoke all on function private.crm_excluir_produtor(uuid) from public, anon;
revoke all on function private.crm_importar_casas() from public, anon;
revoke all on function private.crm_indicadores(date, date) from public, anon;
revoke all on function public.crm_listar_produtores() from public, anon;
revoke all on function public.crm_salvar_produtor(uuid, jsonb) from public, anon;
revoke all on function public.crm_excluir_produtor(uuid) from public, anon;
revoke all on function public.crm_importar_casas() from public, anon;
revoke all on function public.crm_indicadores(date, date) from public, anon;

grant execute on function private.crm_etapa_ordem(text) to authenticated, service_role;
grant execute on function private.crm_exigir_super_admin() to authenticated, service_role;
grant execute on function private.crm_numeros_casa(uuid) to service_role;
grant execute on function private.crm_listar_produtores() to authenticated, service_role;
grant execute on function private.crm_salvar_produtor(uuid, jsonb) to authenticated, service_role;
grant execute on function private.crm_excluir_produtor(uuid) to authenticated, service_role;
grant execute on function private.crm_importar_casas() to authenticated, service_role;
grant execute on function private.crm_indicadores(date, date) to authenticated, service_role;
grant execute on function public.crm_listar_produtores() to authenticated, service_role;
grant execute on function public.crm_salvar_produtor(uuid, jsonb) to authenticated, service_role;
grant execute on function public.crm_excluir_produtor(uuid) to authenticated, service_role;
grant execute on function public.crm_importar_casas() to authenticated, service_role;
grant execute on function public.crm_indicadores(date, date) to authenticated, service_role;
