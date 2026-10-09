-- =============================================================================
-- GZ1 Ingresso - Testes: financeiro administrativo
-- Arquivo: supabase/tests/financeiro_admin.test.sql
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
  if has_function_privilege('anon', 'public.obter_financeiro_admin(uuid, text, timestamptz, timestamptz, public.status_pagamento, public.provedor_pagamento)', 'EXECUTE') then
    raise exception 'A: anon nao pode executar obter_financeiro_admin';
  end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_portaria uuid := gen_random_uuid();
  v_e uuid; v_e2 uuid;
  v_r jsonb; v_pag jsonb;
  v_ped_a uuid; v_ped_p uuid; v_ped_rj uuid; v_ped_r uuid;
  v_pay_a uuid; v_pay_p uuid; v_pay_rj uuid; v_pay_r uuid;
  v_pay_e2 uuid;
  v_res jsonb; v_mov jsonb;
  v_n integer;
begin
  insert into auth.users (id) values (v_admin), (v_portaria);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Fin', 'adminfin_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Port Fin', 'portfin_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true);

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Fin','fin-'||replace(gen_random_uuid()::text,'-',''), now()+interval '3 days','L','E',100,50,'AGENDADO','PUBLICADO','ABERTAS') returning id into v_e;
  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Fin 2','fin2-'||replace(gen_random_uuid()::text,'-',''), now()+interval '3 days','L','E',100,50,'AGENDADO','PUBLICADO','ABERTAS') returning id into v_e2;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status) values (v_e,'Lote F',1,100,40,'MANUAL','ATIVO');
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status) values (v_e2,'Lote F2',1,100,40,'MANUAL','ATIVO');

  -- APROVADO (40)
  v_r := public.criar_reserva(v_e,'Fin A','11999990050','a@test.local',array['A']);
  v_ped_a := (v_r->>'pedido_id')::uuid;
  v_pag := public.criar_pagamento_pendente_por_token((v_r->>'checkout_token')::uuid,'MERCADO_PAGO');
  v_pay_a := (v_pag->>'pagamento_id')::uuid;
  perform public.confirmar_pagamento(v_pay_a, 'tx-fin-a');

  -- PENDENTE (40)
  v_r := public.criar_reserva(v_e,'Fin P','11999990051','p@test.local',array['P']);
  v_ped_p := (v_r->>'pedido_id')::uuid;
  v_pag := public.criar_pagamento_pendente_por_token((v_r->>'checkout_token')::uuid,'MERCADO_PAGO');
  v_pay_p := (v_pag->>'pagamento_id')::uuid;

  -- REJEITADO (40)
  v_r := public.criar_reserva(v_e,'Fin RJ','11999990052','rj@test.local',array['RJ']);
  v_ped_rj := (v_r->>'pedido_id')::uuid;
  v_pag := public.criar_pagamento_pendente_por_token((v_r->>'checkout_token')::uuid,'MERCADO_PAGO');
  v_pay_rj := (v_pag->>'pagamento_id')::uuid;
  update public.pagamentos set status='REJEITADO' where id=v_pay_rj;

  -- REEMBOLSADO (valor_reembolsado=40)
  v_r := public.criar_reserva(v_e,'Fin R','11999990053','r@test.local',array['R']);
  v_ped_r := (v_r->>'pedido_id')::uuid;
  v_pag := public.criar_pagamento_pendente_por_token((v_r->>'checkout_token')::uuid,'MERCADO_PAGO');
  v_pay_r := (v_pag->>'pagamento_id')::uuid;
  perform public.confirmar_pagamento(v_pay_r, 'tx-fin-r');
  update public.pagamentos set status='REEMBOLSADO', valor_reembolsado=40, reembolsado_em=now() where id=v_pay_r;

  -- Evento 2: APROVADO (40)
  v_r := public.criar_reserva(v_e2,'Fin E2','11999990054','e2@test.local',array['E2']);
  v_pag := public.criar_pagamento_pendente_por_token((v_r->>'checkout_token')::uuid,'MERCADO_PAGO');
  v_pay_e2 := (v_pag->>'pagamento_id')::uuid;
  perform public.confirmar_pagamento(v_pay_e2, 'tx-fin-e2');

  -- B) PORTARIA negado
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  begin
    perform public.obter_financeiro_admin();
    raise exception 'B: PORTARIA nao deveria acessar financeiro admin';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'B: inesperado: %', sqlerrm; end if;
  end;

  -- C) ADMIN permitido
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_res := public.obter_financeiro_admin(p_evento_id => v_e);
  v_mov := v_res->'movimentacoes';
  if jsonb_typeof(v_mov) <> 'array' then raise exception 'C/N: movimentacoes deveriam ser array'; end if;
  if jsonb_array_length(v_mov) <> 4 then raise exception 'N: esperado 4 movimentacoes, obtido %', jsonb_array_length(v_mov); end if;

  -- D) faturamento somente APROVADO
  if (v_res->'resumo'->>'valorAprovado')::numeric <> 40 then
    raise exception 'D: valorAprovado deveria ser 40 (obtido %)', v_res->'resumo'->>'valorAprovado';
  end if;
  if (v_res->'resumo'->>'aprovados')::int <> 1 then raise exception 'D: aprovados deveria ser 1'; end if;

  -- E) PENDENTE nao entra no faturamento
  if (v_res->'resumo'->>'pendente')::numeric <> 40 then raise exception 'E: pendente deveria ser 40'; end if;

  -- F/G/H) REJEITADO/CANCELADO/EXPIRADO nao entram no faturamento (ja garantido por valorAprovado=40)

  -- I) reembolso conforme valor_reembolsado + liquido = aprovado - reembolsado
  if (v_res->'resumo'->>'reembolsado')::numeric <> 40 then raise exception 'I: reembolsado deveria ser 40'; end if;
  if (v_res->'resumo'->>'liquido')::numeric <> 0 then raise exception 'I: liquido deveria ser 0'; end if;

  -- J) filtro evento (evento2 tem 1 aprovado)
  v_res := public.obter_financeiro_admin(p_evento_id => v_e2);
  if jsonb_array_length(v_res->'movimentacoes') <> 1 then raise exception 'J: evento2 deveria ter 1'; end if;
  if (v_res->'resumo'->>'valorAprovado')::numeric <> 40 then raise exception 'J: evento2 aprovado deveria ser 40'; end if;

  -- K) filtro periodo (de = futuro => vazio)
  v_res := public.obter_financeiro_admin(p_evento_id => v_e, p_de => now() + interval '1 day');
  if jsonb_array_length(v_res->'movimentacoes') <> 0 then raise exception 'K: periodo futuro deveria ser vazio'; end if;

  -- L) filtro provedor (MERCADO_PAGO => 4)
  v_res := public.obter_financeiro_admin(p_evento_id => v_e, p_provedor => 'MERCADO_PAGO');
  if jsonb_array_length(v_res->'movimentacoes') <> 4 then raise exception 'L: filtro provedor incorreto'; end if;

  -- O) ordenacao por coalesce(confirmado_em, criado_em) DESC
  v_res := public.obter_financeiro_admin(p_evento_id => v_e);
  v_mov := v_res->'movimentacoes';
  if (v_mov->0->>'criado_em') < (v_mov->1->>'criado_em') then raise exception 'O: ordenacao DESC incorreta'; end if;

  -- P) sem secrets
  if (v_mov->0 ? 'checkout_token') or (v_mov->0 ? 'qr_token') or (v_mov->0 ? 'pix_copia_cola') or (v_mov->0 ? 'pix_qr_code') then
    raise exception 'P: dados sensiveis expostos';
  end if;
end $$;

select 'financeiro_admin: todos os testes passaram' as resultado;

rollback;
