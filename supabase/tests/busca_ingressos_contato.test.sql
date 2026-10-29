-- =============================================================================
-- Ingressoudi - Testes: busca de ingressos por telefone + e-mail
-- Arquivo: supabase/tests/busca_ingressos_contato.test.sql
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
  -- taxa_servico 0: os testes herdados validam valores sem a taxa da plataforma
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
  v_e uuid; v_e_antigo uuid;
  v_rA jsonb; v_rB jsonb; v_rP jsonb; v_rV jsonb;
  v_pag jsonb; v_res jsonb;
  v_tokA text;
  i integer;
begin
  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Contato','ct-'||replace(gen_random_uuid()::text,'-',''), now()+interval '3 days','L','E',100,50,'AGENDADO','PUBLICADO','ABERTAS')
  returning id into v_e;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_e,'Lote C',1,100,40,'MANUAL','ATIVO');

  -- A e B: dois pedidos PAGOS do mesmo comprador (telefone com mascara, e-mail com maiuscula)
  v_rA := public.criar_reserva(v_e,'Comprador Contato','(31) 98888-0101','Contato@Test.local',array['Ct A']);
  v_tokA := v_rA->>'checkout_token';
  v_pag := public.criar_pagamento_pendente_por_token((v_rA->>'checkout_token')::uuid,'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid,'tx-ct-A');

  v_rB := public.criar_reserva(v_e,'Comprador Contato','31988880101','contato@test.local',array['Ct B1','Ct B2']);
  v_pag := public.criar_pagamento_pendente_por_token((v_rB->>'checkout_token')::uuid,'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid,'tx-ct-B');

  -- P: pedido so reservado (nao pago) do mesmo comprador
  v_rP := public.criar_reserva(v_e,'Comprador Contato','31988880101','contato@test.local',array['Ct P']);

  -- 1) telefone + e-mail corretos => os 2 pedidos pagos, com checkout_token e sem qr_token
  v_res := public.buscar_ingressos_contato('31988880101', 'contato@test.local');
  if (v_res->>'ok')::boolean is not true then raise exception '1: deveria encontrar'; end if;
  if jsonb_array_length(v_res->'pedidos') <> 2 then
    raise exception '1: esperado 2 pedidos, veio %', jsonb_array_length(v_res->'pedidos');
  end if;
  if not exists (select 1 from jsonb_array_elements(v_res->'pedidos') p where p->>'checkout_token' = v_tokA) then
    raise exception '1: checkout_token do pedido A ausente';
  end if;
  if v_res::text like '%qr_token%' then raise exception '1: nao pode expor qr_token'; end if;
  if exists (select 1 from jsonb_array_elements(v_res->'pedidos') p where p->>'pedido_id' = v_rP->>'pedido_id') then
    raise exception '1: pedido nao pago nao pode aparecer';
  end if;
  if not exists (select 1 from jsonb_array_elements(v_res->'pedidos') p where (p->>'quantidade')::int = 2) then
    raise exception '1: quantidade do pedido B deveria ser 2';
  end if;

  -- 2) com +55, espacos e e-mail em maiuscula => encontra
  v_res := public.buscar_ingressos_contato('+55 31 9 8888-0101', '  CONTATO@test.LOCAL ');
  if (v_res->>'ok')::boolean is not true then raise exception '2: formato diferente deveria casar'; end if;

  -- 3) e-mail errado => generico
  v_res := public.buscar_ingressos_contato('31988880101', 'outro@test.local');
  if (v_res->>'ok')::boolean is not false or v_res ? 'pedidos' then raise exception '3: e-mail errado deveria falhar'; end if;

  -- 4) telefone errado => generico
  v_res := public.buscar_ingressos_contato('31988889999', 'contato@test.local');
  if (v_res->>'ok')::boolean is not false then raise exception '4: telefone errado deveria falhar'; end if;

  -- 5) dados incompletos => generico
  v_res := public.buscar_ingressos_contato('3198', 'contato@test.local');
  if (v_res->>'ok')::boolean is not false then raise exception '5: telefone curto deveria falhar'; end if;
  v_res := public.buscar_ingressos_contato('31988880101', 'sem-arroba');
  if (v_res->>'ok')::boolean is not false then raise exception '5: e-mail invalido deveria falhar'; end if;

  -- 6) evento antigo (mais de 2 dias) nao aparece
  update public.eventos set inicio_em = now() - interval '5 days' where id = v_e;
  v_res := public.buscar_ingressos_contato('31988880101', 'contato@test.local');
  if (v_res->>'ok')::boolean is not false then raise exception '6: evento antigo nao deveria aparecer'; end if;
  update public.eventos set inicio_em = now() + interval '3 days' where id = v_e;

  -- 7) rate limit: 5 falhas no telefone bloqueiam ate os dados certos
  for i in 1..5 loop
    perform public.buscar_ingressos_contato('31988880101', 'errado'||i||'@test.local');
  end loop;
  v_res := public.buscar_ingressos_contato('31988880101', 'contato@test.local');
  if (v_res->>'ok')::boolean is not false then raise exception '7: rate limit deveria bloquear'; end if;
end $$;

select 'busca_ingressos_contato: todos os testes passaram' as resultado;

rollback;
