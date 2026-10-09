-- =============================================================================
-- Ingressoudi - Testes: isolamento entre organizacoes (Etapas B e C)
-- Arquivo: supabase/tests/multiempresa_isolamento.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
--
-- Cenario: organizacao A (admin A + portaria A) com evento, lote, venda, VIP e
-- entrada; organizacao B (admin B + portaria B) com evento proprio.
-- Criterio: nenhum usuario de B le, altera ou valida qualquer dado de A.
-- =============================================================================

begin;

do $$
declare
  v_org_a uuid; v_org_b uuid;
  v_admin_a uuid := gen_random_uuid();
  v_port_a uuid := gen_random_uuid();
  v_admin_b uuid := gen_random_uuid();
  v_port_b uuid := gen_random_uuid();
  v_ev_a uuid; v_ev_b uuid; v_lote_a uuid; v_ped_a uuid; v_ing_a uuid; v_qr_a text;
  v_vip_a uuid; v_entrada_a uuid;
  v_res jsonb; v_txt text;

begin
  insert into public.organizacoes (nome, slug) values ('Org A', 'iso-a-' || replace(gen_random_uuid()::text,'-','')) returning id into v_org_a;
  insert into public.organizacoes (nome, slug) values ('Org B', 'iso-b-' || replace(gen_random_uuid()::text,'-','')) returning id into v_org_b;

  insert into auth.users (id) values (v_admin_a), (v_port_a), (v_admin_b), (v_port_b);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin_a, 'Admin A', 'iso_aa_' || replace(v_admin_a::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_port_a,  'Port A',  'iso_pa_' || replace(v_port_a::text,'-','')  || '@test.local', 'PORTARIA', true),
    (v_admin_b, 'Admin B', 'iso_ab_' || replace(v_admin_b::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_port_b,  'Port B',  'iso_pb_' || replace(v_port_b::text,'-','')  || '@test.local', 'PORTARIA', true);
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values
    (v_org_a, v_admin_a, 'ADMINISTRADOR'), (v_org_a, v_port_a, 'PORTARIA'),
    (v_org_b, v_admin_b, 'ADMINISTRADOR'), (v_org_b, v_port_b, 'PORTARIA');

  ---------------------------------------------------------------------------
  -- Organizacao A monta seus dados pelas proprias RPCs
  ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_a::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin_a::text, true);

  v_res := public.criar_evento_admin('Show A', 'iso-show-a-' || replace(gen_random_uuid()::text,'-',''), null, null,
                                     now() + interval '2 days', 'Casa A', 'Rua A', 100, 50, 'PUBLICADO', 'ABERTAS');
  v_ev_a := (v_res->>'evento_id')::uuid;
  if (select organizacao_id from public.eventos where id = v_ev_a) <> v_org_a then
    raise exception 'SETUP: evento A deveria pertencer a Org A';
  end if;

  v_res := public.criar_lote_admin(v_ev_a, 'Lote A', 10, 25, 'MANUAL', null);
  v_lote_a := (v_res->>'lote_id')::uuid;
  perform public.ativar_lote_manual(v_lote_a);

  v_res := public.criar_venda_manual_admin(v_ev_a, v_lote_a, 'Comprador Alfa', '11999990000', array['Zuleica Alfa']);
  v_ped_a := (v_res->>'pedido_id')::uuid;
  select i.id, i.qr_token into v_ing_a, v_qr_a from public.ingressos i where i.pedido_id = v_ped_a limit 1;

  v_res := public.criar_lista_vip_admin(v_ev_a, 'Vip Alfa', null, null);
  v_vip_a := (v_res->>'vip_id')::uuid;

  -- evento A comeca agora (permite a entrada)
  update public.eventos set inicio_em = now() - interval '1 hour' where id = v_ev_a;

  -- portaria A valida o proprio ingresso (gera uma entrada em A)
  perform set_config('request.jwt.claims', json_build_object('sub', v_port_a::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_port_a::text, true);
  v_res := public.registrar_entrada_qr(v_ev_a, v_qr_a);
  if v_res->>'resultado' <> 'LIBERADO' then
    raise exception 'SETUP: portaria A deveria liberar o proprio ingresso (obtido %)', v_res->>'resultado';
  end if;
  v_entrada_a := (v_res->>'entrada_id')::uuid;

  ---------------------------------------------------------------------------
  -- Admin B: nada de A aparece nem pode ser alterado
  ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_b::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin_b::text, true);

  v_res := public.criar_evento_admin('Show B', 'iso-show-b-' || replace(gen_random_uuid()::text,'-',''), null, null,
                                     now() + interval '3 days', 'Casa B', 'Rua B', 100, 50, 'PUBLICADO', 'ABERTAS');
  v_ev_b := (v_res->>'evento_id')::uuid;
  if (select organizacao_id from public.eventos where id = v_ev_b) <> v_org_b then
    raise exception 'B0: evento B deveria pertencer a Org B';
  end if;

  -- B1) listagens
  if exists (select 1 from public.listar_eventos_admin() x where x.id = v_ev_a) then
    raise exception 'B1: listar_eventos_admin vazou evento de A'; end if;
  if not exists (select 1 from public.listar_eventos_admin() x where x.id = v_ev_b) then
    raise exception 'B1: listar_eventos_admin deveria mostrar evento de B'; end if;
  if public.listar_eventos_admin_filtrado(null, null, null, null)::text like '%' || v_ev_a::text || '%' then
    raise exception 'B1: listar_eventos_admin_filtrado vazou evento de A'; end if;
  if public.listar_eventos_venda_manual_admin()::text like '%' || v_ev_a::text || '%' then
    raise exception 'B1: listar_eventos_venda_manual_admin vazou evento de A'; end if;
  if public.listar_pedidos_admin()::text like '%' || v_ped_a::text || '%' then
    raise exception 'B1: listar_pedidos_admin vazou pedido de A'; end if;
  if public.listar_ingressos_admin(null, null, null, null)::text like '%' || v_ing_a::text || '%' then
    raise exception 'B1: listar_ingressos_admin vazou ingresso de A'; end if;
  if public.listar_entradas_admin(null, null, null, null, null, null)::text like '%' || v_entrada_a::text || '%' then
    raise exception 'B1: listar_entradas_admin vazou entrada de A'; end if;
  if public.listar_usuarios_admin(null)::text like '%' || v_admin_a::text || '%' then
    raise exception 'B1: listar_usuarios_admin vazou usuario de A'; end if;

  -- B2) contadores, dashboard e financeiro zerados para B
  v_res := public.obter_contadores_admin();
  if (v_res->>'pedidos')::int <> 0 or (v_res->>'entradas')::int <> 0 then
    raise exception 'B2: contadores de B deveriam ser zero (obtido %)', v_res; end if;
  v_res := public.obter_dashboard_admin();
  if (v_res->'metricas'->>'vendidos')::int <> 0 or (v_res->'metricas'->>'utilizados')::int <> 0 then
    raise exception 'B2: dashboard de B nao deveria contar ingressos de A (obtido %)', v_res->'metricas'; end if;
  if (v_res->'evento'->>'evento_id')::uuid is distinct from v_ev_b then
    raise exception 'B2: dashboard de B deveria destacar o evento de B'; end if;
  if v_res::text like '%Comprador Alfa%' or v_res::text like '%Zuleica Alfa%' then
    raise exception 'B2: dashboard de B vazou pedido/entrada de A'; end if;
  v_res := public.obter_financeiro_admin(null, null, null, null, null, null);
  if v_res::text like '%' || v_ped_a::text || '%' or v_res::text like '%Comprador Alfa%' then
    raise exception 'B2: financeiro de B vazou dados de A'; end if;

  -- B3) consultas por id retornam vazio
  if public.obter_pedido_admin(v_ped_a) is not null then
    raise exception 'B3: obter_pedido_admin vazou pedido de A'; end if;
  if public.obter_ingresso_admin(v_ing_a) is not null then
    raise exception 'B3: obter_ingresso_admin vazou ingresso de A'; end if;

  -- B4) operacoes sobre o evento de A sao recusadas como "nao encontrado"
  begin perform public.obter_evento_admin(v_ev_a); raise exception 'B4: obter_evento_admin'; exception when others then
    if position('nao encontrad' in lower(sqlerrm)) = 0 then raise exception 'B4 obter_evento_admin: %', sqlerrm; end if; end;
  begin perform public.obter_dashboard_evento(v_ev_a); raise exception 'B4: obter_dashboard_evento'; exception when others then
    if position('nao encontrad' in lower(sqlerrm)) = 0 then raise exception 'B4 obter_dashboard_evento: %', sqlerrm; end if; end;
  begin perform public.atualizar_evento_admin(v_ev_a, 'Hack', 'hack-' || replace(gen_random_uuid()::text,'-',''), null, null,
                                              now() + interval '2 days', 'X', 'Y', 100, 50, 'PUBLICADO', 'ABERTAS');
    raise exception 'B4: atualizar_evento_admin'; exception when others then
    if position('nao encontrad' in lower(sqlerrm)) = 0 then raise exception 'B4 atualizar_evento_admin: %', sqlerrm; end if; end;
  begin perform public.definir_vendas_evento_admin(v_ev_a, 'ENCERRADAS'); raise exception 'B4: definir_vendas'; exception when others then
    if position('nao encontrad' in lower(sqlerrm)) = 0 then raise exception 'B4 definir_vendas: %', sqlerrm; end if; end;
  begin perform public.listar_lotes_admin(v_ev_a); raise exception 'B4: listar_lotes_admin'; exception when others then
    if position('nao encontrad' in lower(sqlerrm)) = 0 then raise exception 'B4 listar_lotes_admin: %', sqlerrm; end if; end;
  begin perform public.criar_lote_admin(v_ev_a, 'Hack', 10, 1, 'MANUAL', null); raise exception 'B4: criar_lote_admin'; exception when others then
    if position('nao encontrad' in lower(sqlerrm)) = 0 then raise exception 'B4 criar_lote_admin: %', sqlerrm; end if; end;
  begin perform public.criar_venda_manual_admin(v_ev_a, v_lote_a, 'Hack', '11999990000', array['Hack']); raise exception 'B4: venda_manual'; exception when others then
    if position('nao encontrad' in lower(sqlerrm)) = 0 then raise exception 'B4 venda_manual: %', sqlerrm; end if; end;
  begin perform public.listar_lista_vip_admin(v_ev_a, null); raise exception 'B4: listar_lista_vip'; exception when others then
    if position('nao encontrad' in lower(sqlerrm)) = 0 then raise exception 'B4 listar_lista_vip: %', sqlerrm; end if; end;
  begin perform public.criar_lista_vip_admin(v_ev_a, 'Hack', null, null); raise exception 'B4: criar_lista_vip'; exception when others then
    if position('nao encontrad' in lower(sqlerrm)) = 0 then raise exception 'B4 criar_lista_vip: %', sqlerrm; end if; end;
  begin perform public.criar_lista_vip_em_lote_admin(v_ev_a, array['Hack']); raise exception 'B4: vip_em_lote'; exception when others then
    if position('nao encontrad' in lower(sqlerrm)) = 0 then raise exception 'B4 vip_em_lote: %', sqlerrm; end if; end;
  begin perform public.encerrar_evento(v_ev_a); raise exception 'B4: encerrar_evento'; exception when others then
    if position('nao encontrad' in lower(sqlerrm)) = 0 then raise exception 'B4 encerrar_evento: %', sqlerrm; end if; end;

  -- B5) operacoes por id de registro de A sao recusadas
  begin perform public.atualizar_lote_admin(v_lote_a, 'Hack', 10, 1, 'MANUAL', null); raise exception 'B5: atualizar_lote'; exception when others then
    if position('nao encontrad' in lower(sqlerrm)) = 0 then raise exception 'B5 atualizar_lote: %', sqlerrm; end if; end;
  begin perform public.ativar_lote_manual(v_lote_a); raise exception 'B5: ativar_lote'; exception when others then
    if position('nao encontrad' in lower(sqlerrm)) = 0 then raise exception 'B5 ativar_lote: %', sqlerrm; end if; end;
  begin perform public.atualizar_lista_vip_admin(v_vip_a, 'Hack', null, null); raise exception 'B5: atualizar_vip'; exception when others then
    if position('nao encontrad' in lower(sqlerrm)) = 0 then raise exception 'B5 atualizar_vip: %', sqlerrm; end if; end;
  begin perform public.remover_lista_vip_admin(v_vip_a); raise exception 'B5: remover_vip'; exception when others then
    if position('nao encontrad' in lower(sqlerrm)) = 0 then raise exception 'B5 remover_vip: %', sqlerrm; end if; end;
  begin perform public.anular_entrada(v_entrada_a, 'Hack'); raise exception 'B5: anular_entrada'; exception when others then
    if position('nao encontrad' in lower(sqlerrm)) = 0 then raise exception 'B5 anular_entrada: %', sqlerrm; end if; end;
  begin perform public.atualizar_usuario_admin(v_admin_a, 'Hack', 'PORTARIA', false); raise exception 'B5: atualizar_usuario'; exception when others then
    if position('nao encontrad' in lower(sqlerrm)) = 0 then raise exception 'B5 atualizar_usuario: %', sqlerrm; end if; end;

  ---------------------------------------------------------------------------
  -- Portaria B: nao enxerga nem valida nada de A
  ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_port_b::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_port_b::text, true);

  if public.listar_eventos_portaria()::text like '%' || v_ev_a::text || '%' then
    raise exception 'C1: listar_eventos_portaria vazou evento de A'; end if;

  begin perform public.registrar_entrada_qr(v_ev_a, v_qr_a); raise exception 'C2: entrada no evento de A'; exception when others then
    if position('nao encontrad' in lower(sqlerrm)) = 0 then raise exception 'C2: %', sqlerrm; end if; end;

  v_res := public.registrar_entrada_qr(v_ev_b, v_qr_a);
  if v_res->>'resultado' <> 'NAO_ENCONTRADO' or v_res->>'codigo' is not null or v_res->>'participante_nome' is not null then
    raise exception 'C3: QR de A no evento de B deveria ser NAO_ENCONTRADO sem dados (obtido %)', v_res; end if;

  v_res := public.registrar_entrada_nome(v_ev_b, v_ing_a);
  if v_res->>'resultado' <> 'NAO_ENCONTRADO' or v_res->>'participante_nome' is not null then
    raise exception 'C4: ingresso de A por nome no evento de B deveria ser NAO_ENCONTRADO (obtido %)', v_res; end if;

  v_res := public.registrar_entrada_vip(v_ev_b, v_vip_a);
  if v_res->>'resultado' <> 'NAO_ENCONTRADO' or v_res->>'participante_nome' is not null then
    raise exception 'C5: VIP de A no evento de B deveria ser NAO_ENCONTRADO (obtido %)', v_res; end if;

  v_txt := public.buscar_ingressos_por_nome(v_ev_a, 'Zuleica')::text;
  if v_txt like '%Zuleica%' then
    raise exception 'C6: busca por nome vazou participante de A'; end if;

  -- nenhuma tentativa de B foi gravada na organizacao A
  if exists (select 1 from public.tentativas_entrada t where t.usuario_id = v_port_b and t.organizacao_id = v_org_a) then
    raise exception 'C7: tentativas da portaria B nao podem ser gravadas na Org A'; end if;

  ---------------------------------------------------------------------------
  -- Admin A continua vendo os proprios dados
  ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_a::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin_a::text, true);
  if public.obter_pedido_admin(v_ped_a) is null then
    raise exception 'D1: admin A deveria ver o proprio pedido'; end if;
  if public.listar_eventos_admin_filtrado(null, null, null, null)::text not like '%' || v_ev_a::text || '%' then
    raise exception 'D1: admin A deveria ver o proprio evento'; end if;
  if public.listar_eventos_admin_filtrado(null, null, null, null)::text like '%' || v_ev_b::text || '%' then
    raise exception 'D1: admin A nao deveria ver evento de B'; end if;
  if (public.obter_contadores_admin()->>'entradas')::int <> 1 then
    raise exception 'D2: admin A deveria contar 1 entrada'; end if;
end $$;

select 'multiempresa_isolamento: todos os testes passaram' as resultado;

rollback;
