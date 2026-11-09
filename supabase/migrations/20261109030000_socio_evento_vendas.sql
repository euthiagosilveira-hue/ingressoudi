-- =============================================================================
-- Ingressoudi - Perfil "Socio do Evento" (parte 2 de 2)
--
-- Rodar DEPOIS da parte 1 (20261109020000_perfil_socio_evento.sql).
--
-- O socio de um evento entra com login proprio e ve SO os numeros de venda
-- dos eventos que o administrador da casa marcou para ele. Nao ve compradores,
-- nao edita nada e nao passa em nenhuma RPC administrativa ou de portaria.
--
-- 1) public.socios_eventos: quais eventos cada socio acompanha (por casa).
-- 2) listar_usuarios_admin: passa a devolver eventos_socio de cada membro.
-- 3) definir_eventos_socio_admin(p_usuario_id, p_evento_ids): o ADMINISTRADOR
--    escolhe os eventos do socio (substitui a lista inteira).
-- 4) listar_eventos_socio(): eventos do socio logado, com o resumo de vendas.
-- 5) obter_vendas_evento_socio(p_evento_id): numeros de um evento (sem nomes
--    de compradores): ingressos, bruto, taxa, liquido, por forma de pagamento,
--    por lote/setor, por dia e entradas por hora.
-- =============================================================================

-- 1) Tabela -------------------------------------------------------------------
create table if not exists public.socios_eventos (
  organizacao_id uuid not null references public.organizacoes (id) on delete cascade,
  usuario_id uuid not null references public.usuarios (id) on delete cascade,
  evento_id uuid not null references public.eventos (id) on delete cascade,
  criado_por uuid null references public.usuarios (id) on delete set null,
  criado_em timestamptz not null default now(),
  primary key (usuario_id, evento_id)
);

create index if not exists idx_socios_eventos_evento on public.socios_eventos (evento_id);
create index if not exists idx_socios_eventos_org_usuario on public.socios_eventos (organizacao_id, usuario_id);

alter table public.socios_eventos enable row level security;
revoke all on table public.socios_eventos from public, anon, authenticated;
grant select, insert, update, delete on table public.socios_eventos to service_role;

-- Garante que o evento e da mesma casa do vinculo.
create or replace function private.validar_socio_evento()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.eventos e
     where e.id = new.evento_id and e.organizacao_id = new.organizacao_id
  ) then
    raise exception 'Evento nao pertence a organizacao.' using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function private.validar_socio_evento() from public, anon, authenticated;

drop trigger if exists trg_validar_socio_evento on public.socios_eventos;
create trigger trg_validar_socio_evento
  before insert or update on public.socios_eventos
  for each row execute function private.validar_socio_evento();

-- 2) listar_usuarios_admin com eventos_socio -----------------------------------
create or replace function private.listar_usuarios_admin(p_busca text default null::text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid;
  v_itens jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  v_org := (select private.organizacao_atual_id());

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'id', u.id,
               'nome', u.nome,
               'email', u.email,
               'perfil', m.perfil,
               'ativo', (m.ativo and u.ativo),
               'pendente', coalesce(au.encrypted_password, '') = '',
               'ultimo_acesso_em', coalesce(au.last_sign_in_at, u.ultimo_acesso_em),
               'criado_em', u.criado_em,
               'eventos_socio', (
                 select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'nome', e.nome)
                                           order by e.inicio_em desc), '[]'::jsonb)
                   from public.socios_eventos se
                   join public.eventos e on e.id = se.evento_id
                  where se.organizacao_id = v_org
                    and se.usuario_id = u.id
               )
             )
             order by (m.ativo and u.ativo) desc, m.perfil, u.nome
           ),
           '[]'::jsonb
         )
    into v_itens
    from public.membros_organizacao m
    join public.usuarios u on u.id = m.usuario_id
    left join auth.users au on au.id = u.id
   where m.organizacao_id = v_org
     and (
       p_busca is null
       or btrim(p_busca) = ''
       or u.nome ilike '%' || p_busca || '%'
       or u.email ilike '%' || p_busca || '%'
     );

  return v_itens;
