-- =============================================================================
-- Ingressoudi - Testes: dashboard de um evento (obter_painel_evento_admin).
-- Executar como owner. begin/rollback.
-- =============================================================================

begin;

-- [Ingressoudi] Fixture multiempresa (Etapa A) ---------------------------------
-- Cria uma organizacao de teste; eventos inseridos sem organizacao caem nela e
-- todo usuario criado (ou com perfil alterado) vira membro dela com o mesmo
-- perfil. Tudo e desfeito pelo rollback ao final do arquivo.
do $fx$
declare
  v_org uuid;
begin
  insert into public.organizacoes (nome, slug, taxa_servico)
  values ('Org Teste', 'org-teste-' || replace(gen_random_uuid()::text, '-', ''), 0)
  returning id into v_org;
  execute format('alter table public.eventos alter column organizacao_id set default %L::uuid', v_org);
  perform set_config('teste.organizacao_id', v_org::text, true);
end
$fx$;

create function private.teste_vincular_membro()
returns trigger
language plpgsql
set search_path = ''
as $fx$
begin
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil, ativo)
  values (current_setting('teste.organizacao_id')::uuid, new.id, new.perfil, true)
  on conflict (organizacao_id, usuario_id) do update set perfil = excluded.perfil;
  return new;
end
$fx$;

create trigger trg_teste_vincular_membro
  after insert or update of perfil on public.usuarios
  for each row execute function private.teste_vincular_membro();
-- [/Ingressoudi] ------------------------------------------------------------------

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_portaria uuid := gen_random_uuid();
  v_evento uuid := gen_random_uuid();
  v_outro uuid := gen_random_uuid();
  v_lote uuid := gen_random_uuid();
  v_lote_outro uuid := gen_random_uuid();
  v_ped uuid := gen_random_uuid();
  v_ped_outro uuid := gen_random_uuid();
  v_i1 uuid := gen_random_uuid();
  v_i2 uuid := gen_random_uuid();
  v_org_b uuid;
  v_evento_b uuid := gen_random_uuid();
  v_res jsonb;
  v_m jsonb;
