-- =============================================================================
-- GZ1 Ingresso - Testes: contadores do sidebar administrativo
-- Arquivo: supabase/tests/contadores_sidebar_admin.test.sql
-- Executar como owner. begin/rollback.
-- =============================================================================

begin;

do $$
begin
  if has_function_privilege('anon', 'public.obter_contadores_admin()', 'EXECUTE') then
    raise exception 'A: anon nao pode executar obter_contadores_admin';
  end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_portaria uuid := gen_random_uuid();
  v_e uuid;
  v_r jsonb; v_pag jsonb;
  v_ped uuid;
  v_i1 uuid; v_i2 uuid;
  v_antes jsonb; v_depois jsonb;
  v_ped0 integer; v_ent0 integer;
begin
  insert into auth.users (id) values (v_admin), (v_portaria);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Operador Admin Cont', 'openadmincont_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Operador Port Cont', 'openportcont_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true);

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  v_antes := public.obter_contadores_admin();
  v_ped0 := (v_antes->>'pedidos')::integer;
  v_ent0 := (v_antes->>'entradas')::integer;

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Cont', 'cont-'||replace(gen_random_uuid()::text,'-',''), now()+interval '3 days','L','E',100,50,'AGENDADO','PUBLICADO','ABERTAS') returning id into v_e;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status) values (v_e,'Lote Cont',1,100,40,'MANUAL','ATIVO');

  v_r := public.criar_reserva(v_e,'Comprador Cont','11999990050','cont@test.local',array['Cont A','Cont B']);
  v_ped := (v_r->>'pedido_id')::uuid;
  v_pag := public.criar_pagamento_pendente_por_token((v_r->>'checkout_token')::uuid,'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid,'tx-cont-1');
  select id into v_i1 from public.ingressos where pedido_id=v_ped order by codigo limit 1;
  select id into v_i2 from public.ingressos where pedido_id=v_ped order by codigo offset 1 limit 1;

  insert into public.entradas (ingresso_id, evento_id, usuario_id, metodo_validacao, entrada_em)
  values (v_i1, v_e, v_admin, 'QR_CODE', now());
  insert into public.entradas (ingresso_id, evento_id, usuario_id, metodo_validacao, entrada_em, anulada_em, anulada_por_usuario_id, motivo_anulacao)
  values (v_i2, v_e, v_admin, 'QR_CODE', now(), now(), v_admin, 'teste');

  v_depois := public.obter_contadores_admin();

  -- B) pedidos reflete +1
  if (v_depois->>'pedidos')::integer <> v_ped0 + 1 then
    raise exception 'B: pedidos esperado %, obtido %', v_ped0 + 1, (v_depois->>'pedidos')::integer;
  end if;

  -- C) entradas efetivas conta apenas a nao anulada (+1)
  if (v_depois->>'entradas')::integer <> v_ent0 + 1 then
    raise exception 'C: entradas efetivas esperado %, obtido %', v_ent0 + 1, (v_depois->>'entradas')::integer;
  end if;

  -- D) PORTARIA negado
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  begin
    perform public.obter_contadores_admin();
    raise exception 'D: PORTARIA nao deveria acessar contadores';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'D: inesperado: %', sqlerrm; end if;
  end;
end $$;

select 'contadores_sidebar_admin: todos os testes passaram' as resultado;

rollback;
