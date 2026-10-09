-- =============================================================================
-- GZ1 Ingresso - Testes: checkout publico seguro (checkout_token)
-- Arquivo: supabase/tests/checkout_publico_seguro.test.sql
-- Executar como owner/service_role. begin/rollback (nao persiste dados).
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
declare
  v_evento_id uuid;
  v_lote_id uuid;
  v_r1 jsonb;
  v_r2 jsonb;
  v_r3 jsonb;
  v_r4 jsonb;
  v_token1 uuid;
  v_token2 uuid;
  v_pedido1 uuid;
  v_consulta jsonb;
  v_pag jsonb;
  v_pag2 jsonb;
  v_pag_id uuid;
  v_pag_id2 uuid;
  v_count integer;
  v_expira_em timestamptz;
begin
  -- fixture
  insert into public.eventos (
    nome, slug, inicio_em, local, endereco,
    capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status
  ) values (
    'Teste Checkout Token', 'teste-checkout-' || replace(gen_random_uuid()::text, '-', ''),
    now() + interval '20 days', 'Local T', 'End T',
    200, 100, 'AGENDADO', 'PUBLICADO', 'ABERTAS'
  ) returning id into v_evento_id;

  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_evento_id, 'Lote T', 1, 100, 40, 'MANUAL', 'ATIVO')
  returning id into v_lote_id;

  -- T1) criar_reserva retorna checkout_token valido
  v_r1 := public.criar_reserva(v_evento_id, 'Comprador T', '34999999999', null, array['A1', 'A2']);
  v_token1 := (v_r1->>'checkout_token')::uuid;
  v_pedido1 := (v_r1->>'pedido_id')::uuid;
  if v_token1 is null then
    raise exception 'T1: checkout_token ausente no retorno';
  end if;

  -- T2) token persistido == token retornado
  if (select checkout_token from public.pedidos where id = v_pedido1) <> v_token1 then
    raise exception 'T2: token persistido difere do retornado';
  end if;

  -- T3) tokens unicos entre pedidos
  v_r2 := public.criar_reserva(v_evento_id, 'Comprador T2', '34999999998', null, array['B1']);
  v_token2 := (v_r2->>'checkout_token')::uuid;
  if v_token2 = v_token1 then
    raise exception 'T3: tokens repetidos';
  end if;

  -- T4) consulta por token retorna o pedido correto
  v_consulta := public.obter_checkout_pedido(v_token1);
  if (v_consulta->>'pedido_id')::uuid <> v_pedido1 then
    raise exception 'T4: obter_checkout_pedido retornou pedido errado';
  end if;
  if (v_consulta->>'codigo_pedido') <> (v_r1->>'codigo_pedido') then
    raise exception 'T4: codigo_pedido divergente';
  end if;
  if (v_consulta->>'valor_total')::numeric <> 80 then
    raise exception 'T4: valor_total esperado 80';
  end if;
  if v_consulta->'pagamento' <> 'null'::jsonb then
    raise exception 'T4: pagamento deveria ser null antes da criacao';
  end if;

  -- T5) privacidade: sem PII / qr
  if (v_consulta ? 'comprador_email')
     or (v_consulta ? 'comprador_telefone')
     or (v_consulta ? 'participantes')
     or (v_consulta ? 'qr_token') then
    raise exception 'T5: campos sensiveis expostos na consulta';
  end if;

  -- T6) token inexistente => null (sem vazamento)
  if public.obter_checkout_pedido(gen_random_uuid()) is not null then
    raise exception 'T6: token inexistente deveria retornar null';
  end if;

  -- T7) criar pagamento por token
  v_pag := public.criar_pagamento_pendente_por_token(v_token1, 'STONE');
  v_pag_id := (v_pag->>'pagamento_id')::uuid;
  if (v_pag->>'status') <> 'PENDENTE' then
    raise exception 'T7: status esperado PENDENTE';
  end if;
  if (v_pag->>'provedor') <> 'STONE' then
    raise exception 'T7: provedor esperado STONE';
  end if;
  if (v_pag->>'valor')::numeric <> 80 then
    raise exception 'T7: valor esperado 80';
  end if;
  if (v_pag->>'reutilizado')::boolean then
    raise exception 'T7: primeira criacao nao deveria ser reutilizacao';
  end if;

  -- T8) idempotencia: mesma chamada retorna mesmo pagamento
  v_pag2 := public.criar_pagamento_pendente_por_token(v_token1, 'STONE');
  v_pag_id2 := (v_pag2->>'pagamento_id')::uuid;
  if v_pag_id2 <> v_pag_id then
    raise exception 'T8: idempotencia quebrada (ids diferentes)';
  end if;
  if not (v_pag2->>'reutilizado')::boolean then
    raise exception 'T8: segunda chamada deveria marcar reutilizado=true';
  end if;

  select count(*) into v_count from public.pagamentos where pedido_id = v_pedido1;
  if v_count <> 1 then
    raise exception 'T8: esperado 1 pagamento para o pedido, encontrado %', v_count;
  end if;

  -- T9) pedido expirado => rejeita
  v_r3 := public.criar_reserva(v_evento_id, 'Comprador T3', '34999999997', null, array['C1']);
  update public.pedidos set reserva_expira_em = now() - interval '1 minute'
   where id = (v_r3->>'pedido_id')::uuid;
  begin
    perform public.criar_pagamento_pendente_por_token((v_r3->>'checkout_token')::uuid, 'STONE');
    raise exception 'T9: deveria rejeitar reserva expirada';
  exception
    when others then
      if position('expirada' in lower(sqlerrm)) = 0 then
        raise exception 'T9: erro inesperado: %', sqlerrm;
      end if;
  end;

  -- T10) pedido nao RESERVADO (cancelado) => rejeita
  v_r4 := public.criar_reserva(v_evento_id, 'Comprador T4', '34999999996', null, array['D1']);
  update public.pedidos set status = 'CANCELADO' where id = (v_r4->>'pedido_id')::uuid;
  begin
    perform public.criar_pagamento_pendente_por_token((v_r4->>'checkout_token')::uuid, 'STONE');
    raise exception 'T10: deveria rejeitar pedido CANCELADO';
  exception
    when others then
      if position('reservado' in lower(sqlerrm)) = 0 then
        raise exception 'T10: erro inesperado: %', sqlerrm;
      end if;
  end;
