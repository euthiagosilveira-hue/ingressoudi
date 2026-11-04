-- =============================================================================
-- Ingressoudi - Excluir evento (somente super admin)
-- Serve para remover eventos de demonstracao criados para apresentar a
-- plataforma. Apaga o evento e tudo que depende dele, numa transacao so:
-- setores, lotes, pedidos, pagamentos, ingressos, entradas, lista VIP,
-- compartilhamentos, recuperacoes e cancelamentos/reembolsos.
--
-- Protecao: se o evento tiver pedidos PAGO, a exclusao so acontece com
-- p_apagar_vendas_pagas = true (a tela pede uma confirmacao a mais).
-- Uma copia completa do que foi apagado fica em public.auditoria
-- (acao EVENTO_EXCLUIDO), caso seja preciso consultar depois.
-- =============================================================================

-- Resumo do que sera apagado, para a tela mostrar antes de confirmar.
create or replace function private.resumo_exclusao_evento(p_evento_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_evento public.eventos%rowtype;
  v_org public.organizacoes%rowtype;
begin
  if not private.usuario_e_super_admin() then
    raise exception 'Permissao negada: apenas super administrador' using errcode = '42501';
  end if;

  select * into v_evento from public.eventos where id = p_evento_id;
  if not found then
    raise exception 'Evento nao encontrado' using errcode = 'P0002';
  end if;
  select * into v_org from public.organizacoes where id = v_evento.organizacao_id;

  return jsonb_build_object(
    'evento_id',         v_evento.id,
    'nome',              v_evento.nome,
    'organizacao_nome',  v_org.nome,
    'inicio_em',         v_evento.inicio_em,
    'pedidos',           (select count(*) from public.pedidos where evento_id = p_evento_id),
    'pedidos_pagos',     (select count(*) from public.pedidos where evento_id = p_evento_id and status = 'PAGO'),
    'pedidos_pagos_online', (
      select count(*) from public.pedidos p
       where p.evento_id = p_evento_id and p.status = 'PAGO'
         and exists (select 1 from public.pagamentos g
                      where g.pedido_id = p.id and g.status = 'APROVADO' and g.provedor = 'MERCADO_PAGO')),
    'valor_pago',        (select coalesce(sum(valor_total), 0) from public.pedidos where evento_id = p_evento_id and status = 'PAGO'),
    'pix_pendentes',     (
      select count(*) from public.pedidos p
       where p.evento_id = p_evento_id and p.status = 'RESERVADO'
         and exists (select 1 from public.pagamentos g where g.pedido_id = p.id and g.status = 'PENDENTE')),
    'ingressos',         (select count(*) from public.ingressos where evento_id = p_evento_id),
    'entradas',          (select count(*) from public.entradas where evento_id = p_evento_id)
                       + (select count(*) from public.entradas_vip where evento_id = p_evento_id),
    'lista_vip',         (select count(*) from public.lista_vip where evento_id = p_evento_id),
    'lotes',             (select count(*) from public.lotes where evento_id = p_evento_id),
    'setores',           (select count(*) from public.setores where evento_id = p_evento_id)
  );
end;
$$;

create or replace function private.excluir_evento_plataforma(
  p_evento_id uuid,
  p_apagar_vendas_pagas boolean default false
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_evento public.eventos%rowtype;
  v_resumo jsonb;
  v_pedidos uuid[];
  v_ingressos uuid[];
  v_copia jsonb;
begin
  if not private.usuario_e_super_admin() then
    raise exception 'Permissao negada: apenas super administrador' using errcode = '42501';
  end if;

  -- trava o evento: nenhuma venda nova entra enquanto apaga
  select * into v_evento from public.eventos where id = p_evento_id for update;
  if not found then
    raise exception 'Evento nao encontrado' using errcode = 'P0002';
  end if;

  v_resumo := private.resumo_exclusao_evento(p_evento_id);

  if (v_resumo->>'pedidos_pagos')::int > 0 and not coalesce(p_apagar_vendas_pagas, false) then
    raise exception 'EVENTO_COM_VENDAS_PAGAS: o evento tem % pedido(s) pago(s). Confirme para apagar mesmo assim.',
      v_resumo->>'pedidos_pagos' using errcode = 'P0001';
  end if;

  select coalesce(array_agg(id), '{}') into v_pedidos from public.pedidos where evento_id = p_evento_id;
  select coalesce(array_agg(id), '{}') into v_ingressos from public.ingressos where evento_id = p_evento_id;

  -- copia de seguranca do que sera apagado
  select jsonb_build_object(
    'evento',   to_jsonb(v_evento),
    'resumo',   v_resumo,
    'setores',  (select coalesce(jsonb_agg(to_jsonb(s)), '[]') from public.setores s where s.evento_id = p_evento_id),
    'lotes',    (select coalesce(jsonb_agg(to_jsonb(l)), '[]') from public.lotes l where l.evento_id = p_evento_id),
    'pedidos',  (select coalesce(jsonb_agg(to_jsonb(p)), '[]') from public.pedidos p where p.evento_id = p_evento_id),
    'pagamentos', (select coalesce(jsonb_agg(to_jsonb(g)), '[]') from public.pagamentos g where g.pedido_id = any(v_pedidos)),
    'ingressos', (select coalesce(jsonb_agg(to_jsonb(i)), '[]') from public.ingressos i where i.evento_id = p_evento_id),
    'lista_vip', (select coalesce(jsonb_agg(to_jsonb(v)), '[]') from public.lista_vip v where v.evento_id = p_evento_id)
  ) into v_copia;

  -- ordem: quem aponta para ingressos/pedidos primeiro, evento por ultimo
  delete from public.compartilhamentos_ingresso where ingresso_id = any(v_ingressos);
  delete from public.tentativas_entrada where evento_id = p_evento_id or ingresso_id = any(v_ingressos);
  delete from public.entradas where evento_id = p_evento_id or ingresso_id = any(v_ingressos);
  delete from public.entradas_vip where evento_id = p_evento_id;
  delete from public.lista_vip where evento_id = p_evento_id;
  delete from public.recuperacoes_ingressos where pedido_id = any(v_pedidos);
  delete from public.cancelamentos_reembolsos where pedido_id = any(v_pedidos);
  delete from public.pagamentos where pedido_id = any(v_pedidos);
  delete from public.ingressos where evento_id = p_evento_id or pedido_id = any(v_pedidos);
  delete from public.pedidos where id = any(v_pedidos);
  delete from public.lotes where evento_id = p_evento_id;
  delete from public.setores where evento_id = p_evento_id;
  delete from public.eventos where id = p_evento_id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, observacao, organizacao_id)
  values (auth.uid(), 'EVENTO_EXCLUIDO', 'eventos', p_evento_id, v_copia,
          'Evento excluido pelo super admin', v_evento.organizacao_id);

  return v_resumo;
end;
$$;

create or replace function public.resumo_exclusao_evento(p_evento_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.resumo_exclusao_evento(p_evento_id); $$;

create or replace function public.excluir_evento_plataforma(
  p_evento_id uuid,
  p_apagar_vendas_pagas boolean default false
)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.excluir_evento_plataforma(p_evento_id, p_apagar_vendas_pagas); $$;

revoke all on function private.resumo_exclusao_evento(uuid) from public, anon;
revoke all on function public.resumo_exclusao_evento(uuid) from public, anon;
revoke all on function private.excluir_evento_plataforma(uuid, boolean) from public, anon;
revoke all on function public.excluir_evento_plataforma(uuid, boolean) from public, anon;
grant execute on function private.resumo_exclusao_evento(uuid) to authenticated, service_role;
grant execute on function public.resumo_exclusao_evento(uuid) to authenticated, service_role;
grant execute on function private.excluir_evento_plataforma(uuid, boolean) to authenticated, service_role;
grant execute on function public.excluir_evento_plataforma(uuid, boolean) to authenticated, service_role;