end;
$$;

comment on function public.listar_usuarios_admin(text) is 'Lista membros da organizacao ativa (ADMINISTRADOR). Campos: id, nome, email, perfil, ativo, pendente, ultimo_acesso_em, criado_em, eventos_socio.';

-- 3) definir_eventos_socio_admin -------------------------------------------------
create or replace function private.definir_eventos_socio_admin(p_usuario_id uuid, p_evento_ids uuid[])
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_org uuid;
  v_perfil public.perfil_usuario;
  v_ids uuid[];
  v_validos integer;
  v_anteriores jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;
  perform private.exigir_fora_do_modo_suporte();

  v_org := private.organizacao_atual_id();

  select m.perfil into v_perfil
    from public.membros_organizacao m
   where m.organizacao_id = v_org
     and m.usuario_id = p_usuario_id;

  if not found then
    raise exception 'Usuario nao encontrado.' using errcode = '23503';
  end if;

  if v_perfil <> 'SOCIO' then
    raise exception 'Somente o perfil Socio do Evento tem eventos vinculados.' using errcode = '23514';
  end if;

  select coalesce(array_agg(distinct x), '{}') into v_ids
    from unnest(coalesce(p_evento_ids, '{}')) x
   where x is not null;

  select count(*) into v_validos
    from public.eventos e
   where e.id = any(v_ids) and e.organizacao_id = v_org;

  if v_validos <> coalesce(array_length(v_ids, 1), 0) then
    raise exception 'Evento nao encontrado.' using errcode = '23503';
  end if;

  select coalesce(jsonb_agg(se.evento_id order by se.evento_id), '[]'::jsonb) into v_anteriores
    from public.socios_eventos se
   where se.organizacao_id = v_org and se.usuario_id = p_usuario_id;

  delete from public.socios_eventos se
   where se.organizacao_id = v_org
     and se.usuario_id = p_usuario_id
     and not (se.evento_id = any(v_ids));

  insert into public.socios_eventos (organizacao_id, usuario_id, evento_id, criado_por)
  select v_org, p_usuario_id, x, auth.uid()
    from unnest(v_ids) x
  on conflict (usuario_id, evento_id) do nothing;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos, organizacao_id)
  values (auth.uid(), 'SOCIO_EVENTOS_DEFINIDOS', 'usuarios', p_usuario_id,
          jsonb_build_object('eventos', v_anteriores),
          jsonb_build_object('eventos', to_jsonb(v_ids)),
          v_org);

  return jsonb_build_object('usuario_id', p_usuario_id, 'eventos', to_jsonb(v_ids));
end;
$$;

create or replace function public.definir_eventos_socio_admin(p_usuario_id uuid, p_evento_ids uuid[])
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.definir_eventos_socio_admin(p_usuario_id, p_evento_ids); $$;

revoke all on function private.definir_eventos_socio_admin(uuid, uuid[]) from public, anon;
grant execute on function private.definir_eventos_socio_admin(uuid, uuid[]) to authenticated, service_role;
revoke all on function public.definir_eventos_socio_admin(uuid, uuid[]) from public, anon;
grant execute on function public.definir_eventos_socio_admin(uuid, uuid[]) to authenticated, service_role;

-- Helpers do socio ---------------------------------------------------------------
-- true quando o usuario logado e SOCIO na casa ativa e acompanha o evento.
create or replace function private.socio_acompanha_evento(p_evento_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    private.perfil_usuario_atual() = 'SOCIO'
    and exists (
      select 1
        from public.socios_eventos se
        join public.eventos e on e.id = se.evento_id and e.organizacao_id = se.organizacao_id
       where se.usuario_id = auth.uid()
         and se.organizacao_id = private.organizacao_atual_id()
         and se.evento_id = p_evento_id),
    false);
$$;

