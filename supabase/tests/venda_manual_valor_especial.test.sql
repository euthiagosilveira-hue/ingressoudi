-- =============================================================================
-- GZ1 Ingresso - Testes: venda manual com valor especial (AVULSO)
-- Arquivo: supabase/tests/venda_manual_valor_especial.test.sql
-- Executar como owner. begin/rollback.
--
-- Cobre:
--   A telefone null permitido
--   B telefone vazio normalizado para null
--   C checkout publico continua exigindo telefone
--   D venda LOTE funciona
--   E tipo LOTE exige lote
--   F preco LOTE vem do banco
--   G AVULSO funciona sem lote
--   H AVULSO rejeita lote preenchido
--   I AVULSO exige valor
--   J valor invalido (<= 0) rejeitado
--   K valor_total calculado corretamente
--   L pedido AVULSO nasce PAGO
--   M pagamento DINHEIRO/APROVADO
--   N ingresso sem lote nasce VALIDO
--   O disponibilidade global respeitada
--   P overselling global rejeitado
--   Q financeiro contabiliza
--   R dashboard contabiliza
--   S auditoria correta (tipo_preco e lote_id)
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
  v_admin uuid := gen_random_uuid();
  v_portaria uuid := gen_random_uuid();

  v_e_lote uuid; v_l_lote uuid;          -- evento com lote ATIVO (preco 40)
  v_e_avulso uuid;                        -- evento SEM lote ativo
  v_e_full uuid;                          -- evento com estoque global curto
  v_e_checkout uuid; v_l_checkout uuid;   -- evento para testar checkout publico

  v_res jsonb;
  v_ped uuid;
  v_pag uuid;
  v_falhou boolean;
  v_msg text;
  v_n integer;
  v_disp_antes integer;
  v_disp_depois integer;
  v_num numeric;
  v_tipo text;
  v_lote_id uuid;
  v_prov text;
  v_status text;
  v_base numeric;
  v_apos numeric;
  v_fin jsonb;
