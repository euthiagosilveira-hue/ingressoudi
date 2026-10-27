-- =============================================================================
-- Ingressoudi - Testes: localizar_pix_portaria (portaria confere o Pix de
-- ingresso expirado). Cenario do GZ1: comprador pagou, o aviso do Mercado Pago
-- nao confirmou, a reserva expirou e a portaria barrou o ingresso.
-- Executar como owner. begin/rollback (nao persiste dados).
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
  v_op uuid := gen_random_uuid();
  v_evento uuid;
  v_r jsonb;
  v_r_pago jsonb;
  v_pag jsonb;
  v_pag_pago jsonb;
  v_pedido uuid;
  v_ingresso uuid;
  v_ingresso_pago uuid;
  v_token text;
  v_res jsonb;
  v_pix jsonb;
begin
  insert into auth.users (id) values (v_op);
  insert into public.usuarios (id, nome, email, perfil, ativo)
  values (v_op, 'Operador Pix', 'op_' || replace(v_op::text,'-','') || '@test.local', 'PORTARIA', true);

  insert into public.eventos (
    nome, slug, inicio_em, local, endereco,
    capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status
  ) values (
    'Teste Pix Portaria', 'teste-pix-portaria-' || replace(gen_random_uuid()::text,'-',''),
    now() + interval '2 days', 'Local', 'End',
    200, 100, 'AGENDADO', 'PUBLICADO', 'ABERTAS'
  ) returning id into v_evento;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_evento, 'Lote', 1, 100, 40, 'MANUAL', 'ATIVO');

  -- Pix gerado e nunca confirmado pelo webhook
  v_r := public.criar_reserva(v_evento, 'Comprador Pix', '34999999911', null, array['Pix 1']);
  v_pedido := (v_r->>'pedido_id')::uuid;
  v_pag := public.criar_pagamento_pendente_por_token((v_r->>'checkout_token')::uuid, 'MERCADO_PAGO');
  update public.pagamentos set cobranca_id = 'MP-123' where id = (v_pag->>'pagamento_id')::uuid;
  select id, qr_token into v_ingresso, v_token from public.ingressos where pedido_id = v_pedido limit 1;

  -- pedido ja pago (nada a conferir)
  v_r_pago := public.criar_reserva(v_evento, 'Comprador Pago', '34999999912', null, array['Pago 1']);
  v_pag_pago := public.criar_pagamento_pendente_por_token((v_r_pago->>'checkout_token')::uuid, 'MERCADO_PAGO');
  update public.pagamentos set cobranca_id = 'MP-456' where id = (v_pag_pago->>'pagamento_id')::uuid;
  perform public.confirmar_pagamento((v_pag_pago->>'pagamento_id')::uuid, 'tx-pago');
  select id into v_ingresso_pago from public.ingressos where pedido_id = (v_r_pago->>'pedido_id')::uuid limit 1;

  -- a reserva vence e a limpeza diaria expira o pedido
  update public.pedidos set reserva_expira_em = now() - interval '1 minute' where id = v_pedido;
  update public.pagamentos set expira_em = now() - interval '1 minute' where id = (v_pag->>'pagamento_id')::uuid;
  perform private.processar_reservas_expiradas(null);
  if (select status from public.ingressos where id = v_ingresso) <> 'EXPIRADO' then
    raise exception 'setup: ingresso deveria estar EXPIRADO';
  end if;

  update public.eventos set status = 'EM_ANDAMENTO', inicio_em = now() - interval '1 hour' where id = v_evento;

  -- A) sem operador autenticado: negado
  begin
    perform public.localizar_pix_portaria(v_evento, v_ingresso);
    raise exception 'A: deveria negar sem operador autenticado';
  exception
    when others then
      if position('permiss' in lower(sqlerrm)) = 0 then
        raise exception 'A: erro inesperado: %', sqlerrm;
      end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_op::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_op::text, true);

  -- B) portaria barra o ingresso expirado
  v_res := public.registrar_entrada_qr(v_evento, v_token);
  if (v_res->>'resultado') <> 'INVALIDO' or (v_res->>'mensagem') <> 'Ingresso expirado' then
    raise exception 'B: esperado INVALIDO/Ingresso expirado, obtido %', v_res;
  end if;

  -- C) localiza o Pix do ingresso expirado
  v_pix := public.localizar_pix_portaria(v_evento, v_ingresso);
  if v_pix is null or (v_pix->>'pagamento_id')::uuid <> (v_pag->>'pagamento_id')::uuid
     or (v_pix->>'cobranca_id') <> 'MP-123' then
    raise exception 'C: Pix nao localizado: %', v_pix;
  end if;

  -- D) ingresso pago ou de outro evento: nada a conferir
  if public.localizar_pix_portaria(v_evento, v_ingresso_pago) is not null then
    raise exception 'D: ingresso pago nao deveria ter Pix a conferir';
  end if;
  if public.localizar_pix_portaria(gen_random_uuid(), v_ingresso) is not null then
    raise exception 'D: outro evento nao deveria localizar o Pix';
  end if;

  -- E) Mercado Pago diz que esta pago: confirma e a entrada e liberada
  perform private.confirmar_pagamento((v_pix->>'pagamento_id')::uuid, 'tx-tardio', null);
  v_res := public.registrar_entrada_qr(v_evento, v_token);
  if (v_res->>'resultado') <> 'LIBERADO' then
    raise exception 'E: esperado LIBERADO apos confirmar, obtido %', v_res;
  end if;
  if not exists (select 1 from public.auditoria where acao = 'PAGAMENTO_CONFIRMADO_APOS_RESERVA' and entidade_id = v_pedido) then
    raise exception 'E: confirmacao tardia deveria ficar na auditoria';
  end if;
  if public.localizar_pix_portaria(v_evento, v_ingresso) is not null then
    raise exception 'E: depois de pago nao ha Pix a conferir';
  end if;
end $$;

select 'conferir_pix_portaria: todos os testes passaram' as resultado;

rollback;
