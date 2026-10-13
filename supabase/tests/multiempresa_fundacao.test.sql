-- =============================================================================
-- Ingressoudi - Testes: fundacao multiempresa (Etapa A)
-- Arquivo: supabase/tests/multiempresa_fundacao.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
-- =============================================================================

begin;

do $$
declare
  v_org_a uuid;
  v_org_b uuid;
  v_admin_a uuid := gen_random_uuid();
  v_port_b uuid := gen_random_uuid();
  v_sem_membro uuid := gen_random_uuid();
  v_membro_inativo uuid := gen_random_uuid();
  v_evento_a uuid;
  v_evento_b uuid;
  v_lote uuid;
  v_vip uuid;
  v_org uuid;
begin
  insert into public.organizacoes (nome, slug) values ('Org A', 'org-a-teste') returning id into v_org_a;
  insert into public.organizacoes (nome, slug) values ('Org B', 'org-b-teste') returning id into v_org_b;

  insert into auth.users (id) values (v_admin_a), (v_port_b), (v_sem_membro), (v_membro_inativo);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin_a, 'Admin A', 'admin_a_' || replace(v_admin_a::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_port_b, 'Portaria B', 'port_b_' || replace(v_port_b::text,'-','') || '@test.local', 'PORTARIA', true),
    (v_sem_membro, 'Sem Membro', 'sem_' || replace(v_sem_membro::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_membro_inativo, 'Membro Inativo', 'inat_' || replace(v_membro_inativo::text,'-','') || '@test.local', 'ADMINISTRADOR', true);

  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values
    (v_org_a, v_admin_a, 'ADMINISTRADOR'),
    (v_org_b, v_port_b, 'PORTARIA');
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil, ativo) values
    (v_org_a, v_membro_inativo, 'ADMINISTRADOR', false);

  -- A) primeira associacao define a organizacao ativa -------------------------
  if (select organizacao_ativa_id from public.usuarios where id = v_admin_a) is distinct from v_org_a then
    raise exception 'A: organizacao ativa do admin A deveria ser Org A';
  end if;
  if (select organizacao_ativa_id from public.usuarios where id = v_port_b) is distinct from v_org_b then
    raise exception 'A: organizacao ativa da portaria B deveria ser Org B';
  end if;

  -- B) admin A: organizacao A, admin, opera portaria ---------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_a::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin_a::text, true);
  if private.organizacao_atual_id() is distinct from v_org_a then
    raise exception 'B: organizacao_atual_id deveria ser Org A';
  end if;
  if not private.usuario_e_admin() then
    raise exception 'B: admin A deveria ser admin';
  end if;
  if not private.usuario_pode_operar_portaria() then
    raise exception 'B: admin A deveria operar portaria';
  end if;

  -- C) evento criado pelo admin A herda Org A sem informar -------------------
  insert into public.eventos (
    nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado
  ) values (
    'Evento A', 'evento-a-' || replace(gen_random_uuid()::text,'-',''),
    now() + interval '2 days', 'Local A', 'End A', 100, 50
  ) returning id, organizacao_id into v_evento_a, v_org;
  if v_org is distinct from v_org_a then
    raise exception 'C: evento deveria herdar Org A';
  end if;
  if not private.evento_da_organizacao_atual(v_evento_a) then
    raise exception 'C: evento A deveria ser da organizacao atual';
  end if;

  -- D) portaria B: organizacao B, nao admin, opera portaria -------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_port_b::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_port_b::text, true);
  if private.organizacao_atual_id() is distinct from v_org_b then
    raise exception 'D: organizacao_atual_id deveria ser Org B';
  end if;
  if private.usuario_e_admin() then
    raise exception 'D: portaria B nao deveria ser admin';
  end if;
  if not private.usuario_pode_operar_portaria() then
    raise exception 'D: portaria B deveria operar portaria';
  end if;
  if private.evento_da_organizacao_atual(v_evento_a) then
    raise exception 'D: evento A NAO deveria ser da organizacao da portaria B';
  end if;

  -- E) usuarios.perfil sozinho NAO autoriza ----------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_sem_membro::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_sem_membro::text, true);
  if private.usuario_e_admin() or private.usuario_pode_operar_portaria() then
    raise exception 'E: usuario sem membro nao deveria ter permissao';
  end if;
  if private.organizacao_atual_id() is not null then
    raise exception 'E: usuario sem membro nao deveria ter organizacao atual';
  end if;

  -- F) membro inativo nao autoriza ---------------------------------------------
  update public.usuarios set organizacao_ativa_id = v_org_a where id = v_membro_inativo;
  perform set_config('request.jwt.claims', json_build_object('sub', v_membro_inativo::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_membro_inativo::text, true);
  if private.usuario_e_admin() then
    raise exception 'F: membro inativo nao deveria ser admin';
  end if;

  -- G) organizacao inativa nao autoriza --------------------------------------
  update public.organizacoes set ativo = false where id = v_org_a;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_a::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin_a::text, true);
  if private.usuario_e_admin() or private.organizacao_atual_id() is not null then
    raise exception 'G: organizacao inativa nao deveria autorizar';
  end if;
  update public.organizacoes set ativo = true where id = v_org_a;

  -- H) sem usuario e sem organizacao informada: evento rejeitado -------------
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    insert into public.eventos (
      nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado
    ) values (
      'Sem Org', 'sem-org-' || replace(gen_random_uuid()::text,'-',''),
      now() + interval '2 days', 'L', 'E', 10, 5
    );
    raise exception 'H: evento sem organizacao deveria falhar';
  exception when others then
    if position('organizacao nao definida' in lower(sqlerrm)) = 0 then
      raise exception 'H: erro inesperado: %', sqlerrm;
    end if;
  end;

  -- I) organizacao do evento e imutavel ----------------------------------------
  begin
    update public.eventos set organizacao_id = v_org_b where id = v_evento_a;
    raise exception 'I: troca de organizacao do evento deveria falhar';
  exception when others then
    if position('nao e permitido alterar a organizacao' in lower(sqlerrm)) = 0 then
      raise exception 'I: erro inesperado: %', sqlerrm;
    end if;
  end;

  -- J) lote herda a organizacao do evento; divergencia e bloqueada -----------
  insert into public.eventos (
    organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado
  ) values (
    v_org_b, 'Evento B', 'evento-b-' || replace(gen_random_uuid()::text,'-',''),
    now() + interval '3 days', 'Local B', 'End B', 100, 50
  ) returning id into v_evento_b;

  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao)
  values (v_evento_a, 'Lote 1', 1, 10, 25.00, 'MANUAL')
  returning id, organizacao_id into v_lote, v_org;
  if v_org is distinct from v_org_a then
    raise exception 'J: lote deveria herdar Org A';
  end if;

  begin
    insert into public.lotes (organizacao_id, evento_id, nome, ordem, quantidade, preco, tipo_ativacao)
    values (v_org_b, v_evento_a, 'Lote X', 2, 10, 25.00, 'MANUAL');
    raise exception 'J: lote com organizacao divergente deveria falhar';
  exception when others then
    if position('divergente' in lower(sqlerrm)) = 0 then
      raise exception 'J: erro inesperado: %', sqlerrm;
    end if;
  end;

  -- K) lista VIP herda a organizacao do evento -------------------------------
  insert into public.lista_vip (evento_id, nome, criado_por_usuario_id)
  values (v_evento_b, 'Convidado B', v_port_b)
  returning id, organizacao_id into v_vip, v_org;
  if v_org is distinct from v_org_b then
    raise exception 'K: VIP deveria herdar Org B';
  end if;

  -- L) tabelas novas fechadas para anon/authenticated -------------------------
  if has_table_privilege('authenticated', 'public.organizacoes', 'SELECT')
     or has_table_privilege('anon', 'public.organizacoes', 'SELECT')
     or has_table_privilege('authenticated', 'public.membros_organizacao', 'SELECT') then
    raise exception 'L: tabelas novas nao devem ter acesso direto';
  end if;
  if has_function_privilege('authenticated', 'private.usuario_e_super_admin()', 'EXECUTE') then
    raise exception 'L: usuario_e_super_admin nao deve ser executavel por authenticated';
  end if;
end $$;

select 'multiempresa_fundacao: todos os testes passaram' as resultado;

rollback;
