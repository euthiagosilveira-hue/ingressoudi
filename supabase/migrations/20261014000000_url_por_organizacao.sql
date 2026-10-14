-- =============================================================================
-- Ingressoudi - Fase 3A: URL e catalogo por organizacao
--  * organizacoes.logo_url
--  * slugs de organizacao reservados (rotas do app)
--  * slug do evento unico POR organizacao (antes: global)
--  * RPCs publicas por organizacao + resolver de links antigos
--  * checkout/ingressos devolvem dados da organizacao (marca e links)
-- =============================================================================

-- 1) LOGO DA ORGANIZACAO ------------------------------------------------------------
alter table public.organizacoes
  add column logo_url text null,
  add constraint ck_organizacoes_logo_url check (
    logo_url is null or logo_url ~* '^(https://|/)' 
  );

-- 2) SLUGS RESERVADOS -------------------------------------------------------------
create or replace function private.slug_organizacao_reservado(p_slug text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lower(coalesce(p_slug, '')) = any (array['admin', 'api', 'app', 'auth', 'cadastro', 'configuracoes', 'contato', 'dashboard-teste', 'entradas', 'eventos', 'eventos-publicos', 'financeiro', 'ingresso', 'ingressos', 'lista-vip', 'login', 'meus-ingressos', 'painel', 'pedidos', 'plataforma', 'portaria', 'privacidade', 'recuperar-ingressos', 'sobre', 'suporte', 'termos', 'www', '_nuxt']::text[]);
$$;

revoke all on function private.slug_organizacao_reservado(text) from public, anon;
grant execute on function private.slug_organizacao_reservado(text) to authenticated, service_role;

do $$
declare
  v_lista text;
begin
  select string_agg(slug, ', ') into v_lista
    from public.organizacoes
   where private.slug_organizacao_reservado(slug);
  if v_lista is not null then
    raise exception 'Organizacoes com slug reservado (renomeie antes de aplicar): %', v_lista;
  end if;
end
$$;

alter table public.organizacoes
  add constraint ck_organizacoes_slug_reservado check (not private.slug_organizacao_reservado(slug));

-- 3) SLUG DO EVENTO UNICO POR ORGANIZACAO ----------------------------------------------
alter table public.eventos drop constraint uq_eventos_slug;
alter table public.eventos
  add constraint uq_eventos_organizacao_slug unique (organizacao_id, slug);