end $$;

-- T11) ACL: nova RPC por token para anon; RPC antiga fechada; confirmacao fechada
do $$
begin
  if not has_function_privilege('anon', 'public.obter_checkout_pedido(uuid)', 'EXECUTE') then
    raise exception 'T11: anon deveria executar obter_checkout_pedido';
  end if;
  if not has_function_privilege('authenticated', 'public.criar_pagamento_pendente_por_token(uuid, public.provedor_pagamento, text, text, text)', 'EXECUTE') then
    raise exception 'T11: authenticated deveria executar criar_pagamento_pendente_por_token';
  end if;
  if has_function_privilege('anon', 'public.criar_pagamento_pendente(uuid, public.provedor_pagamento, text, text, text)', 'EXECUTE') then
    raise exception 'T11: anon NAO pode executar criar_pagamento_pendente(pedido_id)';
  end if;
  if has_function_privilege('authenticated', 'public.criar_pagamento_pendente(uuid, public.provedor_pagamento, text, text, text)', 'EXECUTE') then
    raise exception 'T11: authenticated NAO pode executar criar_pagamento_pendente(pedido_id)';
  end if;
  if has_function_privilege('anon', 'public.confirmar_pagamento(uuid, text, text)', 'EXECUTE') then
    raise exception 'T11: anon NAO pode confirmar_pagamento';
  end if;
end $$;

-- T12) RLS / acesso direto e secdef_public
do $$
declare
  v_secdef integer;
begin
  if has_table_privilege('anon', 'public.pedidos', 'SELECT') then
    raise exception 'T12: anon nao pode ler pedidos diretamente';
  end if;
  if has_table_privilege('authenticated', 'public.pagamentos', 'SELECT') then
    raise exception 'T12: authenticated nao pode ler pagamentos diretamente';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.pedidos'::regclass) then
    raise exception 'T12: RLS desabilitada em pedidos';
  end if;

  select count(*) into v_secdef
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef = true

     -- [Ingressoudi] funcoes SECURITY DEFINER em public sao permitidas desde que

     -- nao sejam executaveis por anon e validem o perfil via helper privado.

     and (has_function_privilege('anon', p.oid, 'EXECUTE')

          or pg_get_functiondef(p.oid) !~ 'private\.(usuario_e_admin|usuario_pode_operar_portaria|usuario_e_super_admin)\(\)');
  if v_secdef <> 0 then
    raise exception 'T12: % funcao(oes) SECURITY DEFINER em public', v_secdef;
  end if;
end $$;

select 'checkout_publico_seguro: todos os testes passaram' as resultado;

rollback;
