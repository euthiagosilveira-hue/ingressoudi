-- =============================================================================
-- Ingressoudi - CRM comercial: kanban, contatos e historico do lead
-- 1) crm_contatos: cada conversa com o produtor (data, canal, resumo). Registrar
--    um contato atualiza o ultimo_contato do produtor.
-- 2) crm_mover_etapa: muda so a etapa (arrastar no kanban), com historico.
-- 3) crm_obter_produtor: linha do tempo das etapas e contatos de um produtor.
-- 4) crm_listar_produtores passa a trazer etapa_desde (quando entrou na etapa
--    atual), para mostrar os dias parados.
-- Tudo exige super admin, como o restante do CRM.
-- =============================================================================

create table public.crm_contatos (
  id uuid primary key default gen_random_uuid(),
  produtor_id uuid not null
    constraint fk_crm_contatos_produtor references public.crm_produtores (id) on delete cascade,
  data date not null,
  canal text not null,
  resumo text not null,
  usuario_id uuid null
    constraint fk_crm_contatos_usuario references public.usuarios (id) on delete set null,
  criado_em timestamptz not null default now(),
  constraint ck_crm_contatos_canal check (canal in ('WHATSAPP', 'INSTAGRAM', 'LIGACAO', 'REUNIAO', 'EMAIL', 'OUTRO')),
  constraint ck_crm_contatos_resumo check (btrim(resumo) <> '')
);

create index idx_crm_contatos_produtor on public.crm_contatos (produtor_id, data desc, criado_em desc);

alter table public.crm_contatos enable row level security;
revoke all on table public.crm_contatos from public, anon, authenticated;
grant select, insert, update, delete on table public.crm_contatos to service_role;

-- 1) Contatos -------------------------------------------------------------------------
create or replace function private.crm_registrar_contato(
  p_produtor_id uuid, p_data date, p_canal text, p_resumo text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_resumo text := nullif(btrim(p_resumo), '');
begin
  perform private.crm_exigir_super_admin();

  if not exists (select 1 from public.crm_produtores c where c.id = p_produtor_id) then
    raise exception 'Produtor % nao encontrado', p_produtor_id using errcode = '23503';
  end if;
  if p_data is null then
    raise exception 'Informe a data do contato' using errcode = '23514';
  end if;
  if p_canal is null or p_canal not in ('WHATSAPP', 'INSTAGRAM', 'LIGACAO', 'REUNIAO', 'EMAIL', 'OUTRO') then
    raise exception 'Canal invalido: %', p_canal using errcode = '23514';
  end if;
  if v_resumo is null then
    raise exception 'Escreva o que foi conversado' using errcode = '23514';
  end if;

  insert into public.crm_contatos (produtor_id, data, canal, resumo, usuario_id)
  values (p_produtor_id, p_data, p_canal, left(v_resumo, 2000), auth.uid())
  returning id into v_id;

  update public.crm_produtores c
     set ultimo_contato = greatest(coalesce(c.ultimo_contato, p_data), p_data)
   where c.id = p_produtor_id;

  return jsonb_build_object('id', v_id);
end;
$$;

create or replace function private.crm_excluir_contato(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_produtor uuid;
begin
  perform private.crm_exigir_super_admin();

  delete from public.crm_contatos k where k.id = p_id returning k.produtor_id into v_produtor;
  if v_produtor is null then
    raise exception 'Contato % nao encontrado', p_id using errcode = '23503';
  end if;

  -- O ultimo contato volta a ser o mais recente que sobrou (se houver algum).
  update public.crm_produtores c
     set ultimo_contato = coalesce(
           (select max(k.data) from public.crm_contatos k where k.produtor_id = v_produtor),
           c.ultimo_contato)
   where c.id = v_produtor;

  return jsonb_build_object('ok', true);
end;
$$;

-- 2) Mover de etapa (kanban) --------------------------------------------------------
create or replace function private.crm_mover_etapa(p_id uuid, p_etapa text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_atual text;
begin
  perform private.crm_exigir_super_admin();

  if private.crm_etapa_ordem(p_etapa) is null then
    raise exception 'Etapa invalida: %', p_etapa using errcode = '23514';
  end if;

  select c.etapa into v_atual from public.crm_produtores c where c.id = p_id for update;
  if not found then
    raise exception 'Produtor % nao encontrado', p_id using errcode = '23503';
  end if;

  if v_atual <> p_etapa then
    update public.crm_produtores c set etapa = p_etapa where c.id = p_id;
    insert into public.crm_historico (produtor_id, etapa_anterior, etapa_nova, usuario_id)
    values (p_id, v_atual, p_etapa, auth.uid());
  end if;

  return jsonb_build_object('id', p_id, 'etapa', p_etapa);
end;
$$;

-- 3) Historico de um produtor -----------------------------------------------------------
create or replace function private.crm_obter_produtor(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.crm_exigir_super_admin();

  if not exists (select 1 from public.crm_produtores c where c.id = p_id) then
    raise exception 'Produtor % nao encontrado', p_id using errcode = '23503';
  end if;

  return jsonb_build_object(
    'historico', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', h.id,
               'etapa_anterior', h.etapa_anterior,
               'etapa_nova', h.etapa_nova,
               'em', h.em,
               'por', u.nome
             ) order by h.em desc)
        from public.crm_historico h
        left join public.usuarios u on u.id = h.usuario_id
       where h.produtor_id = p_id), '[]'::jsonb),
    'contatos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', k.id,
               'data', k.data,
               'canal', k.canal,
               'resumo', k.resumo,
               'criado_em', k.criado_em,
               'por', u.nome
             ) order by k.data desc, k.criado_em desc)
        from public.crm_contatos k
        left join public.usuarios u on u.id = k.usuario_id
       where k.produtor_id = p_id), '[]'::jsonb)
  );
