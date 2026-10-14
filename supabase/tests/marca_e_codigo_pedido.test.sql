-- =============================================================================
-- Ingressoudi - Testes: marca da casa e codigo do pedido (Fase 3B parte 1)
-- Arquivo: supabase/tests/marca_e_codigo_pedido.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
-- =============================================================================

begin;

do $$
begin
  if has_function_privilege('anon', 'public.atualizar_marca_organizacao(text,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.obter_marca_organizacao()', 'EXECUTE') then
    raise exception 'ACL: anon nao pode ler/alterar a marca pelo painel';
  end if;
  if has_function_privilege('authenticated', 'private.gerar_codigo_pedido()', 'EXECUTE') then
    raise exception 'ACL: gerar_codigo_pedido e interno';
  end if;
end $$;

do $$
declare
  v_sa text := 'mc-a-' || substr(replace(gen_random_uuid()::text,'-',''), 1, 10);
  v_org_a uuid; v_org_b uuid;
  v_admin uuid := gen_random_uuid();
  v_port uuid := gen_random_uuid();
  v_admin_b uuid := gen_random_uuid();
  v_ev uuid; v_lote uuid; v_res jsonb;
begin
  insert into public.organizacoes (nome, slug) values ('Marca A', v_sa) returning id into v_org_a;
  insert into public.organizacoes (nome, slug) values ('Marca B', 'mc-b-' || substr(md5(random()::text),1,10)) returning id into v_org_b;
  insert into auth.users (id) values (v_admin), (v_port), (v_admin_b);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Adm', 'mc_a_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_port, 'Port', 'mc_p_' || replace(v_port::text,'-','') || '@test.local', 'PORTARIA', true),
    (v_admin_b, 'Adm B', 'mc_b_' || replace(v_admin_b::text,'-','') || '@test.local', 'ADMINISTRADOR', true);
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values
    (v_org_a, v_admin, 'ADMINISTRADOR'), (v_org_a, v_port, 'PORTARIA'), (v_org_b, v_admin_b, 'ADMINISTRADOR');

  -- T1) admin atualiza logo e cor da propria casa --------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_res := public.atualizar_marca_organizacao('https://cdn.exemplo.com/logo.png', '#FF5500');
  if v_res->>'cor_primaria' <> '#ff5500' or v_res->>'logo_url' <> 'https://cdn.exemplo.com/logo.png' then
    raise exception 'T1: marca nao salva: %', v_res;
  end if;
  if (select cor_primaria from public.organizacoes where id = v_org_b) is not null then
    raise exception 'T1: alterou outra organizacao';
  end if;

  -- T2) validacoes ------------------------------------------------------------
  begin
    perform public.atualizar_marca_organizacao('data:image/png;base64,xx', null);
    raise exception 'T2: logo data: deveria falhar';
  exception when others then
    if position('logo invalido' in lower(sqlerrm)) = 0 then raise exception 'T2 logo: %', sqlerrm; end if;
  end;
  begin
    perform public.atualizar_marca_organizacao(null, 'vermelho');
    raise exception 'T2: cor invalida deveria falhar';
  exception when others then
    if position('cor invalida' in lower(sqlerrm)) = 0 then raise exception 'T2 cor: %', sqlerrm; end if;
  end;

  -- limpar (null) e permitido
  v_res := public.atualizar_marca_organizacao(null, null);
  if v_res->>'logo_url' is not null or v_res->>'cor_primaria' is not null then
    raise exception 'T2: deveria limpar logo/cor';
  end if;
  perform public.atualizar_marca_organizacao('/Logo horizontal.png', '#d9b138');

  -- T3) portaria nao altera a marca -------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_port::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_port::text, true);
  begin
    perform public.atualizar_marca_organizacao(null, '#000000');
    raise exception 'T3: portaria nao deveria alterar marca';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'T3: %', sqlerrm; end if;
  end;

  -- T4) pagina publica devolve a cor ------------------------------------------
  v_res := public.obter_organizacao_publica(v_sa);
  if v_res->>'cor_primaria' <> '#d9b138' or v_res->>'logo_url' <> '/Logo horizontal.png' then
    raise exception 'T4: pagina publica sem marca: %', v_res;
  end if;

  -- T5) novos pedidos usam o prefixo da plataforma (IU) ------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_res := public.criar_evento_admin('Show Marca', 'show-marca', null, null,
                                     now() + interval '3 days', 'Casa', 'Rua', 100, 50, 'PUBLICADO', 'ABERTAS');
  v_ev := (v_res->>'evento_id')::uuid;
  v_res := public.criar_lote_admin(v_ev, 'Lote', 10, 25, 'MANUAL', null);
  v_lote := (v_res->>'lote_id')::uuid;
  perform public.ativar_lote_manual(v_lote);

  v_res := public.criar_venda_manual_admin(v_ev, v_lote, 'Comprador', '11999990000', array['Ana']);
  if (select codigo from public.pedidos where id = (v_res->>'pedido_id')::uuid) !~ '^IU[0-9]+$' then
    raise exception 'T5: venda manual deveria gerar codigo IU: %', (select codigo from public.pedidos where id = (v_res->>'pedido_id')::uuid);
  end if;

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  v_res := public.criar_reserva(v_ev, 'Comprador', '11999990000', 'c@test.local', array['Bia']);
  if v_res->>'codigo_pedido' !~ '^IU[0-9]+$' then
    raise exception 'T5: reserva deveria gerar codigo IU: %', v_res->>'codigo_pedido';
  end if;
end $$;

rollback;
