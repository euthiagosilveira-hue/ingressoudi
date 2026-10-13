-- =============================================================================
-- GZ1 Ingresso - Testes: recuperacao de ingressos (codigo + telefone)
-- Arquivo: supabase/tests/recuperacao_ingressos.test.sql
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
declare
  v_e uuid;
  v_rA jsonb; v_rB jsonb; v_rC jsonb; v_rD jsonb;
  v_rF jsonb; v_rG jsonb; v_rH jsonb;
  v_pedA uuid; v_pag jsonb;
  v_codA text; v_telA text;
  v_codD text; v_telD text;
  v_pedD uuid; v_rD2 jsonb;
  v_pedR uuid; v_pedE uuid; v_pedC uuid;
  v_tokenA text;
  v_res jsonb; v_null jsonb;
  v_rand text;
begin
  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Rec','rec-'||replace(gen_random_uuid()::text,'-',''), now()+interval '3 days','L','E',100,50,'AGENDADO','PUBLICADO','ABERTAS')
  returning id into v_e;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_e,'Lote R',1,100,40,'MANUAL','ATIVO');

  -- Pedido PAGO (A) — telefone em digitos
  select public.criar_reserva(v_e,'Comprador Rec','11999990020','rec@test.local',array['Rec A']) as r into v_rA;
  v_pedA := (v_rA->>'pedido_id')::uuid; v_codA := v_rA->>'codigo_pedido'; v_telA := '11999990020';
  v_pag := public.criar_pagamento_pendente_por_token((v_rA->>'checkout_token')::uuid,'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid,'tx-rec-A');

  -- D) Pedido PAGO com telefone formatado
  select public.criar_reserva(v_e,'Comprador Rec D','(11) 99999-0021','recd@test.local',array['Rec D']) as r into v_rD;
  v_pedD := (v_rD->>'pedido_id')::uuid; v_codD := v_rD->>'codigo_pedido'; v_telD := '11999990021';
  v_pag := public.criar_pagamento_pendente_por_token((v_rD->>'checkout_token')::uuid,'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid,'tx-rec-D');

  -- F/G/H pedidos RESERVADO/EXPIRADO/CANCELADO
  select (public.criar_reserva(v_e,'Comprador R','11999990022',null,array['R'])->>'pedido_id')::uuid into v_pedR;
  select (public.criar_reserva(v_e,'Comprador E','11999990023',null,array['E'])->>'pedido_id')::uuid into v_pedE;
  select (public.criar_reserva(v_e,'Comprador C','11999990024',null,array['C'])->>'pedido_id')::uuid into v_pedC;
  update public.pedidos set status='EXPIRADO' where id=v_pedE;
  update public.pedidos set status='CANCELADO' where id=v_pedC;

  -- A) sucesso
  v_rA := public.recuperar_ingressos(v_codA, v_telA);
  if (v_rA->>'ok')::boolean is not true or (v_rA->>'token') is null then
    raise exception 'A: deveria recuperar';
  end if;
  v_tokenA := v_rA->>'token';
  if (v_rA ? 'checkout_token') or (v_rA ? 'qr_token') then
    raise exception 'L/M: recuperacao nao pode expor tokens';
  end if;

  -- B) codigo correto + telefone errado => generico
  v_rB := public.recuperar_ingressos(v_codA, '11999990099');
  if (v_rB->>'ok')::boolean is not false then raise exception 'B: deveria falhar'; end if;

  -- C) codigo inexistente => generico
  v_rC := public.recuperar_ingressos('GZ000000', v_telA);
  if (v_rC->>'ok')::boolean is not false then raise exception 'C: deveria falhar'; end if;

  -- D) telefone com mascara diferente => sucesso
  v_rD2 := public.recuperar_ingressos(v_codD, '11999990021');
  if (v_rD2->>'ok')::boolean is not true then raise exception 'D: mascara deveria casar'; end if;

  -- E) PAGO/APROVADO permitido (ja coberto em A)

  -- F) RESERVADO => negado
  v_rF := public.recuperar_ingressos((select codigo from public.pedidos where id=v_pedR),'11999990022');
  if (v_rF->>'ok')::boolean is not false then raise exception 'F: RESERVADO deveria ser negado'; end if;

  -- G) EXPIRADO => negado
  v_rG := public.recuperar_ingressos((select codigo from public.pedidos where id=v_pedE),'11999990023');
  if (v_rG->>'ok')::boolean is not false then raise exception 'G: EXPIRADO deveria ser negado'; end if;

  -- H) CANCELADO => negado
  v_rH := public.recuperar_ingressos((select codigo from public.pedidos where id=v_pedC),'11999990024');
  if (v_rH->>'ok')::boolean is not false then raise exception 'H: CANCELADO deveria ser negado'; end if;

  -- I) token valido => acesso aos ingressos
  v_res := public.obter_ingressos_recuperacao(v_tokenA);
  if v_res is null then raise exception 'I: token valido deveria retornar ingressos'; end if;
  if (v_res->>'codigo_pedido') <> v_codA then raise exception 'I: pedido incorreto'; end if;
  if jsonb_array_length(v_res->'ingressos') < 1 then raise exception 'I: sem ingressos'; end if;

  -- J) token expirado => negado
  insert into public.recuperacoes_ingressos (pedido_id, token_hash, expira_em)
  values (v_pedA, md5('token-expirado-teste'), now() - interval '1 minute');
  v_null := public.obter_ingressos_recuperacao('token-expirado-teste');
  if v_null is not null then raise exception 'J: token expirado deveria ser negado'; end if;

  -- K) token invalido => negado
  v_rand := replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');
  if public.obter_ingressos_recuperacao(v_rand) is not null then
    raise exception 'K: token invalido deveria ser negado';
  end if;
end $$;

select 'recuperacao_ingressos: todos os testes passaram' as resultado;

rollback;
