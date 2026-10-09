-- =============================================================================
-- GZ1 Ingresso - Testes: busca por nome com desambiguacao (telefone)
-- Arquivo: supabase/tests/portaria_busca_nome_desambiguacao.test.sql
-- Executar como owner. begin/rollback.
--
-- Cobre:
--   * anon sem EXECUTE
--   * PORTARIA e ADMIN podem consultar
--   * telefone do ingresso (comprador)
--   * telefone do VIP (lista_vip)
--   * telefone null (VIP sem telefone)
--   * homonimos retornam como linhas separadas
--   * nenhum campo financeiro/administrativo novo exposto
-- =============================================================================

begin;

do $$
begin
  if has_function_privilege('anon', 'public.buscar_ingressos_por_nome(uuid, text)', 'EXECUTE') then
    raise exception 'anon nao pode executar buscar_ingressos_por_nome';
  end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_portaria uuid := gen_random_uuid();
  v_e uuid;
  v_lote uuid;
  v_ped uuid;
  v_vip1 uuid;
  v_vip2 uuid;
  v_res jsonb;
  v_item jsonb;
  v_n integer;
begin
  insert into auth.users (id) values (v_admin), (v_portaria);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Busca', 'adminbusca_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Port Busca', 'portbusca_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true);

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Busca', 'busca-' || replace(gen_random_uuid()::text,'-',''), now()+interval '2 days', 'L', 'E', 100, 50, 'AGENDADO', 'RASCUNHO', 'ENCERRADAS')
  returning id into v_e;

  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_e, 'Lote', 1, 100, 40, 'MANUAL', 'ATIVO') returning id into v_lote;

  insert into public.pedidos (evento_id, lote_id, codigo, comprador_nome, comprador_telefone, quantidade, tipo_preco, valor_unitario, valor_total, status, reserva_expira_em, pago_em)
  values (v_e, v_lote, 'GZBUSCA1', 'Maria Homonima', '34999991234', 1, 'LOTE', 40, 40, 'PAGO', now(), now())
  returning id into v_ped;

  insert into public.ingressos (pedido_id, evento_id, lote_id, codigo, participante_nome, valor_unitario, qr_token, status)
  values (v_ped, v_e, v_lote, 'GZBUSCA1-01', 'Maria Homonima', 40, gen_random_uuid()::text, 'VALIDO');

  insert into public.lista_vip (evento_id, nome, telefone, criado_por_usuario_id)
  values (v_e, 'Maria Homonima', '34988887777', v_admin) returning id into v_vip1;

  insert into public.lista_vip (evento_id, nome, telefone, criado_por_usuario_id)
  values (v_e, 'Maria Homonima', null, v_admin) returning id into v_vip2;

  -- PORTARIA pode consultar
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);

  v_res := public.buscar_ingressos_por_nome(v_e, 'Maria');
  if jsonb_array_length(v_res) <> 3 then
    raise exception 'esperado 3 resultados (1 ingresso + 2 VIP), obtido %', jsonb_array_length(v_res);
  end if;

  -- telefone do ingresso
  select el into v_item from jsonb_array_elements(v_res) el where el->>'origem' = 'INGRESSO';
  if (v_item->>'telefone') <> '34999991234' then
    raise exception 'telefone do ingresso incorreto: %', v_item->>'telefone';
  end if;

  -- telefone do VIP com valor
  select el into v_item from jsonb_array_elements(v_res) el where el->>'vip_id' = v_vip1::text;
  if (v_item->>'telefone') <> '34988887777' then
    raise exception 'telefone do VIP incorreto: %', v_item->>'telefone';
  end if;

  -- VIP sem telefone -> null
  select el into v_item from jsonb_array_elements(v_res) el where el->>'vip_id' = v_vip2::text;
  if (v_item->>'telefone') is not null then
    raise exception 'VIP sem telefone deveria retornar null';
  end if;

  -- homonimos retornam como linhas separadas
  select count(*) into v_n from jsonb_array_elements(v_res) el
   where el->>'participante_nome' = 'Maria Homonima';
  if v_n <> 3 then
    raise exception 'homonimos deveriam retornar separados (obtido %)', v_n;
  end if;

  -- nenhum campo financeiro/administrativo novo exposto
  select el into v_item from jsonb_array_elements(v_res) el limit 1;
  if (v_item ? 'valor') or (v_item ? 'valor_unitario') or (v_item ? 'valor_total')
     or (v_item ? 'pagamento') or (v_item ? 'email') or (v_item ? 'comprador_email') then
    raise exception 'campo financeiro/administrativo exposto: %', v_item;
  end if;

  -- ADMIN tambem consulta
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_res := public.buscar_ingressos_por_nome(v_e, 'Maria');
  if jsonb_array_length(v_res) <> 3 then
    raise exception 'ADMIN deveria ver 3 resultados, obtido %', jsonb_array_length(v_res);
  end if;
end $$;

select 'portaria_busca_nome_desambiguacao: todos os testes passaram' as resultado;

rollback;
