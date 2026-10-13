-- =============================================================================
-- GZ1 Ingresso - Testes: entradas administrativas
-- Arquivo: supabase/tests/entradas_admin.test.sql
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
  if has_function_privilege('anon', 'public.listar_entradas_admin(uuid, text, timestamptz, timestamptz, public.metodo_validacao, text)', 'EXECUTE') then
    raise exception 'A: anon nao pode executar listar_entradas_admin';
  end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_portaria uuid := gen_random_uuid();
  v_e uuid; v_e2 uuid;
  v_r jsonb; v_pag jsonb;
  v_ped uuid; v_pedcod text;
  v_i1 uuid; v_i2 uuid; v_i3 uuid;
  v_lista jsonb; v_n integer;
begin
  insert into auth.users (id) values (v_admin), (v_portaria);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Operador Admin E', 'openadmine_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Operador Port E', 'openporte_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true);

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Ent 1','ent1-'||replace(gen_random_uuid()::text,'-',''), now()+interval '3 days','L','E',100,50,'AGENDADO','PUBLICADO','ABERTAS') returning id into v_e;
  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Ent 2','ent2-'||replace(gen_random_uuid()::text,'-',''), now()+interval '3 days','L','E',100,50,'AGENDADO','PUBLICADO','ABERTAS') returning id into v_e2;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status) values (v_e,'Lote E1',1,100,40,'MANUAL','ATIVO');
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status) values (v_e2,'Lote E2',1,100,40,'MANUAL','ATIVO');

  v_r := public.criar_reserva(v_e,'Comprador Ent','11999990040','ent@test.local',array['Entrada Alfa','Entrada Beta','Entrada Gama']);
  v_ped := (v_r->>'pedido_id')::uuid; v_pedcod := v_r->>'codigo_pedido';
  v_pag := public.criar_pagamento_pendente_por_token((v_r->>'checkout_token')::uuid,'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid,'tx-ent-1');
  select id into v_i1 from public.ingressos where pedido_id=v_ped order by codigo limit 1;
  select id into v_i2 from public.ingressos where pedido_id=v_ped order by codigo offset 1 limit 1;
  select id into v_i3 from public.ingressos where pedido_id=v_ped order by codigo offset 2 limit 1;

  -- tres entradas: QR (admin), NOME (portaria), e uma anulada
  insert into public.entradas (ingresso_id, evento_id, usuario_id, metodo_validacao, entrada_em)
  values (v_i1, v_e, v_admin, 'QR_CODE', now() - interval '10 minutes');
  insert into public.entradas (ingresso_id, evento_id, usuario_id, metodo_validacao, entrada_em)
  values (v_i2, v_e, v_portaria, 'NOME', now() - interval '5 minutes');
  insert into public.entradas (ingresso_id, evento_id, usuario_id, metodo_validacao, entrada_em, anulada_em, anulada_por_usuario_id, motivo_anulacao)
  values (v_i3, v_e, v_admin, 'QR_CODE', now() - interval '1 minute', now(), v_admin, 'teste');

  -- B) PORTARIA negado
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  begin
    perform public.listar_entradas_admin();
    raise exception 'B: PORTARIA nao deveria listar entradas admin';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'B: inesperado: %', sqlerrm; end if;
  end;

  -- C) ADMIN permitido
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_lista := public.listar_entradas_admin(p_evento_id => v_e);
  if jsonb_array_length(v_lista) <> 3 then raise exception 'C/J: esperado 3 entradas, obtido %', jsonb_array_length(v_lista); end if;

  -- D) filtro evento (evento2 sem entradas)
  v_lista := public.listar_entradas_admin(p_evento_id => v_e2);
  if jsonb_array_length(v_lista) <> 0 then raise exception 'D: evento2 deveria ter 0'; end if;

  -- E) busca codigo do ingresso
  v_lista := public.listar_entradas_admin(p_evento_id => v_e, p_busca => (select codigo from public.ingressos where id=v_i1));
  if jsonb_array_length(v_lista) <> 1 or (v_lista->0->>'ingresso_id')::uuid <> v_i1 then raise exception 'E: busca por ingresso falhou'; end if;

  -- F) busca participante
  v_lista := public.listar_entradas_admin(p_evento_id => v_e, p_busca => 'Beta');
  if jsonb_array_length(v_lista) <> 1 or (v_lista->0->>'ingresso_id')::uuid <> v_i2 then raise exception 'F: busca por participante falhou'; end if;

  -- G) busca codigo do pedido
  v_lista := public.listar_entradas_admin(p_busca => v_pedcod);
  if jsonb_array_length(v_lista) <> 3 then raise exception 'G: busca por pedido deveria achar 3'; end if;

  -- H) periodo (de = agora - 6 min => exclui a de 10 min)
  v_lista := public.listar_entradas_admin(p_evento_id => v_e, p_de => now() - interval '6 minutes');
  if jsonb_array_length(v_lista) <> 2 then raise exception 'H: periodo deveria retornar 2'; end if;

  -- I) inexistente
  v_lista := public.listar_entradas_admin(p_busca => 'zzz-nao-existe-zzz');
  if jsonb_array_length(v_lista) <> 0 then raise exception 'I: inexistente deveria ser vazio'; end if;

  -- K) operador correto
  v_lista := public.listar_entradas_admin(p_evento_id => v_e, p_busca => 'Beta');
  if (v_lista->0->>'operador_nome') <> 'Operador Port E' then raise exception 'K: operador incorreto'; end if;

  -- L) metodo correto
  if (v_lista->0->>'metodo') <> 'NOME' then raise exception 'L: metodo incorreto'; end if;

  -- M/N) sem tokens
  if (v_lista->0 ? 'qr_token') or (v_lista->0 ? 'checkout_token') then raise exception 'M/N: tokens expostos'; end if;

  -- O) ordenacao entrada_em DESC
  v_lista := public.listar_entradas_admin(p_evento_id => v_e);
  if (v_lista->0->>'entrada_em') < (v_lista->1->>'entrada_em') then raise exception 'O: ordenacao deveria ser DESC'; end if;

  -- P) situacao ANULADA
  v_lista := public.listar_entradas_admin(p_evento_id => v_e, p_situacao => 'ANULADA');
  if jsonb_array_length(v_lista) <> 1 or (v_lista->0->>'ingresso_id')::uuid <> v_i3 then
    raise exception 'P: filtro ANULADA incorreto';
  end if;
  if (v_lista->0->>'anulada_em') is null then raise exception 'P: anulada_em ausente'; end if;
end $$;

select 'entradas_admin: todos os testes passaram' as resultado;

rollback;
