-- =============================================================================
-- GZ1 Ingresso - Testes: edicao administrativa de evento
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
  if has_function_privilege('anon', 'public.obter_evento_admin(uuid)'::regprocedure, 'EXECUTE') then
    raise exception 'A: anon nao pode obter_evento_admin';
  end if;
  if has_function_privilege('anon',
       'public.atualizar_evento_admin(uuid,text,text,text,text,timestamptz,text,text,integer,integer,public.status_publicacao,public.status_vendas)'::regprocedure,
       'EXECUTE') then
    raise exception 'A: anon nao pode atualizar_evento_admin';
  end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_portaria uuid := gen_random_uuid();
  v_evento uuid := gen_random_uuid();
  v_outro uuid := gen_random_uuid();
  v_realizado uuid := gen_random_uuid();
  v_lote uuid := gen_random_uuid();
  v_pedido uuid := gen_random_uuid();
  v_res jsonb;
  v_local text;
  v_status text;
  v_pub timestamptz;
  v_aud integer;
begin
  insert into auth.users (id) values (v_admin), (v_portaria);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Ed', 'admined_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Port Ed', 'ported_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true);

  insert into public.eventos (id, nome, slug, descricao, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, vendas_status, publicacao_status)
  values (v_evento, 'Evento Editar', 'evento-editar-' || replace(v_evento::text,'-',''), 'desc', now() + interval '20 days', 'Galeria', 'Rua 1', 100, 50, 'AGENDADO', 'ENCERRADAS', 'RASCUNHO'),
         (v_outro, 'Outro Evento', 'outro-evento-' || replace(v_outro::text,'-',''), null, now() + interval '20 days', 'Galeria', 'Rua 2', 100, 50, 'AGENDADO', 'ENCERRADAS', 'RASCUNHO'),
         (v_realizado, 'Evento Realizado', 'evento-realizado-' || replace(v_realizado::text,'-',''), null, now() - interval '5 days', 'Galeria', 'Rua 3', 100, 50, 'REALIZADO', 'ENCERRADAS', 'PUBLICADO');

  -- 2 ingressos vendidos para validar impacto de capacidade/estoque
  insert into public.lotes (id, evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_lote, v_evento, 'Lote 1', 1, 10, 50, 'MANUAL', 'ATIVO');
  insert into public.pedidos (id, evento_id, lote_id, codigo, comprador_nome, comprador_telefone, quantidade, tipo_preco, valor_unitario, valor_total, status, reserva_expira_em)
  values (v_pedido, v_evento, v_lote, 'ED' || substr(replace(v_pedido::text,'-',''),1,10), 'Comprador', '11999999999', 2, 'LOTE', 50, 100, 'PAGO', now() + interval '1 day');
  insert into public.ingressos (pedido_id, evento_id, lote_id, codigo, participante_nome, valor_unitario, qr_token, status) values
    (v_pedido, v_evento, v_lote, 'ED' || substr(replace(gen_random_uuid()::text,'-',''),1,12) || 'A', 'P1', 50, gen_random_uuid()::text, 'VALIDO'),
    (v_pedido, v_evento, v_lote, 'ED' || substr(replace(gen_random_uuid()::text,'-',''),1,12) || 'B', 'P2', 50, gen_random_uuid()::text, 'VALIDO');

  -- B) PORTARIA negado
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  begin
    perform public.obter_evento_admin(v_evento);
    raise exception 'B: PORTARIA nao deveria obter';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'B(obter): %', sqlerrm; end if;
  end;
  begin
    perform public.atualizar_evento_admin(v_evento, 'X', 'x-slug', null, null, now(), 'L', 'E', 10, 5, 'RASCUNHO', null);
    raise exception 'B: PORTARIA nao deveria atualizar';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'B(atualizar): %', sqlerrm; end if;
  end;

  -- ADMIN
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  -- C) ADMIN obtem
  v_res := public.obter_evento_admin(v_evento);
  if (v_res->>'nome') <> 'Evento Editar' then raise exception 'C: nome incorreto'; end if;
  if (v_res->>'publicacao_status') <> 'RASCUNHO' then raise exception 'C: publicacao incorreta'; end if;

  -- D) inexistente
  begin
    perform public.obter_evento_admin(gen_random_uuid());
    raise exception 'D: evento inexistente deveria falhar';
  exception when others then
    if position('nao encontrado' in lower(sqlerrm)) = 0 then raise exception 'D: %', sqlerrm; end if;
  end;

  -- J) assinatura nao permite status livre
  if pg_get_function_arguments('public.atualizar_evento_admin'::regproc) like '%status_evento%' then
    raise exception 'J: atualizar nao deveria receber status_evento';
  end if;

  -- E) atualizacao com sucesso
  v_res := public.atualizar_evento_admin(v_evento, 'Evento Editado', 'Evento Editado!', 'nova desc', null, '2026-10-29T23:00:00Z'::timestamptz, 'Arena', 'Rua 9', 120, 60, 'PUBLICADO', 'ABERTAS');
  if (v_res->>'slug') <> 'evento-editado' then raise exception 'E: slug incorreto (%)', v_res->>'slug'; end if;

  -- G) timezone preservado (20:00 SP)
  select to_char(inicio_em at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI') into v_local
    from public.eventos where id = v_evento;
  if v_local <> '2026-10-29 20:00' then raise exception 'G: timezone incorreto (%)', v_local; end if;
  -- E/vendas delegado
  select vendas_status into v_status from public.eventos where id = v_evento;
  if v_status <> 'ABERTAS' then raise exception 'E: vendas deveriam ser ABERTAS'; end if;
  -- publicacao RASCUNHO->PUBLICADO define publicado_em
  select publicado_em into v_pub from public.eventos where id = v_evento;
  if v_pub is null then raise exception 'pub: publicado_em deveria ser preenchido'; end if;
  -- PUBLICADO->RASCUNHO nao zera
  perform public.atualizar_evento_admin(v_evento, 'Evento Editado', 'evento-editado', 'nova desc', null, '2026-10-29T23:00:00Z'::timestamptz, 'Arena', 'Rua 9', 120, 60, 'RASCUNHO', 'ABERTAS');
  select publicado_em into v_pub from public.eventos where id = v_evento;
  if v_pub is null then raise exception 'pub: RASCUNHO nao deveria zerar publicado_em'; end if;

  -- F) slug duplicado
  begin
    perform public.atualizar_evento_admin(v_evento, 'Conflito', 'outro-evento-' || replace(v_outro::text,'-',''), null, null, now(), 'L', 'E', 100, 50, 'RASCUNHO', null);
    raise exception 'F: slug duplicado deveria falhar';
  exception when others then
    if position('endereco de url' in lower(sqlerrm)) = 0 then raise exception 'F: %', sqlerrm; end if;
  end;

  -- H) capacidade invalida
  begin
    perform public.atualizar_evento_admin(v_evento, 'X', 'x-slug', null, null, now(), 'L', 'E', 0, 0, 'RASCUNHO', null);
    raise exception 'H: capacidade 0 deveria falhar';
  exception when others then
    if position('capacidade' in lower(sqlerrm)) = 0 then raise exception 'H: %', sqlerrm; end if;
  end;

  -- I) estoque > capacidade
  begin
    perform public.atualizar_evento_admin(v_evento, 'X', 'x-slug', null, null, now(), 'L', 'E', 10, 20, 'RASCUNHO', null);
    raise exception 'I: estoque>capacidade deveria falhar';
  exception when others then
    if position('exceder' in lower(sqlerrm)) = 0 then raise exception 'I: %', sqlerrm; end if;
  end;
  -- I2) estoque abaixo dos ingressos emitidos
  begin
    perform public.atualizar_evento_admin(v_evento, 'X', 'x-slug', null, null, now(), 'L', 'E', 100, 1, 'RASCUNHO', null);
    raise exception 'I2: estoque<emitidos deveria falhar';
  exception when others then
    if position('menor que os ingressos' in lower(sqlerrm)) = 0 then raise exception 'I2: %', sqlerrm; end if;
  end;
  -- capacidade abaixo dos ingressos emitidos
  begin
    perform public.atualizar_evento_admin(v_evento, 'X', 'x-slug', null, null, now(), 'L', 'E', 1, 1, 'RASCUNHO', null);
    raise exception 'I3: capacidade<emitidos deveria falhar';
  exception when others then
    if position('menor que os ingressos' in lower(sqlerrm)) = 0 then raise exception 'I3: %', sqlerrm; end if;
  end;

  -- J2) evento REALIZADO nao pode ser editado
  begin
    perform public.atualizar_evento_admin(v_realizado, 'X', 'x-slug', null, null, now(), 'L', 'E', 100, 50, 'RASCUNHO', null);
    raise exception 'J2: REALIZADO nao deveria ser editavel';
  exception when others then
    if position('nao pode ser editado' in lower(sqlerrm)) = 0 then raise exception 'J2: %', sqlerrm; end if;
  end;

  -- K) capa valida persistida
  perform public.atualizar_evento_admin(v_evento, 'Evento Editado', 'evento-editado', 'd', 'https://cdn.exemplo.com/capa.jpg', '2026-10-29T23:00:00Z'::timestamptz, 'Arena', 'Rua 9', 120, 60, 'RASCUNHO', 'ABERTAS');
  select imagem_url into v_local from public.eventos where id = v_evento;
  if v_local <> 'https://cdn.exemplo.com/capa.jpg' then raise exception 'K: capa nao persistida (%)', v_local; end if;

  -- L) blob nao persistido
  begin
    perform public.atualizar_evento_admin(v_evento, 'Evento Editado', 'evento-editado', 'd', 'blob:https://gz-1-ingressos.vercel.app/abc', '2026-10-29T23:00:00Z'::timestamptz, 'Arena', 'Rua 9', 120, 60, 'RASCUNHO', 'ABERTAS');
    raise exception 'L: blob deveria ser rejeitado';
  exception when others then
    if position('imagem invalida' in lower(sqlerrm)) = 0 then raise exception 'L: %', sqlerrm; end if;
  end;

  -- M) auditoria
  select count(*) into v_aud from public.auditoria
   where acao = 'EVENTO_ATUALIZADO_ADMIN' and entidade = 'eventos' and entidade_id = v_evento;
  if v_aud < 1 then raise exception 'M: auditoria de atualizacao ausente'; end if;
end $$;

select 'editar_evento_admin: todos os testes passaram' as resultado;

rollback;
