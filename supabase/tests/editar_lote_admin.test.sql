-- =============================================================================
-- GZ1 Ingresso - Testes: editar_lote_admin
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

-- A) anon sem EXECUTE ---------------------------------------------------------
do $$
begin
  if has_function_privilege('anon',
       'public.atualizar_lote_admin(uuid,text,integer,numeric,public.tipo_ativacao_lote,timestamptz)'::regprocedure,
       'EXECUTE') then
    raise exception 'A: anon nao pode executar atualizar_lote_admin';
  end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_portaria uuid := gen_random_uuid();
  v_evento uuid := gen_random_uuid();
  v_lote uuid := gen_random_uuid();
  v_lote_encerrado uuid := gen_random_uuid();
  v_pedido uuid := gen_random_uuid();
  v_pedido2 uuid := gen_random_uuid();
  v_res jsonb;
  v_num numeric;
  v_int integer;
  v_txt text;
  v_ts timestamptz;
  v_aud integer;
begin
  insert into auth.users (id) values (v_admin), (v_portaria);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Lote', 'adminlote_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Port Lote', 'portlote_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true);

  insert into public.eventos (id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, vendas_status, publicacao_status)
  values (v_evento, 'Evento Lote', 'evento-lote-' || replace(v_evento::text,'-',''), now() + interval '30 days',
          'Galeria', 'Rua 1', 1000, 1000, 'AGENDADO', 'ABERTAS', 'PUBLICADO');

  insert into public.lotes (id, evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_lote, v_evento, 'Lote 1', 1, 50, 30, 'MANUAL', 'INATIVO'),
         (v_lote_encerrado, v_evento, 'Lote Enc', 2, 10, 30, 'MANUAL', 'ENCERRADO');

  -- 12 ingressos vendidos a R$30 no lote 1 (comprometido = 12; max 10 por pedido)
  insert into public.pedidos (id, evento_id, lote_id, codigo, comprador_nome, comprador_telefone, quantidade, tipo_preco, valor_unitario, valor_total, status, reserva_expira_em)
  values (v_pedido, v_evento, v_lote, 'EL' || substr(replace(v_pedido::text,'-',''),1,10), 'Comprador', '11999999999', 10, 'LOTE', 30, 300, 'PAGO', now() + interval '1 day'),
         (v_pedido2, v_evento, v_lote, 'EL' || substr(replace(v_pedido2::text,'-',''),1,10), 'Comprador 2', '11999999998', 2, 'LOTE', 30, 60, 'PAGO', now() + interval '1 day');
  insert into public.ingressos (pedido_id, evento_id, lote_id, codigo, participante_nome, valor_unitario, qr_token, status)
  select v_pedido, v_evento, v_lote, 'EL' || substr(replace(gen_random_uuid()::text,'-',''),1,12) || t.pos, 'P' || t.pos, 30, gen_random_uuid()::text, 'VALIDO'
    from generate_series(1, 10) as t(pos);
  insert into public.ingressos (pedido_id, evento_id, lote_id, codigo, participante_nome, valor_unitario, qr_token, status)
  select v_pedido2, v_evento, v_lote, 'EL2' || substr(replace(gen_random_uuid()::text,'-',''),1,11) || t.pos, 'Q' || t.pos, 30, gen_random_uuid()::text, 'VALIDO'
    from generate_series(1, 2) as t(pos);

  -- B) PORTARIA negado
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  begin
    perform public.atualizar_lote_admin(v_lote, 'X', 50, 30, 'MANUAL', null);
    raise exception 'B: PORTARIA nao deveria editar';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'B: %', sqlerrm; end if;
  end;

  -- ADMIN
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  -- I) quantidade abaixo do comprometido
  begin
    perform public.atualizar_lote_admin(v_lote, 'Lote 1', 10, 40, 'MANUAL', null);
    raise exception 'I: quantidade 10 < comprometido deveria falhar';
  exception when others then
    if position('menor que os ingressos' in lower(sqlerrm)) = 0 then raise exception 'I: %', sqlerrm; end if;
  end;

  -- C) atualiza INATIVO (quantidade acima do comprometido) + O/P/Q
  v_res := public.atualizar_lote_admin(v_lote, 'Lote Editado', 20, 40, 'MANUAL', null);
  select nome into v_txt from public.lotes where id = v_lote;
  if v_txt <> 'Lote Editado' then raise exception 'C: nome nao atualizado'; end if;
  select quantidade into v_int from public.lotes where id = v_lote;
  if v_int <> 20 then raise exception 'C: quantidade nao atualizada'; end if;
  select preco into v_num from public.lotes where id = v_lote;
  if v_num <> 40 then raise exception 'C: preco nao atualizado'; end if;
  select ordem into v_int from public.lotes where id = v_lote;
  if v_int <> 1 then raise exception 'O: ordem mudou'; end if;
  if (select evento_id from public.lotes where id = v_lote) <> v_evento then raise exception 'P: evento_id mudou'; end if;
  if (select status from public.lotes where id = v_lote) <> 'INATIVO' then raise exception 'Q: status mudou'; end if;

  -- R) historico preservado
  select valor_unitario into v_num from public.pedidos where id = v_pedido;
  if v_num <> 30 then raise exception 'R: pedido antigo mudou para %', v_num; end if;
  if (select count(*) from public.ingressos where lote_id = v_lote and valor_unitario = 30) <> 12 then
    raise exception 'R: ingressos antigos mudaram';
  end if;

  -- T) auditoria
  select count(*) into v_aud from public.auditoria where acao = 'LOTE_ATUALIZADO' and entidade_id = v_lote;
  if v_aud < 1 then raise exception 'T: auditoria ausente'; end if;

  -- F) nome vazio
  begin
    perform public.atualizar_lote_admin(v_lote, '   ', 20, 40, 'MANUAL', null);
    raise exception 'F: nome vazio deveria falhar';
  exception when others then
    if position('nome do lote' in lower(sqlerrm)) = 0 then raise exception 'F: %', sqlerrm; end if;
  end;

  -- G) preco negativo
  begin
    perform public.atualizar_lote_admin(v_lote, 'Lote', 20, -1, 'MANUAL', null);
    raise exception 'G: preco negativo deveria falhar';
  exception when others then
    if position('preco' in lower(sqlerrm)) = 0 then raise exception 'G: %', sqlerrm; end if;
  end;

  -- H) quantidade <= 0
  begin
    perform public.atualizar_lote_admin(v_lote, 'Lote', 0, 40, 'MANUAL', null);
    raise exception 'H: quantidade 0 deveria falhar';
  exception when others then
    if position('quantidade' in lower(sqlerrm)) = 0 then raise exception 'H: %', sqlerrm; end if;
  end;

  -- K) DATA_HORA sem ativacao_em
  begin
    perform public.atualizar_lote_admin(v_lote, 'Lote', 20, 40, 'DATA_HORA', null);
    raise exception 'K: DATA_HORA sem ativacao_em deveria falhar';
  exception when others then
    if position('data e hora' in lower(sqlerrm)) = 0 then raise exception 'K: %', sqlerrm; end if;
  end;

  -- L) MANUAL zera ativacao_em
  perform public.atualizar_lote_admin(v_lote, 'Lote', 20, 40, 'MANUAL', '2026-10-29T23:00:00Z'::timestamptz);
  select ativacao_em into v_ts from public.lotes where id = v_lote;
  if v_ts is not null then raise exception 'L: MANUAL deveria zerar ativacao_em'; end if;

  -- M) ESGOTAMENTO zera ativacao_em
  perform public.atualizar_lote_admin(v_lote, 'Lote', 20, 40, 'ESGOTAMENTO', '2026-10-29T23:00:00Z'::timestamptz);
  select ativacao_em into v_ts from public.lotes where id = v_lote;
  if v_ts is not null then raise exception 'M: ESGOTAMENTO deveria zerar ativacao_em'; end if;

  -- U) reduzir para o comprometido exato => disponibilidade 0 (nunca negativa)
  perform public.atualizar_lote_admin(v_lote, 'Lote', 12, 40, 'MANUAL', null);
  if private.calcular_disponibilidade_lote(v_lote) <> 0 then raise exception 'U: disponibilidade deveria ser 0'; end if;

  -- D/N) ativa e edita lote ATIVO (tipo preservado)
  perform public.ativar_lote_manual(v_lote);
  v_res := public.atualizar_lote_admin(v_lote, 'Lote Ativo Editado', 30, 55, 'DATA_HORA', '2027-01-01T00:00:00Z'::timestamptz);
  select tipo_ativacao into v_txt from public.lotes where id = v_lote;
  if v_txt <> 'MANUAL' then raise exception 'N: ATIVO nao deveria mudar tipo (%)', v_txt; end if;
  select preco into v_num from public.lotes where id = v_lote;
  if v_num <> 55 then raise exception 'D: ATIVO deveria permitir editar preco'; end if;
  select quantidade into v_int from public.lotes where id = v_lote;
  if v_int <> 30 then raise exception 'D: ATIVO deveria permitir editar quantidade'; end if;

  -- S) nova reserva usa o novo preco
  v_res := public.criar_reserva(v_evento, 'Novo Comprador', '11988887777', null, array['Nova Pessoa']);
  if (v_res->>'valor_unitario')::numeric <> 55 then
    raise exception 'S: nova reserva deveria usar 55 (%)', v_res->>'valor_unitario';
  end if;

  -- E) ENCERRADO rejeitado
  begin
    perform public.atualizar_lote_admin(v_lote_encerrado, 'X', 10, 30, 'MANUAL', null);
    raise exception 'E: ENCERRADO deveria falhar';
  exception when others then
    if position('encerrados' in lower(sqlerrm)) = 0 then raise exception 'E: %', sqlerrm; end if;
  end;
end $$;

select 'editar_lote_admin: todos os testes passaram' as resultado;

rollback;