begin
  -- -------------------------------------------------------------------------
  -- Fixtures
  -- -------------------------------------------------------------------------
  insert into auth.users (id) values (v_admin), (v_portaria);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Especial', 'adminesp_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Port Especial', 'portesp_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true);

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Lote','vlote-'||replace(gen_random_uuid()::text,'-',''), now()+interval '2 days','L','E',100,10,'AGENDADO','PUBLICADO','ABERTAS')
  returning id into v_e_lote;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_e_lote,'Lote Especial',1,5,40.00,'MANUAL','ATIVO') returning id into v_l_lote;

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Avulso','vavulso-'||replace(gen_random_uuid()::text,'-',''), now()+interval '2 days','L','E',100,10,'AGENDADO','PUBLICADO','ABERTAS')
  returning id into v_e_avulso;

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Curto','vcurto-'||replace(gen_random_uuid()::text,'-',''), now()+interval '2 days','L','E',100,2,'AGENDADO','PUBLICADO','ABERTAS')
  returning id into v_e_full;

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Checkout','vcheckout-'||replace(gen_random_uuid()::text,'-',''), now()+interval '2 days','L','E',100,10,'AGENDADO','PUBLICADO','ABERTAS')
  returning id into v_e_checkout;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_e_checkout,'Lote Checkout',1,10,20.00,'MANUAL','ATIVO') returning id into v_l_checkout;

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  -- -------------------------------------------------------------------------
  -- A) telefone null permitido (modo LOTE)
  -- -------------------------------------------------------------------------
  v_res := public.criar_venda_manual_admin(v_e_lote, v_l_lote, 'Sem Telefone', null, array['A']);
  v_ped := (v_res->>'pedido_id')::uuid;
  if (select p.comprador_telefone from public.pedidos p where p.id = v_ped) is not null then
    raise exception 'A: comprador_telefone deveria ser null';
  end if;

  -- -------------------------------------------------------------------------
  -- B) telefone vazio normalizado para null
  -- -------------------------------------------------------------------------
  v_res := public.criar_venda_manual_admin(v_e_lote, v_l_lote, 'Telefone Vazio', '   ', array['B']);
  v_ped := (v_res->>'pedido_id')::uuid;
  if (select p.comprador_telefone from public.pedidos p where p.id = v_ped) is not null then
    raise exception 'B: telefone vazio deveria ser normalizado para null';
  end if;

  -- -------------------------------------------------------------------------
  -- C) checkout publico continua exigindo telefone
  -- -------------------------------------------------------------------------
  v_falhou := false; v_msg := null;
  begin
    perform public.criar_reserva(v_e_checkout, 'Pub', '', null, array['P']);
  exception when others then v_falhou := true; v_msg := sqlerrm; end;
  if not v_falhou then raise exception 'C: checkout publico deveria exigir telefone'; end if;
  if position('telefone' in lower(v_msg)) = 0 then
    raise exception 'C: erro inesperado no checkout: %', v_msg;
  end if;

  -- -------------------------------------------------------------------------
  -- D/F) venda LOTE funciona e preco vem do banco
  -- -------------------------------------------------------------------------
  v_res := public.criar_venda_manual_admin(v_e_lote, v_l_lote, 'Comprador Lote', '11999990000', array['L1','L2'], null, 'LOTE', 999.99);
  v_ped := (v_res->>'pedido_id')::uuid;
  v_pag := (v_res->>'pagamento_id')::uuid;
  select p.tipo_preco::text, p.lote_id, p.valor_unitario into v_tipo, v_lote_id, v_num
    from public.pedidos p where p.id = v_ped;
  if v_tipo <> 'LOTE' then raise exception 'D: tipo_preco deveria ser LOTE (obtido %)', v_tipo; end if;
  if v_lote_id <> v_l_lote then raise exception 'D: lote_id incorreto'; end if;
  if v_num <> 40.00 then raise exception 'F: preco deveria vir do lote (40.00, obtido %)', v_num; end if;

  -- -------------------------------------------------------------------------
  -- E) tipo LOTE exige lote
  -- -------------------------------------------------------------------------
  v_falhou := false;
  begin
    perform public.criar_venda_manual_admin(v_e_lote, null, 'X', '11999990000', array['X'], null, 'LOTE', null);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'E: LOTE sem lote deveria falhar'; end if;

  -- -------------------------------------------------------------------------
  -- G/K/L/M/N/O) venda AVULSO funciona sem lote
  -- -------------------------------------------------------------------------
  select private.calcular_disponibilidade_evento(v_e_avulso) into v_disp_antes;

  v_res := public.criar_venda_manual_admin(v_e_avulso, null, 'Comprador Especial', null, array['E1','E2','E3'], null, 'AVULSO', 25.00);
  v_ped := (v_res->>'pedido_id')::uuid;
  v_pag := (v_res->>'pagamento_id')::uuid;

  if (v_res->>'tipo_preco') <> 'AVULSO' then raise exception 'G: tipo_preco deveria ser AVULSO'; end if;
  if v_res ? 'lote_id' and (v_res->>'lote_id') is not null then
    raise exception 'G: lote_id deveria ser null no AVULSO';
  end if;

  select p.status::text, p.tipo_preco::text, p.lote_id, p.valor_unitario, p.valor_total
    into v_status, v_tipo, v_lote_id, v_num, v_apos
    from public.pedidos p where p.id = v_ped;
  if v_status <> 'PAGO' then raise exception 'L: pedido AVULSO deveria ser PAGO (obtido %)', v_status; end if;
  if v_tipo <> 'AVULSO' then raise exception 'L: tipo_preco deveria ser AVULSO'; end if;
  if v_lote_id is not null then raise exception 'L: lote_id deveria ser null'; end if;
  if v_num <> 25.00 then raise exception 'K: valor_unitario deveria ser 25.00 (obtido %)', v_num; end if;
  if v_apos <> 75.00 then raise exception 'K: valor_total deveria ser 75.00 (obtido %)', v_apos; end if;

  if not exists (
    select 1 from public.pedidos p
     where p.id = v_ped
       and p.motivo_valor_avulso is not null
       and p.autorizado_por_usuario_id = v_admin
  ) then
    raise exception 'G: pedido avulso deveria ter motivo e autorizador';
  end if;

  select pg.provedor::text, pg.status::text into v_prov, v_status
    from public.pagamentos pg where pg.id = v_pag;
  if v_prov <> 'DINHEIRO' then raise exception 'M: pagamento deveria ser DINHEIRO (obtido %)', v_prov; end if;
  if v_status <> 'APROVADO' then raise exception 'M: pagamento deveria ser APROVADO'; end if;

  select count(*) into v_n
    from public.ingressos i
   where i.pedido_id = v_ped and i.status = 'VALIDO' and i.lote_id is null and i.valor_unitario = 25.00;
  if v_n <> 3 then raise exception 'N: deveria haver 3 ingressos VALIDO sem lote com valor 25 (obtido %)', v_n; end if;

  select private.calcular_disponibilidade_evento(v_e_avulso) into v_disp_depois;
  if v_disp_antes <> 10 or v_disp_depois <> 7 then
    raise exception 'O: disponibilidade global deveria ir de 10 para 7 (antes=%, depois=%)', v_disp_antes, v_disp_depois;
  end if;

  -- -------------------------------------------------------------------------
  -- H) AVULSO rejeita lote preenchido
  -- -------------------------------------------------------------------------
  v_falhou := false;
  begin
    perform public.criar_venda_manual_admin(v_e_lote, v_l_lote, 'X', null, array['X'], null, 'AVULSO', 10.00);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'H: AVULSO com lote deveria falhar'; end if;

  -- -------------------------------------------------------------------------
  -- I/J) AVULSO exige valor > 0
  -- -------------------------------------------------------------------------
  v_falhou := false;
  begin
    perform public.criar_venda_manual_admin(v_e_avulso, null, 'X', null, array['X'], null, 'AVULSO', null);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'I: AVULSO sem valor deveria falhar'; end if;

  v_falhou := false;
  begin
    perform public.criar_venda_manual_admin(v_e_avulso, null, 'X', null, array['X'], null, 'AVULSO', 0);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'J: AVULSO com valor zero deveria falhar'; end if;

  -- -------------------------------------------------------------------------
  -- P) overselling global rejeitado
  -- -------------------------------------------------------------------------
  v_falhou := false;
  begin
    perform public.criar_venda_manual_admin(
      v_e_full, null, 'X', null,
      array(select 'P' || g from generate_series(1, 3) g), null, 'AVULSO', 10.00
    );
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'P: venda AVULSO acima da capacidade global deveria falhar'; end if;

  -- -------------------------------------------------------------------------
  -- S) auditoria correta para AVULSO
  -- -------------------------------------------------------------------------
  select count(*) into v_n
    from public.auditoria a
   where a.acao = 'VENDA_MANUAL_CRIADA'
     and a.entidade = 'pedidos'
     and a.entidade_id = v_ped
     and a.usuario_id = v_admin
     and (a.dados_novos->>'tipo_preco') = 'AVULSO'
     and (a.dados_novos->>'lote_id') is null
     and (a.dados_novos->>'forma') = 'DINHEIRO';
  if v_n <> 1 then raise exception 'S: auditoria AVULSO ausente/incorreta'; end if;

  -- -------------------------------------------------------------------------
  -- Q/R) financeiro e dashboard contabilizam o valor especial
  -- -------------------------------------------------------------------------
  select coalesce(sum(pg.valor), 0) into v_base
    from public.pagamentos pg where pg.status = 'APROVADO';

  v_res := public.criar_venda_manual_admin(v_e_avulso, null, 'Comprador Q', null, array['Q1'], null, 'AVULSO', 30.00);

  v_fin := public.obter_financeiro_admin(p_evento_id => v_e_avulso);
  if (v_fin->'resumo'->>'valorAprovado')::numeric <> 105.00 then
    raise exception 'Q: financeiro do evento deveria somar 105.00 (75 + 30), obtido %', v_fin->'resumo'->>'valorAprovado';
  end if;

  select coalesce(sum(pg.valor), 0) into v_apos
    from public.pagamentos pg where pg.status = 'APROVADO';
  if v_apos <> v_base + 30.00 then
    raise exception 'R: faturamento total deveria crescer 30 (antes=%, depois=%)', v_base, v_apos;
  end if;

  if (public.obter_dashboard_admin()->'metricas'->>'faturamento')::numeric <> v_apos then
    raise exception 'R: dashboard deveria refletir o faturamento total';
  end if;
end $$;

select 'venda_manual_valor_especial: todos os testes passaram' as resultado;

rollback;
