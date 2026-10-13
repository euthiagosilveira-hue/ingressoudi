-- =============================================================================
-- GZ1 Ingresso - Testes: reserva de 30 minutos + email obrigatorio no checkout
-- Arquivo: supabase/tests/reserva_30_minutos.test.sql
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
  v_evento_id uuid;
  v_res jsonb;
  v_pedido uuid;
  v_token uuid;
  v_expira timestamptz;
  v_diff numeric;
  v_email text;
  v_pag jsonb;
  v_pag_expira timestamptz;
  v_ped_expira timestamptz;
begin
  insert into public.eventos (
    nome, slug, inicio_em, local, endereco,
    capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status
  ) values (
    'Teste Reserva 30min', 'teste-reserva-30-' || replace(gen_random_uuid()::text, '-', ''),
    now() + interval '20 days', 'Local T', 'End T',
    100, 50, 'AGENDADO', 'PUBLICADO', 'ABERTAS'
  ) returning id into v_evento_id;

  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_evento_id, 'Lote T', 1, 50, 40, 'MANUAL', 'ATIVO');

  -- reserva real via RPC publica, com email valido
  v_res := public.criar_reserva(
    v_evento_id, 'Comprador T', '34999999999', 'demo@gz1.local', array['P1', 'P2']
  );
  v_pedido := (v_res->>'pedido_id')::uuid;
  v_token := (v_res->>'checkout_token')::uuid;
  v_expira := (v_res->>'reserva_expira_em')::timestamptz;

  -- T1) expiracao ~= now() + 30 min (tolerancia 29..31)
  v_diff := extract(epoch from (v_expira - now())) / 60.0;
  if v_diff < 29 or v_diff > 31 then
    raise exception 'T1: reserva_expira_em deveria ser ~30min, veio % min', round(v_diff, 2);
  end if;

  -- T2) email persistido
  select comprador_email into v_email from public.pedidos where id = v_pedido;
  if v_email <> 'demo@gz1.local' then
    raise exception 'T2: comprador_email nao persistido corretamente (%)', coalesce(v_email, 'null');
  end if;

  -- T3) checkout_token presente
  if v_token is null then
    raise exception 'T3: checkout_token ausente';
  end if;

  -- T4) pagamento herda a expiracao do pedido (nao hardcode 30min na RPC)
  v_pag := public.criar_pagamento_pendente_por_token(v_token, 'STONE');
  select expira_em into v_pag_expira from public.pagamentos where pedido_id = v_pedido;
  select reserva_expira_em into v_ped_expira from public.pedidos where id = v_pedido;
  if v_pag_expira <> v_ped_expira then
    raise exception 'T4: pagamento.expira_em difere de pedido.reserva_expira_em';
  end if;
  if v_pag is null then
    raise exception 'T4: pagamento nao retornado';
  end if;
end $$;

select 'reserva_30_minutos: todos os testes passaram' as resultado;

rollback;