CREATE OR REPLACE FUNCTION private.atualizar_evento_admin(p_evento_id uuid, p_nome text, p_slug text, p_descricao text DEFAULT NULL::text, p_imagem_url text DEFAULT NULL::text, p_inicio_em timestamp with time zone DEFAULT NULL::timestamp with time zone, p_local text DEFAULT NULL::text, p_endereco text DEFAULT NULL::text, p_capacidade_total integer DEFAULT NULL::integer, p_estoque_antecipado integer DEFAULT NULL::integer, p_publicacao_status status_publicacao DEFAULT NULL::status_publicacao, p_vendas_status status_vendas DEFAULT NULL::status_vendas)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_evento public.eventos%rowtype;
  v_slug text;
  v_capacidade integer := coalesce(p_capacidade_total, 0);
  v_estoque integer := coalesce(p_estoque_antecipado, 0);
  v_ocupados integer;
  v_publicado_em timestamptz;
  v_descricao text;
  v_imagem text;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  -- [multiempresa] evento precisa ser da organizacao ativa
  if not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  select * into v_evento from public.eventos e where e.id = p_evento_id for update;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if v_evento.status in ('REALIZADO', 'CANCELADO') then
    raise exception 'Evento % nao pode ser editado (status=%)', p_evento_id, v_evento.status using errcode = '23514';
  end if;

  if p_nome is null or btrim(p_nome) = '' then
    raise exception 'Informe o nome do evento' using errcode = '23514';
  end if;
  if p_local is null or btrim(p_local) = '' then
    raise exception 'Informe o local' using errcode = '23514';
  end if;
  if p_endereco is null or btrim(p_endereco) = '' then
    raise exception 'Informe o endereco' using errcode = '23514';
  end if;
  if p_inicio_em is null then
    raise exception 'Informe a data de inicio' using errcode = '23514';
  end if;
  if v_capacidade <= 0 then
    raise exception 'A capacidade deve ser maior que zero' using errcode = '23514';
  end if;
  if v_estoque < 0 then
    raise exception 'O estoque nao pode ser negativo' using errcode = '23514';
  end if;
  if v_estoque > v_capacidade then
    raise exception 'O estoque nao pode exceder a capacidade total' using errcode = '23514';
  end if;

  if p_imagem_url is not null and btrim(p_imagem_url) ~* '^(blob:|data:)' then
    raise exception 'URL de imagem invalida' using errcode = '23514';
  end if;

  select count(*) into v_ocupados
    from public.ingressos i
    join public.pedidos p on p.id = i.pedido_id
   where i.evento_id = p_evento_id
     and (
       i.status in ('VALIDO', 'UTILIZADO')
       or (i.status = 'RESERVADO' and p.status = 'RESERVADO' and p.reserva_expira_em > now())
     );
  if v_capacidade < v_ocupados then
    raise exception 'A capacidade nao pode ser menor que os ingressos ja emitidos/reservados (%)', v_ocupados using errcode = '23514';
  end if;
  if v_estoque < v_ocupados then
    raise exception 'O estoque nao pode ser menor que os ingressos ja emitidos/reservados (%)', v_ocupados using errcode = '23514';
  end if;

  v_slug := btrim(
    regexp_replace(
      lower(
        translate(
          btrim(coalesce(p_slug, '')),
          U&'\00E1\00E0\00E2\00E3\00E4\00E9\00E8\00EA\00EB\00ED\00EC\00EE\00EF\00F3\00F2\00F4\00F5\00F6\00FA\00F9\00FB\00FC\00E7\00F1',
          'aaaaaeeeeiiiiooooouuuucn'
        )
      ),
      '[^a-z0-9]+', '-', 'g'
    ),
    '-'
  );
  if v_slug = '' then
    raise exception 'Informe o slug' using errcode = '23514';
  end if;

  v_descricao := nullif(btrim(coalesce(p_descricao, '')), '');
  v_imagem := nullif(btrim(coalesce(p_imagem_url, '')), '');

  if exists (
    select 1 from public.eventos e
     where e.slug = v_slug and e.id <> p_evento_id
       and e.organizacao_id = v_evento.organizacao_id
  ) then
    raise exception 'Ja existe um evento com esse endereco de URL' using errcode = '23505';
  end if;

  v_publicado_em := v_evento.publicado_em;
  if p_publicacao_status = 'PUBLICADO' and v_publicado_em is null then
    v_publicado_em := now();
  end if;

  update public.eventos
     set nome = btrim(p_nome),
         slug = v_slug,
         descricao = v_descricao,
         imagem_url = v_imagem,
         inicio_em = p_inicio_em,
         local = btrim(p_local),
         endereco = btrim(p_endereco),
         capacidade_total = v_capacidade,
         estoque_antecipado = v_estoque,
         publicacao_status = coalesce(p_publicacao_status, publicacao_status),
         publicado_em = v_publicado_em,
         atualizado_em = now()
   where id = p_evento_id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values (
    auth.uid(),
    'EVENTO_ATUALIZADO_ADMIN',
    'eventos',
    p_evento_id,
    jsonb_build_object(
      'nome', v_evento.nome,
      'slug', v_evento.slug,
      'capacidade_total', v_evento.capacidade_total,
      'estoque_antecipado', v_evento.estoque_antecipado,
      'publicacao_status', v_evento.publicacao_status,
      'inicio_em', v_evento.inicio_em
    ),
    jsonb_build_object(
      'nome', btrim(p_nome),
      'slug', v_slug,
      'capacidade_total', v_capacidade,
      'estoque_antecipado', v_estoque,
      'publicacao_status', coalesce(p_publicacao_status, v_evento.publicacao_status),
      'inicio_em', p_inicio_em
    )
  );

  if p_vendas_status is not null then
    perform private.definir_vendas_evento_admin(p_evento_id, p_vendas_status);
  end if;

  return jsonb_build_object(
    'evento_id', p_evento_id,
    'slug', v_slug,
    'nome', btrim(p_nome),
    'publicacao_status', coalesce(p_publicacao_status, v_evento.publicacao_status),
    'vendas_status', coalesce(p_vendas_status, v_evento.vendas_status)
  );
