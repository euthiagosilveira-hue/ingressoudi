-- =============================================================================
-- GZ1 Ingresso - Testes: pedidos administrativos (listagem + detalhe)
-- Arquivo: supabase/tests/pedidos_admin.test.sql
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
  if has_function_privilege('anon', 'public.listar_pedidos_admin(uuid, text, public.status_pedido, public.status_pagamento, public.tipo_preco_pedido, timestamptz, timestamptz)', 'EXECUTE') then
    raise exception 'A: anon nao pode executar listar_pedidos_admin';
  end if;
  if has_function_privilege('anon', 'public.obter_pedido_admin(uuid)', 'EXECUTE') then
    raise exception 'A: anon nao pode executar obter_pedido_admin';
  end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_portaria uuid := gen_random_uuid();
  v_e1 uuid; v_e2 uuid;
  v_r1 jsonb; v_r2 jsonb; v_r3 jsonb; v_pag jsonb;
  v_ped1 uuid; v_ped2 uuid; v_ped3 uuid; v_cod1 text;
  v_lista jsonb; v_det jsonb; v_n integer;
begin
  insert into auth.users (id) values (v_admin), (v_portaria);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Ped', 'adminped_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Port Ped', 'portped_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true);

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Ped 1','ped1-'||replace(gen_random_uuid()::text,'-',''), now() + interval '3 days','L','E',100,50,'AGENDADO','PUBLICADO','ABERTAS') returning id into v_e1;
  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Ped 2','ped2-'||replace(gen_random_uuid()::text,'-',''), now() + interval '3 days','L','E',100,50,'AGENDADO','PUBLICADO','ABERTAS') returning id into v_e2;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_e1,'Lote P1',1,100,40,'MANUAL','ATIVO');
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_e2,'Lote P2',1,100,40,'MANUAL','ATIVO');

  -- ped1 PAGO (dominio), ped2 RESERVADO (evento1), ped3 RESERVADO (evento2)
  v_r1 := public.criar_reserva(v_e1, 'Comprador Um', '11999990001', 'um@test.local', array['P1']);
  v_ped1 := (v_r1->>'pedido_id')::uuid; v_cod1 := v_r1->>'codigo_pedido';
  v_pag := public.criar_pagamento_pendente_por_token((v_r1->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'tx-ped-1');

  v_r2 := public.criar_reserva(v_e1, 'Comprador Dois', '11999990002', 'dois@test.local', array['P2']);
  v_ped2 := (v_r2->>'pedido_id')::uuid;
  v_r3 := public.criar_reserva(v_e2, 'Comprador Tres', '11999990003', 'tres@test.local', array['P3']);
  v_ped3 := (v_r3->>'pedido_id')::uuid;

  -- B) PORTARIA => negado
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  begin
    perform public.listar_pedidos_admin();
    raise exception 'B: PORTARIA nao deveria listar pedidos admin';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then
      raise exception 'B: erro inesperado: %', sqlerrm;
    end if;
  end;

  -- C) ADMIN => permitido
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  -- F) filtro por evento
  v_lista := public.listar_pedidos_admin(p_evento_id => v_e1);
  v_n := jsonb_array_length(v_lista);
  if v_n <> 2 then
    raise exception 'F: evento1 deveria ter 2 pedidos, obtido %', v_n;
  end if;

  -- filtro status PAGO no evento1
  v_lista := public.listar_pedidos_admin(p_evento_id => v_e1, p_status => 'PAGO'::public.status_pedido);
  if jsonb_array_length(v_lista) <> 1 or (v_lista->0->>'id')::uuid <> v_ped1 then
    raise exception 'D: filtro status PAGO incorreto';
  end if;

  -- G) busca por codigo
  v_lista := public.listar_pedidos_admin(p_busca => v_cod1);
  if not exists (select 1 from jsonb_array_elements(v_lista) e where (e->>'id')::uuid = v_ped1) then
    raise exception 'G: busca por codigo falhou';
  end if;

  -- H) busca por telefone
  v_lista := public.listar_pedidos_admin(p_busca => '11999990002');
  if jsonb_array_length(v_lista) <> 1 or (v_lista->0->>'id')::uuid <> v_ped2 then
    raise exception 'H: busca por telefone falhou';
  end if;

  -- I) busca inexistente
  v_lista := public.listar_pedidos_admin(p_busca => 'zzz-nao-existe-zzz');
  if jsonb_array_length(v_lista) <> 0 then
    raise exception 'I: busca inexistente deveria retornar vazio';
  end if;

  -- seguranca: sem checkout_token/qr_token
  v_lista := public.listar_pedidos_admin(p_evento_id => v_e1);
  if (v_lista->0 ? 'checkout_token') or (v_lista->0 ? 'qr_token') then
    raise exception 'seguranca: campos sensiveis expostos';
  end if;

  -- J) detalhe
  v_det := public.obter_pedido_admin(v_ped1);
  if (v_det->>'codigo') <> v_cod1 then
    raise exception 'J: detalhe com codigo incorreto';
  end if;
  if (v_det->'pagamento'->>'status') <> 'APROVADO' then
    raise exception 'J: pagamento do detalhe deveria estar APROVADO';
  end if;
  if jsonb_array_length(v_det->'ingressos') <> 1 then
    raise exception 'J: detalhe deveria ter 1 ingresso';
  end if;
  if (v_det ? 'checkout_token') or (v_det->'ingressos'->0 ? 'qr_token') then
    raise exception 'J: detalhe nao pode expor tokens';
  end if;

  if public.obter_pedido_admin(gen_random_uuid()) is not null then
    raise exception 'J: pedido inexistente deveria retornar null';
  end if;
end $$;

select 'pedidos_admin: todos os testes passaram' as resultado;

rollback;
