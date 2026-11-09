-- =============================================================================
-- Ingressoudi - Testes: perfil Socio do Evento (socios_eventos e RPCs do socio).
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
  v_socio uuid := gen_random_uuid();
  v_evento uuid := gen_random_uuid();
  v_outro uuid := gen_random_uuid();
  v_lote uuid := gen_random_uuid();
  v_lote_outro uuid := gen_random_uuid();
  v_ped uuid := gen_random_uuid();
  v_ped_pix uuid := gen_random_uuid();
  v_ped_outro uuid := gen_random_uuid();
  v_i1 uuid := gen_random_uuid();
  v_i2 uuid := gen_random_uuid();
  v_i3 uuid := gen_random_uuid();
  v_org_b uuid;
  v_evento_b uuid := gen_random_uuid();
  v_res jsonb;
  v_r jsonb;
  v_lista jsonb;
begin
  insert into auth.users (id) values (v_admin), (v_portaria), (v_socio);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Socio', 'adminsocio_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Port Socio', 'portsocio_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true),
    (v_socio, 'Socio Evento', 'socio_' || replace(v_socio::text,'-','') || '@test.local', 'SOCIO', true);

  insert into public.eventos (id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, vendas_status, publicacao_status) values
    (v_evento, 'Evento do Socio', 'ev-socio-' || replace(v_evento::text,'-',''), now() + interval '3 days', 'Galeria', 'Rua 1', 100, 100, 'AGENDADO', 'ABERTAS', 'PUBLICADO'),
    (v_outro, 'Outro Evento', 'ev-socio-outro-' || replace(v_outro::text,'-',''), now() + interval '5 days', 'Galeria', 'Rua 1', 100, 100, 'AGENDADO', 'ABERTAS', 'PUBLICADO');
  insert into public.lotes (id, evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_lote, v_evento, 'Lote 1', 1, 100, 30, 'MANUAL', 'ATIVO');

  -- venda na porta: 2 ingressos (1 ja entrou)
  insert into public.pedidos (id, evento_id, lote_id, codigo, comprador_nome, comprador_telefone, quantidade, tipo_preco, valor_unitario, valor_total, status, pago_em, checkout_token)
  values (v_ped, v_evento, v_lote, 'SP' || replace(v_ped::text,'-',''), 'Comprador Porta', '11999990001', 2, 'LOTE', 30, 60, 'PAGO', '2026-11-01 20:00:00-03', gen_random_uuid());
  insert into public.pagamentos (pedido_id, provedor, valor, status) values (v_ped, 'DINHEIRO', 60, 'APROVADO');
  insert into public.ingressos (id, pedido_id, evento_id, lote_id, codigo, participante_nome, valor_unitario, qr_token, status, utilizado_em) values
    (v_i1, v_ped, v_evento, v_lote, 'SP1' || substr(replace(gen_random_uuid()::text,'-',''),1,12), 'Ana', 30, gen_random_uuid()::text, 'UTILIZADO', '2026-11-01 23:30:00-03'),
    (v_i2, v_ped, v_evento, v_lote, 'SP2' || substr(replace(gen_random_uuid()::text,'-',''),1,12), 'Bia', 30, gen_random_uuid()::text, 'VALIDO', null);
  insert into public.entradas (ingresso_id, evento_id, usuario_id, metodo_validacao, entrada_em)
  values (v_i1, v_evento, v_admin, 'QR_CODE', '2026-11-01 23:30:00-03');

  -- venda online por Pix: 1 ingresso de 30 + taxa 3
  insert into public.pedidos (id, evento_id, lote_id, codigo, comprador_nome, comprador_telefone, quantidade, tipo_preco, valor_unitario, valor_total, status, pago_em, checkout_token, taxa_servico_unitaria, taxa_repassada, valor_taxa_total)
  values (v_ped_pix, v_evento, v_lote, 'SX' || replace(v_ped_pix::text,'-',''), 'Comprador Pix', '11999990003', 1, 'LOTE', 30, 33, 'PAGO', '2026-11-02 10:00:00-03', gen_random_uuid(), 3, true, 3);
  insert into public.pagamentos (pedido_id, provedor, valor, status, forma_pagamento, confirmado_em) values (v_ped_pix, 'MERCADO_PAGO', 33, 'APROVADO', 'PIX', '2026-11-02 10:00:00-03');
  insert into public.ingressos (id, pedido_id, evento_id, lote_id, codigo, participante_nome, valor_unitario, qr_token, status) values
    (v_i3, v_ped_pix, v_evento, v_lote, 'SX1' || substr(replace(gen_random_uuid()::text,'-',''),1,12), 'Caio', 30, gen_random_uuid()::text, 'VALIDO');

  -- outro evento da mesma casa (o socio NAO acompanha)
  insert into public.lotes (id, evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_lote_outro, v_outro, 'Lote X', 1, 100, 99, 'MANUAL', 'ATIVO');
  insert into public.pedidos (id, evento_id, lote_id, codigo, comprador_nome, comprador_telefone, quantidade, tipo_preco, valor_unitario, valor_total, status, pago_em, checkout_token)
  values (v_ped_outro, v_outro, v_lote_outro, 'SO' || replace(v_ped_outro::text,'-',''), 'Outro', '11999990002', 1, 'LOTE', 99, 99, 'PAGO', now(), gen_random_uuid());
  insert into public.pagamentos (pedido_id, provedor, valor, status) values (v_ped_outro, 'DINHEIRO', 99, 'APROVADO');

  -- evento de outra organizacao
  insert into public.organizacoes (nome, slug, taxa_servico)
  values ('Org B', 'org-b-' || replace(gen_random_uuid()::text, '-', ''), 0)
  returning id into v_org_b;
  insert into public.eventos (id, organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, vendas_status, publicacao_status)
  values (v_evento_b, v_org_b, 'Evento Org B', 'ev-socio-b-' || replace(v_evento_b::text,'-',''), now() + interval '3 days', 'Galeria', 'Rua 2', 100, 100, 'AGENDADO', 'ABERTAS', 'PUBLICADO');

  -- A) ACL: anon nao executa; tabela fechada para authenticated
  if has_function_privilege('anon', 'public.listar_eventos_socio()', 'execute') then raise exception 'A: anon listar'; end if;
  if has_function_privilege('anon', 'public.obter_vendas_evento_socio(uuid)', 'execute') then raise exception 'A: anon obter'; end if;
  if has_function_privilege('anon', 'public.definir_eventos_socio_admin(uuid, uuid[])', 'execute') then raise exception 'A: anon definir'; end if;
  if has_table_privilege('authenticated', 'public.socios_eventos', 'select') then raise exception 'A: tabela aberta'; end if;

  -- B) socio sem eventos: lista vazia
  perform set_config('request.jwt.claims', json_build_object('sub', v_socio::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_socio::text, true);
  if jsonb_array_length(public.listar_eventos_socio()) <> 0 then raise exception 'B: deveria estar vazia'; end if;

  -- C) socio nao define os proprios eventos
  begin
    perform public.definir_eventos_socio_admin(v_socio, array[v_evento]);
    raise exception 'C: socio nao pode definir eventos';
  exception when others then
    if position('Permissao negada' in sqlerrm) = 0 then raise exception 'C: %', sqlerrm; end if;
  end;

  -- D) admin define eventos (valida perfil e casa)
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  begin
    perform public.definir_eventos_socio_admin(v_portaria, array[v_evento]);
    raise exception 'D1: portaria nao tem eventos de socio';
  exception when others then
    if position('Socio do Evento' in sqlerrm) = 0 then raise exception 'D1: %', sqlerrm; end if;
  end;
  begin
    perform public.definir_eventos_socio_admin(v_socio, array[v_evento, v_evento_b]);
    raise exception 'D2: evento de outra casa deveria ser recusado';
  exception when others then
    if position('nao encontrado' in sqlerrm) = 0 then raise exception 'D2: %', sqlerrm; end if;
  end;
  perform public.definir_eventos_socio_admin(v_socio, array[v_evento, v_outro]);
  perform public.definir_eventos_socio_admin(v_socio, array[v_evento, v_evento]);  -- substitui e ignora repetidos
  if (select count(*) from public.socios_eventos where usuario_id = v_socio) <> 1 then raise exception 'D3: deveria ficar 1 evento'; end if;
  if not exists (select 1 from public.auditoria where acao = 'SOCIO_EVENTOS_DEFINIDOS' and entidade_id = v_socio) then raise exception 'D4: auditoria'; end if;

  -- E) lista de usuarios mostra os eventos do socio
  select x into v_r from jsonb_array_elements(public.listar_usuarios_admin(null)) x where x->>'id' = v_socio::text;
  if v_r->>'perfil' <> 'SOCIO' then raise exception 'E: perfil (%)', v_r; end if;
  if jsonb_array_length(v_r->'eventos_socio') <> 1 or v_r->'eventos_socio'->0->>'nome' <> 'Evento do Socio' then raise exception 'E: eventos (%)', v_r; end if;

  -- F) admin nao usa as telas do socio
  begin
    perform public.listar_eventos_socio();
    raise exception 'F: admin nao deveria listar como socio';
  exception when others then
    if position('Permissao negada' in sqlerrm) = 0 then raise exception 'F: %', sqlerrm; end if;
  end;

  -- G) socio ve so o evento dele, com os numeros certos
  perform set_config('request.jwt.claims', json_build_object('sub', v_socio::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_socio::text, true);
  v_lista := public.listar_eventos_socio();
  if jsonb_array_length(v_lista) <> 1 or (v_lista->0->>'evento_id')::uuid <> v_evento then raise exception 'G: lista (%)', v_lista; end if;

  v_res := public.obter_vendas_evento_socio(v_evento);
  v_r := v_res->'resumo';
  if (v_r->>'vendidos')::int <> 3 then raise exception 'G: vendidos (%)', v_r; end if;
  if (v_r->>'utilizados')::int <> 1 then raise exception 'G: utilizados (%)', v_r; end if;
  if (v_r->>'bruto')::numeric <> 93 then raise exception 'G: bruto (%)', v_r; end if;
  if (v_r->>'taxa')::numeric <> 3 then raise exception 'G: taxa (%)', v_r; end if;
  if (v_r->>'liquido')::numeric <> 90 then raise exception 'G: liquido (%)', v_r; end if;
  if (v_r->>'capacidade')::int <> 100 then raise exception 'G: capacidade (%)', v_r; end if;
  if jsonb_array_length(v_res->'porForma') <> 2 then raise exception 'G: porForma (%)', v_res->'porForma'; end if;
  if not exists (select 1 from jsonb_array_elements(v_res->'porForma') f where f->>'forma' = 'PIX' and (f->>'valor')::numeric = 33) then raise exception 'G: pix (%)', v_res->'porForma'; end if;
  if not exists (select 1 from jsonb_array_elements(v_res->'porForma') f where f->>'forma' = 'PORTA' and (f->>'ingressos')::int = 2) then raise exception 'G: porta (%)', v_res->'porForma'; end if;
  if (v_res->'porLote'->0->>'vendidos')::int <> 3 then raise exception 'G: porLote (%)', v_res->'porLote'; end if;
  if jsonb_array_length(v_res->'porDia') <> 2 or v_res->'porDia'->0->>'dia' <> '2026-11-01' then raise exception 'G: porDia (%)', v_res->'porDia'; end if;
  if v_res->'entradasPorHora'->0->>'hora' <> '23h' then raise exception 'G: entradas (%)', v_res->'entradasPorHora'; end if;
  -- sem dados pessoais de compradores
  if v_res::text like '%Comprador%' or v_res::text like '%11999990%' or v_res::text like '%Ana%' then raise exception 'G: vazou dado de comprador'; end if;

  -- H) evento que o socio nao acompanha e evento de outra casa
  begin
    perform public.obter_vendas_evento_socio(v_outro);
    raise exception 'H1: outro evento deveria ser recusado';
  exception when others then
    if position('nao encontrado' in sqlerrm) = 0 then raise exception 'H1: %', sqlerrm; end if;
  end;
  begin
    perform public.obter_vendas_evento_socio(v_evento_b);
    raise exception 'H2: evento de outra casa deveria ser recusado';
  exception when others then
    if position('nao encontrado' in sqlerrm) = 0 then raise exception 'H2: %', sqlerrm; end if;
  end;

  -- I) socio nao passa nas telas de administrador nem na portaria
  if private.usuario_e_admin() then raise exception 'I: socio virou admin'; end if;
  if private.usuario_pode_operar_portaria() then raise exception 'I: socio opera portaria'; end if;
  begin
    perform public.obter_painel_evento_admin(v_evento);
    raise exception 'I: painel admin deveria ser recusado';
  exception when others then
    if position('Permissao negada' in sqlerrm) = 0 then raise exception 'I: %', sqlerrm; end if;
  end;

  -- J) membro desativado perde o acesso
  update public.membros_organizacao set ativo = false where usuario_id = v_socio;
  begin
    perform public.listar_eventos_socio();
    raise exception 'J: socio desativado deveria ser recusado';
  exception when others then
    if position('Permissao negada' in sqlerrm) = 0 then raise exception 'J: %', sqlerrm; end if;
  end;
end $$;

select 'socio_evento: todos os testes passaram' as resultado;

rollback;
