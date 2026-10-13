-- =============================================================================
-- GZ1 Ingresso - Testes: dashboard administrativo
-- Arquivo: supabase/tests/dashboard_admin.test.sql
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
  insert into public.organizacoes (nome, slug)
  values ('Org Teste', 'org-teste-' || replace(gen_random_uuid()::text, '-', ''))
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
begin
  if has_function_privilege('anon', 'public.obter_dashboard_admin()', 'EXECUTE') then
    raise exception 'A: anon nao pode executar obter_dashboard_admin';
  end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_portaria uuid := gen_random_uuid();
  v_e uuid; v_e2 uuid;
  v_r jsonb; v_pag jsonb;
  v_ped uuid; v_pag2 jsonb; v_ped2 uuid;
  v_i1 uuid; v_i2 uuid; v_i3 uuid;
  v_res jsonb; v_m jsonb;
  v_base_vend integer; v_base_util integer; v_base_fat numeric;
begin
  insert into auth.users (id) values (v_admin), (v_portaria);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Dash', 'admindash_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Port Dash', 'portdash_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true);

  -- baseline global (a RPC e global; ha fixtures reais no banco)
  select count(*) filter (where status in ('VALIDO','UTILIZADO')) into v_base_vend from public.ingressos;
  select count(*) filter (where status = 'UTILIZADO') into v_base_util from public.ingressos;
  select coalesce(sum(valor), 0) into v_base_fat from public.pagamentos where status = 'APROVADO';

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Dash','dash-'||replace(gen_random_uuid()::text,'-',''), now()+interval '3 days','L','E',100,50,'AGENDADO','PUBLICADO','ABERTAS') returning id into v_e;
  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Dash 2','dash2-'||replace(gen_random_uuid()::text,'-',''), now()+interval '5 days','L','E',100,50,'AGENDADO','PUBLICADO','ABERTAS') returning id into v_e2;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status) values (v_e,'Lote D',1,100,40,'MANUAL','ATIVO');

  -- pedido PAGO com 3 ingressos (confirm) no evento v_e
  v_r := public.criar_reserva(v_e,'Comprador Dash','11999990060','dash@test.local',array['Dash 1','Dash 2','Dash 3']);
  v_ped := (v_r->>'pedido_id')::uuid;
  v_pag := public.criar_pagamento_pendente_por_token((v_r->>'checkout_token')::uuid,'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid,'tx-dash-1');
  select id into v_i1 from public.ingressos where pedido_id=v_ped order by codigo limit 1;
  select id into v_i2 from public.ingressos where pedido_id=v_ped order by codigo offset 1 limit 1;
  select id into v_i3 from public.ingressos where pedido_id=v_ped order by codigo offset 2 limit 1;

  -- 1 utilizado + 2 entradas efetivas
  update public.ingressos set status='UTILIZADO', utilizado_em=now() where id=v_i1;
  insert into public.entradas (ingresso_id, evento_id, usuario_id, metodo_validacao, entrada_em)
  values (v_i1, v_e, v_admin, 'QR_CODE', now());
  insert into public.entradas (ingresso_id, evento_id, usuario_id, metodo_validacao, entrada_em)
  values (v_i2, v_e, v_admin, 'NOME', now());

  -- pagamento PENDENTE (nao entra no faturamento)
  v_r := public.criar_reserva(v_e,'Comprador Dash P','11999990061',null,array['Dash P']);
  v_pag2 := public.criar_pagamento_pendente_por_token((v_r->>'checkout_token')::uuid,'MERCADO_PAGO');

  -- torna v_e EM_ANDAMENTO (para evento atual)
  update public.eventos set status='EM_ANDAMENTO', inicio_em = now() - interval '1 hour', vendas_status='ENCERRADAS' where id=v_e;

  -- B) PORTARIA negado
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  begin
    perform public.obter_dashboard_admin();
    raise exception 'B: PORTARIA nao deveria acessar dashboard admin';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'B: inesperado: %', sqlerrm; end if;
  end;

  -- C) ADMIN permitido
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_res := public.obter_dashboard_admin();
  v_m := v_res->'metricas';

  -- D) metricas reais (delta vs baseline): +3 vendidos, +1 utilizado
  if (v_m->>'vendidos')::int <> v_base_vend + 3 then raise exception 'D: vendidos deveria ser % (obtido %)', v_base_vend + 3, v_m->>'vendidos'; end if;
  if (v_m->>'utilizados')::int <> v_base_util + 1 then raise exception 'D: utilizados deveria ser %', v_base_util + 1; end if;
  if (v_m->>'naoEntraram')::int <> (v_m->>'vendidos')::int - (v_m->>'utilizados')::int then
    raise exception 'D/F: naoEntraram inconsistente';
  end if;

  -- E) faturamento somente APROVADO (delta +120 = 3 ingressos x 40)
  if (v_m->>'faturamento')::numeric <> v_base_fat + 120 then raise exception 'E: faturamento deveria ser % (obtido %)', v_base_fat + 120, v_m->>'faturamento'; end if;

  -- G) evento EM_ANDAMENTO prioritario
  if (v_res->'evento'->>'status') <> 'EM_ANDAMENTO' then raise exception 'G: evento deveria ser EM_ANDAMENTO'; end if;

  -- I) entradas por hora: sempre 11 buckets
  if jsonb_array_length(v_res->'entradasPorHora') <> 11 then raise exception 'I: entradasPorHora deveria ter 11'; end if;

  -- J) pagamentos por status: 3 slices
  if jsonb_array_length(v_res->'pagamentosPorStatus') <> 3 then raise exception 'J: pagamentosPorStatus deveria ter 3'; end if;

  -- K) pedidos recentes
  if jsonb_array_length(v_res->'pedidosRecentes') < 1 then raise exception 'K: pedidosRecentes vazio'; end if;

  -- L) entradas recentes (lista global; pelo menos as inseridas)
  if jsonb_array_length(v_res->'entradasRecentes') < 2 then raise exception 'L: entradasRecentes deveria ter ao menos 2'; end if;

  -- M) sem secrets
  if (v_res ? 'checkout_token') or (v_res->'entradasRecentes'->0 ? 'qr_token') or (v_res ? 'qr_token') then
    raise exception 'M: dados sensiveis expostos';
  end if;
end $$;

select 'dashboard_admin: todos os testes passaram' as resultado;

rollback;