revoke all on function private.socio_acompanha_evento(uuid) from public, anon;
grant execute on function private.socio_acompanha_evento(uuid) to authenticated, service_role;

-- Resumo de vendas de um evento (mesmas regras do Dashboard: ingressos VALIDO ou
-- UTILIZADO; valores de pedidos PAGO). Uso interno, sem checagem de acesso.
create or replace function private.resumo_vendas_evento(p_evento_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with ing as (
    select count(*) filter (where i.status in ('VALIDO', 'UTILIZADO')) as vendidos,
           count(*) filter (where i.status = 'UTILIZADO') as utilizados,
           count(*) filter (where i.status in ('VALIDO', 'UTILIZADO') and i.meia) as meias
      from public.ingressos i
     where i.evento_id = p_evento_id
  ), ped as (
    select coalesce(sum(p.valor_total), 0) as bruto,
           coalesce(sum(p.valor_taxa_total), 0) as taxa,
           count(*) as pedidos
      from public.pedidos p
     where p.evento_id = p_evento_id and p.status = 'PAGO'
  ), reemb as (
    select coalesce(sum(pg.valor_reembolsado), 0) as reembolsado
      from public.pagamentos pg
      join public.pedidos p on p.id = pg.pedido_id
     where p.evento_id = p_evento_id
  )
  select jsonb_build_object(
    'vendidos', ing.vendidos,
    'utilizados', ing.utilizados,
    'naoEntraram', greatest(ing.vendidos - ing.utilizados, 0),
    'meias', ing.meias,
    'capacidade', e.capacidade_total,
    'pedidos', ped.pedidos,
    'bruto', ped.bruto,
    'taxa', ped.taxa,
    'reembolsado', reemb.reembolsado,
    'liquido', ped.bruto - ped.taxa - reemb.reembolsado,
    'ticketMedio', case when ing.vendidos > 0 then round(ped.bruto / ing.vendidos, 2) else 0 end
  )
  from public.eventos e, ing, ped, reemb
  where e.id = p_evento_id;
$$;

revoke all on function private.resumo_vendas_evento(uuid) from public, anon, authenticated;

-- 4) listar_eventos_socio ----------------------------------------------------------
create or replace function private.listar_eventos_socio()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid;
begin
  if coalesce(private.perfil_usuario_atual() = 'SOCIO', false) is false then
    raise exception 'Permissao negada: apenas Socio do Evento' using errcode = '42501';
  end if;

  v_org := private.organizacao_atual_id();

  return (
    select coalesce(jsonb_agg(
             jsonb_build_object(
               'evento_id', e.id,
               'nome', e.nome,
               'slug', e.slug,
               'imagem_url', e.imagem_url,
               'inicio_em', e.inicio_em,
               'local', e.local,
               'status', e.status,
               'vendas_status', e.vendas_status,
               'resumo', private.resumo_vendas_evento(e.id)
             )
             order by e.inicio_em desc), '[]'::jsonb)
      from public.socios_eventos se
      join public.eventos e on e.id = se.evento_id and e.organizacao_id = se.organizacao_id
     where se.usuario_id = auth.uid()
       and se.organizacao_id = v_org
  );
end;
$$;

create or replace function public.listar_eventos_socio()
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.listar_eventos_socio(); $$;

revoke all on function private.listar_eventos_socio() from public, anon;
grant execute on function private.listar_eventos_socio() to authenticated, service_role;
revoke all on function public.listar_eventos_socio() from public, anon;
grant execute on function public.listar_eventos_socio() to authenticated, service_role;

