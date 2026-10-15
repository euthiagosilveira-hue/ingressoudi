-- Resumo (somente leitura) do que existe numa organizacao. Placeholder: __SLUG__
with org as (
  select * from public.organizacoes where slug = '__SLUG__'
)
select jsonb_pretty(jsonb_build_object(
  'organizacao', (select jsonb_build_object('id', o.id, 'nome', o.nome, 'slug', o.slug, 'ativo', o.ativo,
                                            'aprovada', o.aprovada, 'criado_em', o.criado_em) from org o),
  'mercado_pago_conectado', exists (select 1 from public.organizacoes_mercado_pago mp join org o on o.id = mp.organizacao_id),
  'contagens', jsonb_build_object(
    'eventos',            (select count(*) from public.eventos x join org o on o.id = x.organizacao_id),
    'lotes',              (select count(*) from public.lotes x join org o on o.id = x.organizacao_id),
    'pedidos',            (select count(*) from public.pedidos x join org o on o.id = x.organizacao_id),
    'ingressos',          (select count(*) from public.ingressos x join org o on o.id = x.organizacao_id),
    'pagamentos',         (select count(*) from public.pagamentos x join org o on o.id = x.organizacao_id),
    'entradas',           (select count(*) from public.entradas x join org o on o.id = x.organizacao_id),
    'tentativas_entrada', (select count(*) from public.tentativas_entrada x join org o on o.id = x.organizacao_id),
    'lista_vip',          (select count(*) from public.lista_vip x join org o on o.id = x.organizacao_id),
    'entradas_vip',       (select count(*) from public.entradas_vip x join org o on o.id = x.organizacao_id),
    'cancelamentos_reembolsos', (select count(*) from public.cancelamentos_reembolsos x join org o on o.id = x.organizacao_id),
    'auditoria',          (select count(*) from public.auditoria x join org o on o.id = x.organizacao_id),
    'membros',            (select count(*) from public.membros_organizacao x join org o on o.id = x.organizacao_id)
  ),
  'pagamentos_aprovados', (
    select coalesce(jsonb_object_agg(s.provedor, jsonb_build_object('quantidade', s.n, 'valor', s.total)), '{}'::jsonb)
      from (select p.provedor::text as provedor, count(*) as n, sum(p.valor) as total
              from public.pagamentos p join org o on o.id = p.organizacao_id
             where p.status = 'APROVADO'
             group by 1) s
  ),
  'eventos', (
    select coalesce(jsonb_agg(jsonb_build_object('nome', e.nome, 'status', e.status, 'inicio_em', e.inicio_em) order by e.inicio_em), '[]'::jsonb)
      from public.eventos e join org o on o.id = e.organizacao_id
  ),
  'membros', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'email', u.email, 'perfil', m.perfil, 'super_admin', u.super_admin,
             'outras_organizacoes', (select count(*) from public.membros_organizacao m2
                                      where m2.usuario_id = u.id and m2.organizacao_id <> m.organizacao_id and m2.ativo))
           order by u.email), '[]'::jsonb)
      from public.membros_organizacao m
      join org o on o.id = m.organizacao_id
      join public.usuarios u on u.id = m.usuario_id
  )
)) as resumo;
