-- Remove DEFINITIVAMENTE uma organizacao e todos os dados dela. Placeholder: __SLUG__
-- Usuarios (contas de login) NAO sao removidos: so perdem o vinculo com esta organizacao.
do $$
declare
  v_org uuid;
  v_n bigint;
  v_eventos uuid[];
begin
  select id into v_org from public.organizacoes where slug = '__SLUG__' for update;
  if v_org is null then
    raise exception 'Organizacao com slug "__SLUG__" nao encontrada';
  end if;
  select coalesce(array_agg(id), '{}') into v_eventos from public.eventos where organizacao_id = v_org;

  delete from public.entradas_vip where organizacao_id = v_org or evento_id = any(v_eventos);
  get diagnostics v_n = row_count; raise notice 'entradas_vip: %', v_n;
  delete from public.entradas where organizacao_id = v_org or evento_id = any(v_eventos);
  get diagnostics v_n = row_count; raise notice 'entradas: %', v_n;
  delete from public.tentativas_entrada where organizacao_id = v_org or evento_id = any(v_eventos);
  get diagnostics v_n = row_count; raise notice 'tentativas_entrada: %', v_n;
  delete from public.compartilhamentos_ingresso c using public.ingressos i
   where c.ingresso_id = i.id and (i.organizacao_id = v_org or i.evento_id = any(v_eventos));
  get diagnostics v_n = row_count; raise notice 'compartilhamentos_ingresso: %', v_n;
  delete from public.cancelamentos_reembolsos where organizacao_id = v_org;
  get diagnostics v_n = row_count; raise notice 'cancelamentos_reembolsos: %', v_n;
  delete from public.pagamentos where organizacao_id = v_org;
  get diagnostics v_n = row_count; raise notice 'pagamentos: %', v_n;
  delete from public.recuperacoes_ingressos r using public.pedidos p
   where r.pedido_id = p.id and (p.organizacao_id = v_org or p.evento_id = any(v_eventos));
  get diagnostics v_n = row_count; raise notice 'recuperacoes_ingressos: %', v_n;
  delete from public.ingressos where organizacao_id = v_org or evento_id = any(v_eventos);
  get diagnostics v_n = row_count; raise notice 'ingressos: %', v_n;
  delete from public.lista_vip where organizacao_id = v_org or evento_id = any(v_eventos);
  get diagnostics v_n = row_count; raise notice 'lista_vip: %', v_n;
  delete from public.pedidos where organizacao_id = v_org or evento_id = any(v_eventos);
  get diagnostics v_n = row_count; raise notice 'pedidos: %', v_n;
  delete from public.lotes where organizacao_id = v_org or evento_id = any(v_eventos);
  get diagnostics v_n = row_count; raise notice 'lotes: %', v_n;
  delete from public.eventos where organizacao_id = v_org;
  get diagnostics v_n = row_count; raise notice 'eventos: %', v_n;
  delete from public.auditoria where organizacao_id = v_org;
  get diagnostics v_n = row_count; raise notice 'auditoria: %', v_n;
  delete from public.organizacoes_mercado_pago where organizacao_id = v_org;
  get diagnostics v_n = row_count; raise notice 'organizacoes_mercado_pago: %', v_n;

  -- quem estava com esta organizacao ativa passa para outra organizacao dele (ou nenhuma)
  update public.usuarios u
     set organizacao_ativa_id = (select m.organizacao_id from public.membros_organizacao m
                                  where m.usuario_id = u.id and m.organizacao_id <> v_org and m.ativo
                                  order by m.criado_em limit 1)
   where u.organizacao_ativa_id = v_org;
  get diagnostics v_n = row_count; raise notice 'usuarios com organizacao ativa trocada: %', v_n;

  delete from public.membros_organizacao where organizacao_id = v_org;
  get diagnostics v_n = row_count; raise notice 'membros_organizacao: %', v_n;
  delete from public.organizacoes where id = v_org;
  raise notice 'organizacao removida: __SLUG__ (%)', v_org;
end $$;
