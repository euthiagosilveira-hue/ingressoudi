-- =============================================================================
-- Ingressoudi - Testes: venda online ate 3 horas depois do inicio do evento
-- Arquivo: supabase/tests/vendas_online_apos_inicio.test.sql
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
  v_org_slug text;
  v_ev1 uuid;  -- comecou ha 1 hora: ainda vende
  v_ev2 uuid;  -- comecou ha 4 horas: nao vende mais
  v_res jsonb;
  v_ok boolean;
  v_proc jsonb;
begin
  update public.organizacoes set aprovada = true
   where id = current_setting('teste.organizacao_id')::uuid
  returning slug into v_org_slug;

  insert into public.eventos (nome, slug, inicio_em, local, endereco,
    capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Ev 1h', 'ev-1h-' || replace(gen_random_uuid()::text, '-', ''), now() - interval '1 hour',
    'L', 'E', 100, 50, 'AGENDADO', 'PUBLICADO', 'ABERTAS')
  returning id into v_ev1;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_ev1, 'Lote', 1, 50, 40, 'MANUAL', 'ATIVO');

  insert into public.eventos (nome, slug, inicio_em, local, endereco,
    capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Ev 4h', 'ev-4h-' || replace(gen_random_uuid()::text, '-', ''), now() - interval '4 hours',
    'L', 'E', 100, 50, 'AGENDADO', 'PUBLICADO', 'ABERTAS')
  returning id into v_ev2;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_ev2, 'Lote', 1, 50, 40, 'MANUAL', 'ATIVO');

  -- T1) dentro das 3 horas: situacao DISPONIVEL, aparece na vitrine e reserva funciona
  if private.calcular_situacao_venda(v_ev1) <> 'DISPONIVEL' then
    raise exception 'T1: deveria estar DISPONIVEL, veio %', private.calcular_situacao_venda(v_ev1);
  end if;
  if not exists (select 1 from private.listar_eventos_publicos_organizacao(v_org_slug) x where x.evento_id = v_ev1) then
    raise exception 'T1: evento iniciado ha 1h deveria aparecer na vitrine';
  end if;
  v_res := public.criar_reserva(v_ev1, 'Comprador', '34999999999', 'demo@ingressoudi.local', array['P1']);
  if v_res->>'pedido_id' is null then
    raise exception 'T1: reserva deveria ser criada';
  end if;

  -- T2) depois das 3 horas: VENDAS_ENCERRADAS, fora da vitrine e reserva recusada
  if private.calcular_situacao_venda(v_ev2) <> 'VENDAS_ENCERRADAS' then
    raise exception 'T2: deveria estar VENDAS_ENCERRADAS, veio %', private.calcular_situacao_venda(v_ev2);
  end if;
  if exists (select 1 from private.listar_eventos_publicos_organizacao(v_org_slug) x where x.evento_id = v_ev2) then
    raise exception 'T2: evento iniciado ha 4h nao deveria aparecer na vitrine';
  end if;
  v_ok := false;
  begin
    perform public.criar_reserva(v_ev2, 'Comprador', '34999999999', 'demo@ingressoudi.local', array['P1']);
  exception when others then
    v_ok := true;
  end;
  if not v_ok then
    raise exception 'T2: reserva depois de 3h deveria ser recusada';
  end if;

  -- T3) inicio automatico: evento de 1h vira EM_ANDAMENTO e continua vendendo;
  --     o de 4h tem as vendas encerradas
  v_proc := private.processar_inicio_eventos(null);
  if (select status::text || '/' || vendas_status::text from public.eventos where id = v_ev1) <> 'EM_ANDAMENTO/ABERTAS' then
    raise exception 'T3: ev1 deveria ficar EM_ANDAMENTO/ABERTAS';
  end if;
  if (select vendas_status::text from public.eventos where id = v_ev2) <> 'ENCERRADAS' then
    raise exception 'T3: ev2 deveria ter vendas ENCERRADAS';
  end if;
  if private.calcular_situacao_venda(v_ev1) <> 'DISPONIVEL' then
    raise exception 'T3: ev1 em andamento deveria seguir DISPONIVEL, veio %', private.calcular_situacao_venda(v_ev1);
  end if;
  v_res := public.criar_reserva(v_ev1, 'Comprador 2', '34999999998', 'demo2@ingressoudi.local', array['P2']);
  if v_res->>'pedido_id' is null then
    raise exception 'T3: reserva em evento EM_ANDAMENTO dentro do prazo deveria funcionar';
  end if;

  -- T4) produtor encerrando as vendas continua valendo
  update public.eventos set vendas_status = 'ENCERRADAS' where id = v_ev1;
  if private.calcular_situacao_venda(v_ev1) <> 'EVENTO_EM_ANDAMENTO' then
    raise exception 'T4: vendas encerradas em andamento deveria ser EVENTO_EM_ANDAMENTO, veio %', private.calcular_situacao_venda(v_ev1);
  end if;

  raise notice 'vendas_online_apos_inicio: OK';
end
$$;

rollback;