end;
$$;

-- 4) Lista com etapa_desde e total de contatos ----------------------------------------
create or replace function private.crm_listar_produtores()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.crm_exigir_super_admin();

  return coalesce((
    select jsonb_agg(
             jsonb_build_object(
               'id', c.id,
               'nome_produtor', c.nome_produtor,
               'empresa_evento', c.empresa_evento,
               'instagram', c.instagram,
               'whatsapp', c.whatsapp,
               'cidade', c.cidade,
               'tipo_evento', c.tipo_evento,
               'ultimo_contato', c.ultimo_contato,
               'etapa', c.etapa,
               'etapa_desde', coalesce((
                 select max(h.em) from public.crm_historico h
                  where h.produtor_id = c.id and h.etapa_nova = c.etapa), c.criado_em),
               'contatos', (select count(*) from public.crm_contatos k where k.produtor_id = c.id),
               'proxima_acao', c.proxima_acao,
               'proxima_acao_em', c.proxima_acao_em,
               'observacoes', c.observacoes,
               'organizacao_id', c.organizacao_id,
               'organizacao_nome', o.nome,
               'organizacao_slug', o.slug,
               'criado_em', c.criado_em,
               'atualizado_em', c.atualizado_em
             ) || case when c.organizacao_id is null
                       then jsonb_build_object('eventos_publicados', 0, 'ingressos_vendidos', 0, 'receita_gerada', 0)
                       else private.crm_numeros_casa(c.organizacao_id) end
             order by c.proxima_acao_em nulls last, c.atualizado_em desc)
      from public.crm_produtores c
      left join public.organizacoes o on o.id = c.organizacao_id
  ), '[]'::jsonb);
end;
$$;

-- Wrappers publicos -------------------------------------------------------------------
create or replace function public.crm_registrar_contato(p_produtor_id uuid, p_data date, p_canal text, p_resumo text)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.crm_registrar_contato(p_produtor_id, p_data, p_canal, p_resumo); $$;

create or replace function public.crm_excluir_contato(p_id uuid)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.crm_excluir_contato(p_id); $$;

create or replace function public.crm_mover_etapa(p_id uuid, p_etapa text)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.crm_mover_etapa(p_id, p_etapa); $$;

create or replace function public.crm_obter_produtor(p_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.crm_obter_produtor(p_id); $$;

revoke all on function private.crm_registrar_contato(uuid, date, text, text) from public, anon;
revoke all on function private.crm_excluir_contato(uuid) from public, anon;
revoke all on function private.crm_mover_etapa(uuid, text) from public, anon;
revoke all on function private.crm_obter_produtor(uuid) from public, anon;
revoke all on function public.crm_registrar_contato(uuid, date, text, text) from public, anon;
revoke all on function public.crm_excluir_contato(uuid) from public, anon;
revoke all on function public.crm_mover_etapa(uuid, text) from public, anon;
revoke all on function public.crm_obter_produtor(uuid) from public, anon;

grant execute on function private.crm_registrar_contato(uuid, date, text, text) to authenticated, service_role;
grant execute on function private.crm_excluir_contato(uuid) to authenticated, service_role;
grant execute on function private.crm_mover_etapa(uuid, text) to authenticated, service_role;
grant execute on function private.crm_obter_produtor(uuid) to authenticated, service_role;
grant execute on function public.crm_registrar_contato(uuid, date, text, text) to authenticated, service_role;
grant execute on function public.crm_excluir_contato(uuid) to authenticated, service_role;
grant execute on function public.crm_mover_etapa(uuid, text) to authenticated, service_role;
grant execute on function public.crm_obter_produtor(uuid) to authenticated, service_role;
