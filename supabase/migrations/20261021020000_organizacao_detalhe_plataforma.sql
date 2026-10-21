-- =============================================================================
-- Ingressoudi - Detalhe de uma casa (Plataforma, somente super admin)
-- obter_organizacao_plataforma(p_organizacao_id): dados da casa, do dono
-- (quem a cadastrou), da equipe, metricas gerais e os numeros de cada evento.
-- Dono = registro ORGANIZACAO_CADASTRADA da auditoria; sem esse registro, o
-- administrador ativo mais antigo da casa.
-- Valores: pedidos PAGO (online = pagamento APROVADO no Mercado Pago; dinheiro
-- = venda manual), as mesmas regras de Todos os eventos e da Receita.
-- Somente leitura. Nao devolve tokens do Mercado Pago nem dados de compradores.
-- =============================================================================

create or replace function private.obter_organizacao_plataforma(p_organizacao_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org public.organizacoes%rowtype;
  v_dono uuid;
  v_eventos jsonb;
  v_metricas jsonb;
begin
  if not private.usuario_e_super_admin() then
    raise exception 'Permissao negada: apenas super administrador' using errcode = '42501';
  end if;

  select * into v_org from public.organizacoes o where o.id = p_organizacao_id;
  if not found then
    raise exception 'Organizacao % nao encontrada', p_organizacao_id using errcode = '23503';
  end if;

  select coalesce(
           (select a.usuario_id
              from public.auditoria a
              join public.usuarios ux on ux.id = a.usuario_id
             where a.acao = 'ORGANIZACAO_CADASTRADA' and a.entidade_id = v_org.id
             order by a.criado_em
             limit 1),
           (select m.usuario_id
              from public.membros_organizacao m
             where m.organizacao_id = v_org.id and m.ativo and m.perfil = 'ADMINISTRADOR'
             order by m.criado_em
             limit 1))
    into v_dono;

  -- Numeros por evento ---------------------------------------------------------
  with pedidos_pagos as (
    select p.evento_id, p.valor_total, p.valor_taxa_total,
           exists (select 1 from public.pagamentos g
                    where g.pedido_id = p.id and g.status = 'APROVADO' and g.provedor = 'MERCADO_PAGO') as online
      from public.pedidos p
     where p.organizacao_id = v_org.id and p.status = 'PAGO'
  ),
  por_evento as (
    select e.id, e.nome, e.slug, e.inicio_em, e.local, e.status, e.publicacao_status, e.vendas_status,
           e.capacidade_total, e.criado_em,
           coalesce(ing.vendidos, 0) as vendidos,
           coalesce(ing.utilizados, 0) as utilizados,
           coalesce(ped.pedidos, 0) as pedidos,
           coalesce(ped.valor, 0) as valor,
           coalesce(ped.online, 0) as online,
           coalesce(ped.dinheiro, 0) as dinheiro,
           coalesce(ped.taxa, 0) as taxa
      from public.eventos e
      left join lateral (
        select count(*) filter (where i.status in ('VALIDO', 'UTILIZADO')) as vendidos,
               count(*) filter (where i.status = 'UTILIZADO') as utilizados
          from public.ingressos i
         where i.evento_id = e.id
      ) ing on true
      left join lateral (
        select count(*) as pedidos,
               sum(pp.valor_total) as valor,
               sum(pp.valor_total) filter (where pp.online) as online,
               sum(pp.valor_total) filter (where not pp.online) as dinheiro,
               sum(pp.valor_taxa_total) filter (where pp.online) as taxa
          from pedidos_pagos pp
         where pp.evento_id = e.id
      ) ped on true
     where e.organizacao_id = v_org.id
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'evento_id', pe.id,
      'nome', pe.nome,
      'slug', pe.slug,
      'inicio_em', pe.inicio_em,
      'local', pe.local,
      'status', pe.status,
      'publicacao_status', pe.publicacao_status,
      'vendas_status', pe.vendas_status,
      'capacidade_total', pe.capacidade_total,
      'vendidos', pe.vendidos,
      'utilizados', pe.utilizados,
      'pedidos_pagos', pe.pedidos,
      'valor_vendido', pe.valor,
      'valor_online', pe.online,
      'valor_dinheiro', pe.dinheiro,
      'taxa_plataforma', pe.taxa
    ) order by pe.inicio_em desc, pe.nome), '[]'::jsonb),
    jsonb_build_object(
      'eventos_total', count(pe.id),
      'eventos_publicados', count(pe.id) filter (where pe.publicacao_status = 'PUBLICADO'),
      'eventos_ativos', count(pe.id) filter (
        where pe.publicacao_status = 'PUBLICADO' and pe.status in ('AGENDADO', 'EM_ANDAMENTO')),
      'eventos_vendas_abertas', count(pe.id) filter (
        where pe.publicacao_status = 'PUBLICADO' and pe.status in ('AGENDADO', 'EM_ANDAMENTO')
          and pe.vendas_status = 'ABERTAS'),
      'eventos_realizados', count(pe.id) filter (where pe.status = 'REALIZADO'),
      'eventos_cancelados', count(pe.id) filter (where pe.status = 'CANCELADO'),
      'eventos_rascunho', count(pe.id) filter (where pe.publicacao_status = 'RASCUNHO'),
      'ingressos_vendidos', coalesce(sum(pe.vendidos), 0),
      'ingressos_utilizados', coalesce(sum(pe.utilizados), 0),
      'pedidos_pagos', coalesce(sum(pe.pedidos), 0),
      'valor_vendido', coalesce(sum(pe.valor), 0),
      'valor_online', coalesce(sum(pe.online), 0),
      'valor_dinheiro', coalesce(sum(pe.dinheiro), 0),
      'taxa_plataforma', coalesce(sum(pe.taxa), 0),
      'primeiro_evento_criado_em', min(pe.criado_em),
      'proximo_evento_em', min(pe.inicio_em) filter (
        where pe.publicacao_status = 'PUBLICADO' and pe.status in ('AGENDADO', 'EM_ANDAMENTO')
          and pe.inicio_em >= now())
    )
    into v_eventos, v_metricas
    from por_evento pe;

  v_metricas := v_metricas || jsonb_build_object(
    'valor_reembolsado', coalesce((
      select sum(g.valor_reembolsado) from public.pagamentos g where g.organizacao_id = v_org.id), 0));

  return jsonb_build_object(
    'organizacao', jsonb_build_object(
      'organizacao_id', v_org.id,
      'nome', v_org.nome,
      'slug', v_org.slug,
      'ativo', v_org.ativo,
      'aprovada', v_org.aprovada,
      'lista_vip_ativa', v_org.lista_vip_ativa,
      'taxa_servico', v_org.taxa_servico,
      'criado_em', v_org.criado_em,
      'mercado_pago', (
        select jsonb_build_object('conectado', true, 'conectado_em', mp.conectado_em, 'producao', mp.live_mode)
          from public.organizacoes_mercado_pago mp
         where mp.organizacao_id = v_org.id)
    ),
    'dono', (
      select jsonb_build_object(
               'usuario_id', u.id,
               'nome', u.nome,
               'email', u.email,
               'ativo', u.ativo,
               'cadastrado_em', coalesce(au.created_at, u.criado_em),
               'ultimo_acesso_em', coalesce(au.last_sign_in_at, u.ultimo_acesso_em),
               'email_confirmado', au.email_confirmed_at is not null,
               'termos_versao', u.termos_versao,
               'termos_aceitos_em', u.termos_aceitos_em,
               'outras_casas', (
                 select count(*) from public.membros_organizacao m2
                  where m2.usuario_id = u.id and m2.ativo and m2.organizacao_id <> v_org.id))
        from public.usuarios u
        left join auth.users au on au.id = u.id
       where u.id = v_dono),
    'equipe', coalesce((
      select jsonb_agg(jsonb_build_object(
               'usuario_id', u.id,
               'nome', u.nome,
               'email', u.email,
               'perfil', m.perfil,
               'ativo', m.ativo and u.ativo,
               'dono', coalesce(u.id = v_dono, false),
               'ultimo_acesso_em', coalesce(au.last_sign_in_at, u.ultimo_acesso_em)
             ) order by (u.id = v_dono) desc, m.perfil, u.nome)
        from public.membros_organizacao m
        join public.usuarios u on u.id = m.usuario_id
        left join auth.users au on au.id = u.id
       where m.organizacao_id = v_org.id), '[]'::jsonb),
    'metricas', v_metricas,
    'eventos', v_eventos
  );
end;
$$;

create or replace function public.obter_organizacao_plataforma(p_organizacao_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.obter_organizacao_plataforma(p_organizacao_id); $$;

revoke all on function private.obter_organizacao_plataforma(uuid) from public, anon;
revoke all on function public.obter_organizacao_plataforma(uuid) from public, anon;
grant execute on function private.obter_organizacao_plataforma(uuid) to authenticated, service_role;
grant execute on function public.obter_organizacao_plataforma(uuid) to authenticated, service_role;
