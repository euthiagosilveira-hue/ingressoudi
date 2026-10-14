-- =============================================================================
-- Ingressoudi - Modo demonstracao (somente super admin)
--  * iniciar_evento_agora: AGENDADO -> EM_ANDAMENTO (libera a portaria antes do
--    horario; vendas online encerram, como no inicio automatico).
--  * reabrir_vendas_demonstracao: EM_ANDAMENTO -> AGENDADO com vendas ABERTAS,
--    para repetir a demonstracao (compra -> iniciar -> portaria). Se o horario do
--    evento ja passou, ele e adiado para daqui a 1 dia (a venda exige horario futuro).
-- Ambas exigem super admin e evento da organizacao ativa; registram auditoria.
-- =============================================================================

create or replace function private.iniciar_evento_agora(p_evento_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_evento public.eventos%rowtype;
begin
  if not private.usuario_e_super_admin() then
    raise exception 'Permissao negada: apenas super administrador' using errcode = '42501';
  end if;
  if not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  select * into v_evento from public.eventos e where e.id = p_evento_id for update;
  if v_evento.status <> 'AGENDADO' then
    raise exception 'Somente evento AGENDADO pode ser iniciado (status=%)', v_evento.status using errcode = '23514';
  end if;

  update public.eventos set status = 'EM_ANDAMENTO', vendas_status = 'ENCERRADAS' where id = p_evento_id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos, organizacao_id)
  values (auth.uid(), 'EVENTO_INICIADO_MANUAL', 'eventos', p_evento_id,
          jsonb_build_object('status', v_evento.status, 'vendas_status', v_evento.vendas_status),
          jsonb_build_object('status', 'EM_ANDAMENTO', 'vendas_status', 'ENCERRADAS', 'iniciado_em', now()),
          v_evento.organizacao_id);

  return jsonb_build_object('evento_id', p_evento_id, 'status', 'EM_ANDAMENTO', 'vendas_status', 'ENCERRADAS');
end;
$$;

create or replace function public.iniciar_evento_agora(p_evento_id uuid)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.iniciar_evento_agora(p_evento_id); $$;

create or replace function private.reabrir_vendas_demonstracao(p_evento_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_evento public.eventos%rowtype;
  v_inicio timestamptz;
begin
  if not private.usuario_e_super_admin() then
    raise exception 'Permissao negada: apenas super administrador' using errcode = '42501';
  end if;
  if not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  select * into v_evento from public.eventos e where e.id = p_evento_id for update;
  if v_evento.status <> 'EM_ANDAMENTO' then
    raise exception 'Somente evento EM_ANDAMENTO pode voltar para vendas (status=%)', v_evento.status using errcode = '23514';
  end if;

  v_inicio := case when v_evento.inicio_em <= now() then date_trunc('minute', now()) + interval '1 day'
                   else v_evento.inicio_em end;

  update public.eventos
     set status = 'AGENDADO', vendas_status = 'ABERTAS', inicio_em = v_inicio, encerrado_em = null
   where id = p_evento_id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos, organizacao_id)
  values (auth.uid(), 'EVENTO_VENDAS_REABERTAS_DEMO', 'eventos', p_evento_id,
          jsonb_build_object('status', v_evento.status, 'vendas_status', v_evento.vendas_status, 'inicio_em', v_evento.inicio_em),
          jsonb_build_object('status', 'AGENDADO', 'vendas_status', 'ABERTAS', 'inicio_em', v_inicio),
          v_evento.organizacao_id);

  return jsonb_build_object('evento_id', p_evento_id, 'status', 'AGENDADO', 'vendas_status', 'ABERTAS', 'inicio_em', v_inicio);
end;
$$;

create or replace function public.reabrir_vendas_demonstracao(p_evento_id uuid)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.reabrir_vendas_demonstracao(p_evento_id); $$;

revoke all on function private.iniciar_evento_agora(uuid) from public, anon;
revoke all on function private.reabrir_vendas_demonstracao(uuid) from public, anon;
revoke all on function public.iniciar_evento_agora(uuid) from public, anon;
revoke all on function public.reabrir_vendas_demonstracao(uuid) from public, anon;
grant execute on function private.iniciar_evento_agora(uuid) to authenticated, service_role;
grant execute on function private.reabrir_vendas_demonstracao(uuid) to authenticated, service_role;
grant execute on function public.iniciar_evento_agora(uuid) to authenticated, service_role;
grant execute on function public.reabrir_vendas_demonstracao(uuid) to authenticated, service_role;