-- 5) obter_vendas_evento_socio -------------------------------------------------------
create or replace function private.obter_vendas_evento_socio(p_evento_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_evento public.eventos%rowtype;
begin
  if coalesce(private.perfil_usuario_atual() = 'SOCIO', false) is false then
    raise exception 'Permissao negada: apenas Socio do Evento' using errcode = '42501';
  end if;

  if not private.socio_acompanha_evento(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  select * into v_evento from public.eventos e where e.id = p_evento_id;

  return jsonb_build_object(
    'evento', jsonb_build_object(
      'evento_id', v_evento.id, 'nome', v_evento.nome, 'slug', v_evento.slug,
      'imagem_url', v_evento.imagem_url, 'inicio_em', v_evento.inicio_em,
      'local', v_evento.local, 'status', v_evento.status,
      'vendas_status', v_evento.vendas_status
    ),
    'resumo', private.resumo_vendas_evento(p_evento_id),

    -- PIX / CARTAO (online) e PORTA (venda manual em dinheiro)
    'porForma', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'forma', f.forma, 'pedidos', f.pedidos, 'ingressos', f.ingressos, 'valor', f.valor)
             order by f.valor desc), '[]'::jsonb)
        from (
          select case
                   when pg.provedor = 'DINHEIRO' then 'PORTA'
                   when pg.forma_pagamento = 'CARTAO' then 'CARTAO'
                   when pg.provedor is null then 'OUTRO'
                   else 'PIX'
                 end as forma,
                 count(*)::int as pedidos,
                 coalesce(sum(p.quantidade), 0)::int as ingressos,
                 coalesce(sum(p.valor_total), 0) as valor
            from public.pedidos p
            left join lateral (
              select x.provedor, x.forma_pagamento
                from public.pagamentos x
               where x.pedido_id = p.id and x.status in ('APROVADO', 'REEMBOLSADO')
               order by x.confirmado_em desc nulls last
               limit 1
            ) pg on true
           where p.evento_id = p_evento_id and p.status = 'PAGO'
           group by 1
        ) f
    ),

    -- Lotes (com o setor, quando houver)
    'porLote', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'lote', l.nome, 'setor', s.nome, 'status', l.status, 'preco', l.preco,
               'quantidade', l.quantidade,
               'vendidos', (select count(*) from public.ingressos i
                             where i.lote_id = l.id and i.status in ('VALIDO', 'UTILIZADO')),
               'valor', (select coalesce(sum(i.valor_unitario), 0) from public.ingressos i
                          where i.lote_id = l.id and i.status in ('VALIDO', 'UTILIZADO')))
             order by s.ordem nulls first, l.ordem), '[]'::jsonb)
        from public.lotes l
        left join public.setores s on s.id = l.setor_id
       where l.evento_id = p_evento_id
    ),

    -- Vendas por dia (data do pagamento, horario de Sao Paulo)
    'porDia', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'dia', to_char(d.dia, 'YYYY-MM-DD'), 'ingressos', d.ingressos, 'valor', d.valor)
             order by d.dia), '[]'::jsonb)
        from (
          select (coalesce(p.pago_em, p.criado_em) at time zone 'America/Sao_Paulo')::date as dia,
                 coalesce(sum(p.quantidade), 0)::int as ingressos,
                 coalesce(sum(p.valor_total), 0) as valor
            from public.pedidos p
           where p.evento_id = p_evento_id and p.status = 'PAGO'
           group by 1
        ) d
    ),

    'entradasPorHora', (
      select coalesce(jsonb_agg(jsonb_build_object('hora', to_char(h.h, 'HH24') || 'h', 'entradas', h.q) order by h.h), '[]'::jsonb)
        from (
          select date_trunc('hour', en.entrada_em at time zone 'America/Sao_Paulo') as h, count(*)::int as q
            from public.entradas en
           where en.evento_id = p_evento_id and en.anulada_em is null
           group by 1
        ) h
    )
  );
end;
$$;

create or replace function public.obter_vendas_evento_socio(p_evento_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.obter_vendas_evento_socio(p_evento_id); $$;

revoke all on function private.obter_vendas_evento_socio(uuid) from public, anon;
grant execute on function private.obter_vendas_evento_socio(uuid) to authenticated, service_role;
revoke all on function public.obter_vendas_evento_socio(uuid) from public, anon;
grant execute on function public.obter_vendas_evento_socio(uuid) to authenticated, service_role;