begin
  insert into auth.users (id) values (v_admin), (v_portaria);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Painel', 'adminpainel_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Port Painel', 'portpainel_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true);

  insert into public.eventos (id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, vendas_status, publicacao_status) values
    (v_evento, 'Evento Painel', 'ev-painel-' || replace(v_evento::text,'-',''), now() + interval '3 days', 'Galeria', 'Rua 1', 100, 100, 'AGENDADO', 'ABERTAS', 'PUBLICADO'),
    (v_outro, 'Outro Evento', 'ev-outro-' || replace(v_outro::text,'-',''), now() + interval '5 days', 'Galeria', 'Rua 1', 100, 100, 'AGENDADO', 'ABERTAS', 'PUBLICADO');
  insert into public.lotes (id, evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_lote, v_evento, 'Lote 1', 1, 100, 30, 'MANUAL', 'ATIVO');

  -- pedido pago com 2 ingressos (1 ja entrou) no evento do painel
  insert into public.pedidos (id, evento_id, lote_id, codigo, comprador_nome, comprador_telefone, quantidade, tipo_preco, valor_unitario, valor_total, status, pago_em, checkout_token)
  values (v_ped, v_evento, v_lote, 'PN' || replace(v_ped::text,'-',''), 'Comprador Painel', '11999990001', 2, 'LOTE', 30, 60, 'PAGO', now(), gen_random_uuid());
  insert into public.pagamentos (pedido_id, provedor, valor, status) values (v_ped, 'DINHEIRO', 60, 'APROVADO');
  insert into public.ingressos (id, pedido_id, evento_id, lote_id, codigo, participante_nome, valor_unitario, qr_token, status, utilizado_em) values
    (v_i1, v_ped, v_evento, v_lote, 'PN1' || substr(replace(gen_random_uuid()::text,'-',''),1,12), 'Ana', 30, gen_random_uuid()::text, 'UTILIZADO', '2026-11-01 23:30:00-03'),
    (v_i2, v_ped, v_evento, v_lote, 'PN2' || substr(replace(gen_random_uuid()::text,'-',''),1,12), 'Bia', 30, gen_random_uuid()::text, 'VALIDO', null);
  insert into public.entradas (ingresso_id, evento_id, usuario_id, metodo_validacao, entrada_em)
  values (v_i1, v_evento, v_admin, 'QR_CODE', '2026-11-01 23:30:00-03');

  -- pedido de outro evento nao entra na conta
  insert into public.lotes (id, evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_lote_outro, v_outro, 'Lote X', 1, 100, 99, 'MANUAL', 'ATIVO');
  insert into public.pedidos (id, evento_id, lote_id, codigo, comprador_nome, comprador_telefone, quantidade, tipo_preco, valor_unitario, valor_total, status, pago_em, checkout_token)
  values (v_ped_outro, v_outro, v_lote_outro, 'PO' || replace(v_ped_outro::text,'-',''), 'Outro', '11999990002', 1, 'LOTE', 99, 99, 'PAGO', now(), gen_random_uuid());
  insert into public.pagamentos (pedido_id, provedor, valor, status) values (v_ped_outro, 'DINHEIRO', 99, 'APROVADO');

  -- evento de outra organizacao
  insert into public.organizacoes (nome, slug, taxa_servico)
  values ('Org B', 'org-b-' || replace(gen_random_uuid()::text, '-', ''), 0)
  returning id into v_org_b;
  insert into public.eventos (id, organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, vendas_status, publicacao_status)
  values (v_evento_b, v_org_b, 'Evento Org B', 'ev-painelb-' || replace(v_evento_b::text,'-',''), now() + interval '3 days', 'Galeria', 'Rua 2', 100, 100, 'AGENDADO', 'ABERTAS', 'PUBLICADO');

  -- A) ACL
  if has_function_privilege('anon', 'public.obter_painel_evento_admin(uuid)', 'execute') then raise exception 'A: anon nao deveria executar'; end if;

  -- B) PORTARIA nao ve o dashboard
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  begin
    perform public.obter_painel_evento_admin(v_evento);
    raise exception 'B: PORTARIA deveria ser recusada';
  exception when others then
    if position('Permissao negada' in sqlerrm) = 0 then raise exception 'B: %', sqlerrm; end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  -- C) evento de outra organizacao: nao encontrado
  begin
    perform public.obter_painel_evento_admin(v_evento_b);
    raise exception 'C: evento de outra organizacao deveria ser recusado';
  exception when others then
    if position('nao encontrado' in sqlerrm) = 0 then raise exception 'C: %', sqlerrm; end if;
  end;

  -- D) metricas so do evento
  v_res := public.obter_painel_evento_admin(v_evento);
  v_m := v_res->'metricas';
  if (v_m->>'vendidos')::int <> 2 then raise exception 'D: vendidos (%)', v_m; end if;
  if (v_m->>'utilizados')::int <> 1 then raise exception 'D: utilizados (%)', v_m; end if;
  if (v_m->>'naoEntraram')::int <> 1 then raise exception 'D: naoEntraram (%)', v_m; end if;
  if (v_m->>'faturamento')::numeric <> 60 then raise exception 'D: faturamento (%)', v_m; end if;
  if (v_m->>'ticketMedio')::numeric <> 30 then raise exception 'D: ticketMedio (%)', v_m; end if;
  if (v_res->'evento'->>'evento_id')::uuid <> v_evento then raise exception 'D: evento (%)', v_res->'evento'; end if;

  -- E) entradas por hora no horario de Sao Paulo
  if jsonb_array_length(v_res->'entradasPorHora') <> 1 then raise exception 'E: horas (%)', v_res->'entradasPorHora'; end if;
  if v_res->'entradasPorHora'->0->>'hora' <> '23h' then raise exception 'E: hora deveria ser 23h (%)', v_res->'entradasPorHora'; end if;

  -- F) pagamentos, pedidos e entradas recentes
  if (v_res->'pagamentosPorStatus'->0->>'value')::int <> 1 then raise exception 'F: pagos (%)', v_res->'pagamentosPorStatus'; end if;
  if jsonb_array_length(v_res->'pedidosRecentes') <> 1 then raise exception 'F: pedidos (%)', v_res->'pedidosRecentes'; end if;
  if (v_res->'pedidosRecentes'->0->>'entrance_used')::int <> 1 then raise exception 'F: entrance_used (%)', v_res->'pedidosRecentes'; end if;
  if jsonb_array_length(v_res->'entradasRecentes') <> 1 then raise exception 'F: entradas (%)', v_res->'entradasRecentes'; end if;

  -- G) extras: lote atual
  if v_res->'extras'->'loteAtual'->>'nome' <> 'Lote 1' then raise exception 'G: lote atual (%)', v_res->'extras'; end if;
end $$;

select 'painel_evento_admin: todos os testes passaram' as resultado;

rollback;