end;
$function$;

-- 4) RPCS PUBLICAS POR ORGANIZACAO ----------------------------------------------------
create or replace function private.obter_organizacao_publica(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('organizacao_id', o.id, 'nome', o.nome, 'slug', o.slug, 'logo_url', o.logo_url)
    from public.organizacoes o
   where o.slug = lower(btrim(coalesce(p_slug, '')))
     and o.ativo
   limit 1;
$$;

create or replace function public.obter_organizacao_publica(p_slug text)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.obter_organizacao_publica(p_slug); $$;

create or replace function private.listar_eventos_publicos_organizacao(p_org_slug text)
returns table(evento_id uuid, slug text, nome text, descricao text, imagem_url text, inicio_em timestamp with time zone, local text, endereco text, status public.status_evento, vendas_status public.status_vendas, lote_id uuid, lote_nome text, preco numeric, situacao_venda text)
language sql
stable
security definer
set search_path = ''
as $$
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
    and e.publicacao_status = 'PUBLICADO'
    and e.status = 'AGENDADO'
    and e.inicio_em >= now()
  order by e.inicio_em asc;
$$;

create or replace function public.listar_eventos_publicos_organizacao(p_org_slug text)
returns table(evento_id uuid, slug text, nome text, descricao text, imagem_url text, inicio_em timestamp with time zone, local text, endereco text, status public.status_evento, vendas_status public.status_vendas, lote_id uuid, lote_nome text, preco numeric, situacao_venda text)
language sql stable security invoker set search_path = ''
as $$ select * from private.listar_eventos_publicos_organizacao(p_org_slug); $$;

create or replace function private.obter_evento_publico_organizacao(p_org_slug text, p_evento_slug text)
returns table(evento_id uuid, slug text, nome text, descricao text, imagem_url text, inicio_em timestamp with time zone, local text, endereco text, status public.status_evento, vendas_status public.status_vendas, lote_id uuid, lote_nome text, preco numeric, situacao_venda text, taxa_servico numeric, taxa_repassada boolean,
              organizacao_slug text, organizacao_nome text, organizacao_logo_url text)
language sql
stable
security definer
set search_path = ''
as $$
  select
    e.id, e.slug, e.nome, e.descricao, e.imagem_url, e.inicio_em, e.local, e.endereco,
    e.status, e.vendas_status,
    l.id, l.nome, l.preco,
    private.calcular_situacao_venda(e.id),
    case when e.taxa_repassada then o.taxa_servico else 0 end,
    e.taxa_repassada,
    o.slug, o.nome, o.logo_url
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
    and e.slug = lower(btrim(coalesce(p_evento_slug, '')))
    and e.publicacao_status = 'PUBLICADO'
  limit 1;
$$;

create or replace function public.obter_evento_publico_organizacao(p_org_slug text, p_evento_slug text)
returns table(evento_id uuid, slug text, nome text, descricao text, imagem_url text, inicio_em timestamp with time zone, local text, endereco text, status public.status_evento, vendas_status public.status_vendas, lote_id uuid, lote_nome text, preco numeric, situacao_venda text, taxa_servico numeric, taxa_repassada boolean,
              organizacao_slug text, organizacao_nome text, organizacao_logo_url text)
language sql stable security invoker set search_path = ''
as $$ select * from private.obter_evento_publico_organizacao(p_org_slug, p_evento_slug); $$;

-- Links antigos /eventos/{slug}: so resolve quando ha UM unico evento publicado com o slug.
create or replace function private.resolver_evento_publico(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when count(*) = 1
              then jsonb_build_object('organizacao_slug', min(o.slug), 'evento_slug', min(e.slug))
         end
    from public.eventos e
    join public.organizacoes o on o.id = e.organizacao_id
   where e.slug = lower(btrim(coalesce(p_slug, '')))
     and e.publicacao_status = 'PUBLICADO'
     and o.ativo;
$$;

create or replace function public.resolver_evento_publico(p_slug text)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.resolver_evento_publico(p_slug); $$;

-- 5) CHECKOUT / INGRESSOS COM DADOS DA ORGANIZACAO ------------------------------------
CREATE OR REPLACE FUNCTION private.obter_checkout_pedido(p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_pedido public.pedidos%rowtype;
  v_evento public.eventos%rowtype;
  v_org public.organizacoes%rowtype;
  v_lote public.lotes%rowtype;
  v_pag public.pagamentos%rowtype;
  v_pag_json jsonb;
begin
  select * into v_pedido
    from public.pedidos p
   where p.checkout_token = p_token
   limit 1;

  if not found then
    return null;
  end if;

  select * into v_evento from public.eventos e where e.id = v_pedido.evento_id;

  select * into v_org from public.organizacoes o where o.id = v_evento.organizacao_id;

  if v_pedido.lote_id is not null then
    select * into v_lote from public.lotes l where l.id = v_pedido.lote_id;
  end if;

  select * into v_pag from public.pagamentos pg where pg.pedido_id = v_pedido.id limit 1;

  if found then
    v_pag_json := jsonb_build_object(
      'pagamento_id', v_pag.id,
      'provedor', v_pag.provedor,
      'status', v_pag.status,
      'valor', v_pag.valor,
      'expira_em', v_pag.expira_em,
      'transacao_id', v_pag.transacao_id,
      'cobranca_id', v_pag.cobranca_id,
      'referencia_externa', v_pag.referencia_externa
    );
  else
    v_pag_json := null;
  end if;

  return jsonb_build_object(
    'pedido_id', v_pedido.id,
    'codigo_pedido', v_pedido.codigo,
    'evento_id', v_pedido.evento_id,
    'evento_slug', v_evento.slug,
    'organizacao_slug', v_org.slug,
    'organizacao_nome', v_org.nome,
    'organizacao_logo_url', v_org.logo_url,
    'evento_nome', v_evento.nome,
    'lote_id', v_pedido.lote_id,
    'lote_nome', v_lote.nome,
    'quantidade', v_pedido.quantidade,
    'valor_unitario', v_pedido.valor_unitario,
    'valor_ingressos', v_pedido.valor_unitario * v_pedido.quantidade,
    'taxa_servico_unitaria', v_pedido.taxa_servico_unitaria,
    'taxa_repassada', v_pedido.taxa_repassada,
    'valor_taxa_total', v_pedido.valor_taxa_total,
    'valor_total', v_pedido.valor_total,
    'pedido_status', v_pedido.status,
    'reserva_expira_em', v_pedido.reserva_expira_em,
    'pagamento', v_pag_json
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.obter_ingressos_checkout(p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_pedido public.pedidos%rowtype;
  v_evento public.eventos%rowtype;
  v_org public.organizacoes%rowtype;
  v_disponivel boolean := false;
  v_ingressos jsonb := '[]'::jsonb;
begin
  if p_token is null then
    return null;
  end if;

  select * into v_pedido
    from public.pedidos p
   where p.checkout_token = p_token
   limit 1;

  if not found then
    return null;
  end if;

  select * into v_evento
    from public.eventos e
   where e.id = v_pedido.evento_id;

  select * into v_org from public.organizacoes o where o.id = v_evento.organizacao_id;

  v_disponivel := v_pedido.status = 'PAGO'
    and exists (
      select 1
        from public.pagamentos pg
       where pg.pedido_id = v_pedido.id
         and pg.status = 'APROVADO'
    );

  if v_disponivel then
    select coalesce(
             jsonb_agg(
               jsonb_build_object(
                 'ingresso_id', i.id,
                 'codigo', i.codigo,
                 'participante_nome', i.participante_nome,
                 'status', i.status,
                 -- QR utilizavel somente para ingresso apto a entrar.
                 'qr_token',
                   case
                     when i.status in ('VALIDO', 'UTILIZADO') then i.qr_token
                     else null
                   end,
                 'utilizado_em', i.utilizado_em
               ) order by i.codigo
             ),
             '[]'::jsonb
           )
      into v_ingressos
      from public.ingressos i
     where i.pedido_id = v_pedido.id
       and i.status in ('VALIDO', 'UTILIZADO', 'CANCELADO');
  end if;

  return jsonb_build_object(
    'pedido_id', v_pedido.id,
    'codigo_pedido', v_pedido.codigo,
    'evento_id', v_pedido.evento_id,
    'evento_slug', v_evento.slug,
    'organizacao_slug', v_org.slug,
    'organizacao_nome', v_org.nome,
    'organizacao_logo_url', v_org.logo_url,
    'evento_nome', v_evento.nome,
    'evento_inicio_em', v_evento.inicio_em,
    'evento_local', v_evento.local,
    'evento_endereco', v_evento.endereco,
    'pedido_status', v_pedido.status,
    'disponivel', v_disponivel,
    'ingressos', v_ingressos
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.montar_ingressos_pedido(p_pedido_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_pedido public.pedidos%rowtype;
  v_evento public.eventos%rowtype;
  v_org public.organizacoes%rowtype;
  v_disponivel boolean := false;
  v_ingressos jsonb := '[]'::jsonb;
begin
  select * into v_pedido from public.pedidos p where p.id = p_pedido_id;
  if not found then
    return null;
  end if;

  select * into v_evento from public.eventos e where e.id = v_pedido.evento_id;

  select * into v_org from public.organizacoes o where o.id = v_evento.organizacao_id;

  v_disponivel := v_pedido.status = 'PAGO'
    and exists (
      select 1 from public.pagamentos pg
       where pg.pedido_id = v_pedido.id and pg.status = 'APROVADO'
    );

  if v_disponivel then
    select coalesce(
             jsonb_agg(
               jsonb_build_object(
                 'ingresso_id', i.id,
                 'codigo', i.codigo,
                 'participante_nome', i.participante_nome,
                 'status', i.status,
                 'qr_token',
                   case when i.status in ('VALIDO', 'UTILIZADO') then i.qr_token else null end,
                 'utilizado_em', i.utilizado_em
               ) order by i.codigo
             ),
             '[]'::jsonb
           )
      into v_ingressos
      from public.ingressos i
     where i.pedido_id = v_pedido.id
       and i.status in ('VALIDO', 'UTILIZADO', 'CANCELADO');
  end if;

  return jsonb_build_object(
    'pedido_id', v_pedido.id,
    'codigo_pedido', v_pedido.codigo,
    'evento_id', v_pedido.evento_id,
    'evento_slug', v_evento.slug,
    'organizacao_slug', v_org.slug,
    'organizacao_nome', v_org.nome,
    'organizacao_logo_url', v_org.logo_url,
    'evento_nome', v_evento.nome,
    'evento_inicio_em', v_evento.inicio_em,
    'evento_local', v_evento.local,
    'evento_endereco', v_evento.endereco,
    'pedido_status', v_pedido.status,
    'disponivel', v_disponivel,
    'ingressos', v_ingressos
  );
end;
$function$;

-- 6) PERMISSOES ------------------------------------------------------------------
revoke all on function private.obter_organizacao_publica(text) from public;
revoke all on function private.listar_eventos_publicos_organizacao(text) from public;
revoke all on function private.obter_evento_publico_organizacao(text, text) from public;
revoke all on function private.resolver_evento_publico(text) from public;
grant execute on function private.obter_organizacao_publica(text) to anon, authenticated, service_role;
grant execute on function private.listar_eventos_publicos_organizacao(text) to anon, authenticated, service_role;
grant execute on function private.obter_evento_publico_organizacao(text, text) to anon, authenticated, service_role;
grant execute on function private.resolver_evento_publico(text) to anon, authenticated, service_role;

revoke all on function public.obter_organizacao_publica(text) from public;
revoke all on function public.listar_eventos_publicos_organizacao(text) from public;
revoke all on function public.obter_evento_publico_organizacao(text, text) from public;
revoke all on function public.resolver_evento_publico(text) from public;
grant execute on function public.obter_organizacao_publica(text) to anon, authenticated, service_role;
grant execute on function public.listar_eventos_publicos_organizacao(text) to anon, authenticated, service_role;
grant execute on function public.obter_evento_publico_organizacao(text, text) to anon, authenticated, service_role;
grant execute on function public.resolver_evento_publico(text) to anon, authenticated, service_role;
