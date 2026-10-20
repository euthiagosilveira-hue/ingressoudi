-- =============================================================================
-- Ingressoudi - Testes: reserva acompanha o Pix, Pix pago apos a reserva e
-- lote que nao encerra por reservas nao pagas (reativacao manual).
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
  v_admin uuid := gen_random_uuid();
  v_evento uuid := gen_random_uuid();
  v_lote uuid := gen_random_uuid();
  v_lote_cheio uuid := gen_random_uuid();
  v_ped_a uuid := gen_random_uuid();
  v_ped_b uuid := gen_random_uuid();
  v_ped_c uuid := gen_random_uuid();
  v_ped_d uuid := gen_random_uuid();
  v_pag_a uuid;
  v_pag_b uuid;
  v_pag_c uuid;
  v_res jsonb;
  v_ts timestamptz;
  v_status text;
  v_n integer;
begin
  insert into public.eventos (id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, vendas_status, publicacao_status)
  values (v_evento, 'Evento Reserva Pix', 'evento-rpix-' || replace(v_evento::text,'-',''), now() + interval '30 days',
          'Galeria', 'Rua 1', 1000, 1000, 'AGENDADO', 'ABERTAS', 'PUBLICADO');

  insert into public.lotes (id, evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_lote, v_evento, 'Lote 1', 1, 100, 30, 'MANUAL', 'ATIVO');

  insert into public.pedidos (id, evento_id, lote_id, codigo, comprador_nome, comprador_telefone, quantidade, tipo_preco, valor_unitario, valor_total, status, reserva_expira_em, checkout_token)
  values
    (v_ped_a, v_evento, v_lote, 'RP' || replace(v_ped_a::text,'-',''), 'A', '11999999991', 1, 'LOTE', 30, 30, 'RESERVADO', now() + interval '30 min', gen_random_uuid()),
    (v_ped_b, v_evento, v_lote, 'RP' || replace(v_ped_b::text,'-',''), 'B', '11999999992', 1, 'LOTE', 30, 30, 'RESERVADO', now() - interval '1 min', gen_random_uuid()),
    (v_ped_c, v_evento, v_lote, 'RP' || replace(v_ped_c::text,'-',''), 'C', '11999999993', 1, 'LOTE', 30, 30, 'EXPIRADO', now() - interval '5 min', gen_random_uuid());

  insert into public.pagamentos (pedido_id, provedor, valor, expira_em, status)
  values (v_ped_a, 'MERCADO_PAGO', 30, now() + interval '30 min', 'PENDENTE') returning id into v_pag_a;
  insert into public.pagamentos (pedido_id, provedor, valor, expira_em, status)
  values (v_ped_b, 'MERCADO_PAGO', 30, now() - interval '1 min', 'PENDENTE') returning id into v_pag_b;
  insert into public.pagamentos (pedido_id, provedor, valor, expira_em, status, cobranca_id)
  values (v_ped_c, 'MERCADO_PAGO', 30, now() - interval '5 min', 'EXPIRADO', 'MP-TARDIO') returning id into v_pag_c;

  insert into public.ingressos (pedido_id, evento_id, lote_id, codigo, participante_nome, valor_unitario, qr_token, status) values
    (v_ped_a, v_evento, v_lote, 'RPA' || substr(replace(gen_random_uuid()::text,'-',''),1,12), 'A', 30, gen_random_uuid()::text, 'RESERVADO'),
    (v_ped_c, v_evento, v_lote, 'RPC' || substr(replace(gen_random_uuid()::text,'-',''),1,12), 'C', 30, gen_random_uuid()::text, 'EXPIRADO');

  -- A) ACL: so o servidor (service_role) estende reservas
  if has_function_privilege('anon', 'public.estender_reserva_pix(uuid, timestamptz)', 'execute') then raise exception 'A: anon nao deveria executar'; end if;
  if has_function_privilege('authenticated', 'public.estender_reserva_pix(uuid, timestamptz)', 'execute') then raise exception 'A: authenticated nao deveria executar'; end if;
  if not has_function_privilege('service_role', 'public.estender_reserva_pix(uuid, timestamptz)', 'execute') then raise exception 'A: service_role deveria executar'; end if;

  -- B) estende reserva e pagamento ate o fim do Pix
  v_res := public.estender_reserva_pix(v_pag_a, now() + interval '31 min');
  if v_res->>'resultado' <> 'estendida' then raise exception 'B: esperado estendida (%)', v_res; end if;
  select reserva_expira_em into v_ts from public.pedidos where id = v_ped_a;
  if v_ts <> now() + interval '31 min' then raise exception 'B: pedido nao estendido (%)', v_ts; end if;
  select expira_em into v_ts from public.pagamentos where id = v_pag_a;
  if v_ts <> now() + interval '31 min' then raise exception 'B: pagamento nao estendido (%)', v_ts; end if;

  -- C) prazo menor que o atual: mantem
  v_res := public.estender_reserva_pix(v_pag_a, now() + interval '10 min');
  if v_res->>'resultado' <> 'mantida' then raise exception 'C: esperado mantida (%)', v_res; end if;
  select reserva_expira_em into v_ts from public.pedidos where id = v_ped_a;
  if v_ts <> now() + interval '31 min' then raise exception 'C: prazo nao deveria mudar'; end if;

  -- D) prazo exagerado: limitado a 90 minutos
  v_res := public.estender_reserva_pix(v_pag_a, now() + interval '5 hours');
  if v_res->>'resultado' <> 'estendida' then raise exception 'D: esperado estendida (%)', v_res; end if;
  select reserva_expira_em into v_ts from public.pedidos where id = v_ped_a;
  if v_ts <> now() + interval '90 min' then raise exception 'D: limite de 90 min nao aplicado (%)', v_ts; end if;

  -- E) reserva ja vencida nao e reaberta
  v_res := public.estender_reserva_pix(v_pag_b, now() + interval '30 min');
  if v_res->>'resultado' <> 'reserva_expirada' then raise exception 'E: esperado reserva_expirada (%)', v_res; end if;
  select reserva_expira_em into v_ts from public.pedidos where id = v_ped_b;
  if v_ts <> now() - interval '1 min' then raise exception 'E: reserva vencida foi alterada'; end if;

  -- F) pedido que nao esta mais reservado: nao se aplica
  v_res := public.estender_reserva_pix(v_pag_c, now() + interval '30 min');
  if v_res->>'resultado' <> 'nao_aplicavel' then raise exception 'F: esperado nao_aplicavel (%)', v_res; end if;

  -- G) confirmacao no prazo segue como antes
  v_res := private.confirmar_pagamento(v_pag_a, 'TX-A', null);
  if v_res->>'resultado' <> 'confirmado' then raise exception 'G: esperado confirmado (%)', v_res; end if;
  select status::text into v_status from public.ingressos where pedido_id = v_ped_a;
  if v_status <> 'VALIDO' then raise exception 'G: ingresso deveria estar VALIDO'; end if;

  -- H) Pix aprovado depois da reserva vencer: emite os ingressos e audita
  v_res := private.confirmar_pagamento(v_pag_c, 'TX-C', null);
  if v_res->>'resultado' <> 'confirmado_apos_reserva' then raise exception 'H: esperado confirmado_apos_reserva (%)', v_res; end if;
  if (v_res->>'ingressos_validados')::integer <> 1 then raise exception 'H: 1 ingresso deveria ser validado (%)', v_res; end if;
  select status::text into v_status from public.pedidos where id = v_ped_c;
  if v_status <> 'PAGO' then raise exception 'H: pedido deveria estar PAGO (%)', v_status; end if;
  select status::text into v_status from public.pagamentos where id = v_pag_c;
  if v_status <> 'APROVADO' then raise exception 'H: pagamento deveria estar APROVADO (%)', v_status; end if;
  select status::text into v_status from public.ingressos where pedido_id = v_ped_c;
  if v_status <> 'VALIDO' then raise exception 'H: ingresso deveria estar VALIDO (%)', v_status; end if;
  select count(*) into v_n from public.auditoria
   where acao = 'PAGAMENTO_CONFIRMADO_APOS_RESERVA' and entidade_id = v_ped_c
     and (dados_novos->>'acima_do_estoque')::boolean = false;
  if v_n <> 1 then raise exception 'H: auditoria ausente (%)', v_n; end if;

  -- I) idempotente
  v_res := private.confirmar_pagamento(v_pag_c, 'TX-C', null);
  if v_res->>'resultado' <> 'ja_confirmado' then raise exception 'I: esperado ja_confirmado (%)', v_res; end if;

  -- J) ultimo lote cheio de reservas nao pagas continua ATIVO
  update public.lotes set status = 'ENCERRADO', encerrado_em = now() where id = v_lote;
  insert into public.lotes (id, evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_lote_cheio, v_evento, 'Lote 2', 2, 2, 30, 'MANUAL', 'ATIVO');
  insert into public.pedidos (id, evento_id, lote_id, codigo, comprador_nome, comprador_telefone, quantidade, tipo_preco, valor_unitario, valor_total, status, reserva_expira_em, checkout_token)
  values (v_ped_d, v_evento, v_lote_cheio, 'RP' || replace(v_ped_d::text,'-',''), 'D', '11999999994', 2, 'LOTE', 30, 60, 'RESERVADO', now() + interval '30 min', gen_random_uuid());
  insert into public.ingressos (pedido_id, evento_id, lote_id, codigo, participante_nome, valor_unitario, qr_token, status)
  select v_ped_d, v_evento, v_lote_cheio, 'RPD' || substr(replace(gen_random_uuid()::text,'-',''),1,12) || t.pos, 'D' || t.pos, 30, gen_random_uuid()::text, 'RESERVADO'
    from generate_series(1, 2) as t(pos);

  v_res := private.processar_virada_lote_esgotamento(v_evento);
  if v_res->>'resultado' <> 'ESGOTADO_TEMPORARIO' then raise exception 'J: esperado ESGOTADO_TEMPORARIO (%)', v_res; end if;
  select status::text into v_status from public.lotes where id = v_lote_cheio;
  if v_status <> 'ATIVO' then raise exception 'J: lote deveria seguir ATIVO (%)', v_status; end if;

  -- K) quando os pagos preenchem o lote, ele encerra
  update public.ingressos set status = 'VALIDO' where pedido_id = v_ped_d;
  v_res := private.processar_virada_lote_esgotamento(v_evento);
  if v_res->>'resultado' <> 'ESGOTADO_SEM_PROXIMO_LOTE' then raise exception 'K: esperado ESGOTADO_SEM_PROXIMO_LOTE (%)', v_res; end if;
  select status::text into v_status from public.lotes where id = v_lote_cheio;
  if v_status <> 'ENCERRADO' then raise exception 'K: lote deveria estar ENCERRADO (%)', v_status; end if;

  -- L) admin reativa lote encerrado que ainda tem ingressos
  insert into auth.users (id) values (v_admin);
  insert into public.usuarios (id, nome, email, perfil, ativo)
  values (v_admin, 'Admin RPix', 'adminrpix_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  v_res := public.ativar_lote_manual(v_lote);
  if v_res->>'resultado' <> 'ATIVADO' then raise exception 'L: esperado ATIVADO (%)', v_res; end if;
  select status::text into v_status from public.lotes where id = v_lote;
  if v_status <> 'ATIVO' then raise exception 'L: lote 1 deveria estar ATIVO (%)', v_status; end if;
  select count(*) into v_n from public.auditoria where acao = 'LOTE_REATIVADO_MANUALMENTE' and entidade_id = v_lote;
  if v_n <> 1 then raise exception 'L: auditoria de reativacao ausente (%)', v_n; end if;

  -- M) lote encerrado sem ingressos disponiveis nao reabre
  begin
    perform public.ativar_lote_manual(v_lote_cheio);
    raise exception 'M: deveria recusar lote sem ingressos';
  exception when others then
    if position('sem ingressos disponiveis' in sqlerrm) = 0 then raise exception 'M: %', sqlerrm; end if;
  end;
  select status::text into v_status from public.lotes where id = v_lote_cheio;
  if v_status <> 'ENCERRADO' then raise exception 'M: lote cheio deveria seguir ENCERRADO (%)', v_status; end if;
end $$;

select 'reserva_pix_e_lotes: todos os testes passaram' as resultado;

rollback;
