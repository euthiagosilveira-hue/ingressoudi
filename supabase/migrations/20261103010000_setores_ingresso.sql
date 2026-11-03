-- =============================================================================
-- Ingressoudi - Setores do evento (ex.: Pista e Camarote)
--
-- Cada evento passa a ter setores. Cada lote pertence a um setor e cada setor
-- tem o proprio lote ATIVO e a propria sequencia de lotes (virada por
-- esgotamento, por data, ativacao e encerramento manual ficam dentro do setor).
-- O estoque antecipado do evento continua sendo o limite geral.
--
--  * public.setores: nome e ordem por evento. Todo evento ganha o setor
--    "Ingresso" (os existentes nesta migracao, os novos por gatilho).
--  * lotes.setor_id: lote sem setor informado cai no primeiro setor do evento.
--    Indice "um lote ATIVO por evento" vira "um lote ATIVO por setor".
--  * criar_reserva ganha p_setor_id (padrao null = primeiro setor com lote
--    ativo), entao o app antigo em cache continua comprando.
--  * criar_lote_admin ganha p_setor_id; RPCs novas para criar, renomear e
--    excluir setor; listar_lotes_admin devolve os setores.
--  * Pagina publica: listar_setores_evento_publico (um cartao por setor).
--  * Portaria (QR e busca por nome) e ingressos do comprador: setor_nome.
--  * Painel do evento: vendas por setor. Pedidos, ingressos, checkout e venda
--    manual mostram "Setor · Lote" quando o evento tem mais de um setor.
--  * Com um setor so, tudo continua exatamente como antes.
--
-- Funcoes longas sao alteradas por troca de trecho (como em
-- 20261101010000_vendas_online_ate_3h_apos_inicio), para nao perder ajustes
-- anteriores; cada troca confere o texto esperado e aborta se nao achar.
-- =============================================================================

-- Troca um trecho no corpo de uma funcao e recria. Ja aplicada: nada a fazer.
create function pg_temp.trocar_trecho(p_funcao text, p_antigo text, p_novo text)
returns void
language plpgsql
as $$
declare
  v_def text;
begin
  v_def := pg_get_functiondef(p_funcao::regprocedure);
  v_def := replace(v_def, E'\r', '');
  -- o SQL Editor no Windows pode colar o script com CRLF
  p_antigo := replace(p_antigo, E'\r', '');
  p_novo := replace(p_novo, E'\r', '');
  if position(p_novo in v_def) > 0 then
    return;
  end if;
  if position(p_antigo in v_def) = 0 then
    raise exception '% nao tem o texto esperado; migracao abortada', p_funcao;
  end if;
  execute replace(v_def, p_antigo, p_novo);
end;
$$;

-- 1) TABELA DE SETORES -------------------------------------------------------------
create table if not exists public.setores (
  id uuid
    constraint pk_setores primary key default gen_random_uuid(),
  evento_id uuid not null
    constraint fk_setores_evento references public.eventos (id) on delete restrict,
  organizacao_id uuid not null
    constraint fk_setores_organizacao references public.organizacoes (id) on delete restrict,
  nome text not null,
  ordem integer not null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),

  constraint uq_setores_evento_ordem unique (evento_id, ordem),
  constraint chk_setores_ordem check (ordem > 0),
  constraint chk_setores_nome check (btrim(nome) <> '' and char_length(nome) <= 40)
);

create unique index if not exists uq_setores_evento_nome on public.setores (evento_id, lower(btrim(nome)));
create index if not exists idx_setores_organizacao on public.setores (organizacao_id);

alter table public.setores enable row level security;
revoke all privileges on table public.setores from anon, authenticated;

drop trigger if exists trg_setores_atualizado_em on public.setores;
create trigger trg_setores_atualizado_em
  before update on public.setores
  for each row execute function public.definir_atualizado_em();

drop trigger if exists trg_setores_organizacao on public.setores;
create trigger trg_setores_organizacao
  before insert or update of evento_id, organizacao_id on public.setores
  for each row execute function private.definir_organizacao_por_evento();

-- Setor padrao de todo evento existente
insert into public.setores (evento_id, nome, ordem)
select e.id, 'Ingresso', 1
  from public.eventos e
 where not exists (select 1 from public.setores s where s.evento_id = e.id);

-- Evento novo nasce com o setor padrao
create or replace function private.criar_setor_padrao_evento()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  insert into public.setores (evento_id, nome, ordem) values (new.id, 'Ingresso', 1);
  return new;
end;
$$;

revoke all on function private.criar_setor_padrao_evento() from public, anon, authenticated;

drop trigger if exists trg_eventos_setor_padrao on public.eventos;
create trigger trg_eventos_setor_padrao
  after insert on public.eventos
  for each row execute function private.criar_setor_padrao_evento();

-- 2) LOTE PERTENCE A UM SETOR -------------------------------------------------------
alter table public.lotes add column if not exists setor_id uuid
  constraint fk_lotes_setor references public.setores (id) on delete restrict;

-- preenche sem mexer no atualizado_em dos lotes
alter table public.lotes disable trigger trg_lotes_atualizado_em;
update public.lotes l
   set setor_id = (select s.id from public.setores s where s.evento_id = l.evento_id order by s.ordem limit 1)
 where l.setor_id is null;
alter table public.lotes enable trigger trg_lotes_atualizado_em;

alter table public.lotes alter column setor_id set not null;
create index if not exists idx_lotes_setor on public.lotes (setor_id);

-- Lote sem setor cai no primeiro setor do evento; setor precisa ser do evento.
create or replace function private.definir_setor_lote()
returns trigger
language plpgsql
set search_path to ''
as $$
declare
  v_evento_setor uuid;
begin
  if new.setor_id is null then
    select s.id into new.setor_id
      from public.setores s
     where s.evento_id = new.evento_id
     order by s.ordem
     limit 1;
    if new.setor_id is null then
      raise exception 'Evento % sem setor', new.evento_id using errcode = '23503';
    end if;
  end if;

  select s.evento_id into v_evento_setor from public.setores s where s.id = new.setor_id;
  if v_evento_setor is null or v_evento_setor <> new.evento_id then
    raise exception 'Setor % nao pertence ao evento %', new.setor_id, new.evento_id using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function private.definir_setor_lote() from public, anon, authenticated;

drop trigger if exists trg_lotes_setor on public.lotes;
create trigger trg_lotes_setor
  before insert or update of evento_id, setor_id on public.lotes
  for each row execute function private.definir_setor_lote();

-- Um lote ATIVO por setor (antes: por evento)
drop index if exists public.uq_lotes_evento_ativo;
create unique index if not exists uq_lotes_setor_ativo on public.lotes (setor_id) where status = 'ATIVO';

-- 3) AJUDANTES ---------------------------------------------------------------------
-- O evento tem mais de um setor (so entao o setor aparece para comprador/portaria).
create or replace function private.evento_tem_setores(p_evento_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select (select count(*) from public.setores s where s.evento_id = p_evento_id) > 1;
$$;

-- "Camarote · 1º lote" quando ha setores; senao so o nome do lote.
create or replace function private.nome_lote_exibicao(p_lote_id uuid)
returns text
language sql
stable
security definer
set search_path to ''
as $$
  select case when private.evento_tem_setores(l.evento_id) then s.nome || ' · ' || l.nome else l.nome end
    from public.lotes l
    join public.setores s on s.id = l.setor_id
   where l.id = p_lote_id;
$$;

-- Setor do ingresso para portaria e comprador (null quando o evento tem um setor so).
create or replace function private.setor_nome_ingresso(p_ingresso_id uuid)
returns text
language sql
stable
security definer
set search_path to ''
as $$
  select s.nome
    from public.ingressos i
    join public.lotes l on l.id = i.lote_id
    join public.setores s on s.id = l.setor_id
   where i.id = p_ingresso_id
     and private.evento_tem_setores(i.evento_id);
$$;

revoke all on function private.evento_tem_setores(uuid) from public, anon, authenticated;
revoke all on function private.nome_lote_exibicao(uuid) from public, anon, authenticated;
revoke all on function private.setor_nome_ingresso(uuid) from public, anon, authenticated;

-- 4) RESERVA ONLINE ESCOLHE O SETOR --------------------------------------------------
do $$
declare
  v_def text;
  v_lote_antigo text := $q$  select * into v_lote
    from public.lotes l
   where l.evento_id = p_evento_id
     and l.status = 'ATIVO'
   for update;$q$;
  v_lote_novo text := $q$  if p_setor_id is not null and not exists (
    select 1 from public.setores s where s.id = p_setor_id and s.evento_id = p_evento_id
  ) then
    raise exception 'Setor % nao encontrado no evento %', p_setor_id, p_evento_id using errcode = '23503';
  end if;

  -- [setores] um lote ATIVO por setor; sem setor informado, o primeiro setor com lote ativo
  select l.* into v_lote
    from public.lotes l
    join public.setores s on s.id = l.setor_id
   where l.evento_id = p_evento_id
     and l.status = 'ATIVO'
     and (p_setor_id is null or l.setor_id = p_setor_id)
   order by s.ordem
   limit 1
   for update of l;$q$;
  v_retorno_antigo text := $q$    'lote_id', v_lote.id,
$q$;
  v_retorno_novo text := $q$    'lote_id', v_lote.id,
    'setor_id', v_lote.setor_id,
$q$;
begin
  if to_regprocedure('private.criar_reserva(uuid,text,text,text,text[],boolean[],uuid)') is not null then
    return;
  end if;

  v_def := pg_get_functiondef('private.criar_reserva(uuid,text,text,text,text[],boolean[])'::regprocedure);
  v_def := replace(v_def, E'\r', '');
  -- o SQL Editor no Windows pode colar o script com CRLF
  v_lote_antigo := replace(v_lote_antigo, E'\r', '');
  v_lote_novo := replace(v_lote_novo, E'\r', '');
  v_retorno_antigo := replace(v_retorno_antigo, E'\r', '');
  v_retorno_novo := replace(v_retorno_novo, E'\r', '');

  if position('p_meias boolean[] DEFAULT NULL::boolean[])' in v_def) = 0
     or position(v_lote_antigo in v_def) = 0
     or position(v_retorno_antigo in v_def) = 0 then
    raise exception 'criar_reserva nao tem o texto esperado; migracao abortada';
  end if;

  v_def := replace(v_def,
    'p_meias boolean[] DEFAULT NULL::boolean[])',
    'p_meias boolean[] DEFAULT NULL::boolean[], p_setor_id uuid DEFAULT NULL::uuid)');
  v_def := replace(v_def, v_lote_antigo, v_lote_novo);
  v_def := replace(v_def, v_retorno_antigo, v_retorno_novo);

  execute v_def;
end;
$$;

drop function if exists public.criar_reserva(uuid, text, text, text, text[], boolean[]);
drop function if exists private.criar_reserva(uuid, text, text, text, text[], boolean[]);

create or replace function public.criar_reserva(
  p_evento_id uuid,
  p_comprador_nome text,
  p_comprador_telefone text,
  p_comprador_email text default null,
  p_nomes_participantes text[] default null,
  p_meias boolean[] default null,
  p_setor_id uuid default null
)
returns jsonb
language sql
set search_path to ''
as $$ select private.criar_reserva(p_evento_id, p_comprador_nome, p_comprador_telefone, p_comprador_email, p_nomes_participantes, p_meias, p_setor_id); $$;

revoke all on function private.criar_reserva(uuid, text, text, text, text[], boolean[], uuid) from public;
grant execute on function private.criar_reserva(uuid, text, text, text, text[], boolean[], uuid) to anon, authenticated, service_role;
revoke all on function public.criar_reserva(uuid, text, text, text, text[], boolean[], uuid) from public;
grant execute on function public.criar_reserva(uuid, text, text, text, text[], boolean[], uuid) to anon, authenticated, service_role;

-- 5) VIRADA DE LOTE DENTRO DO SETOR ---------------------------------------------------
create or replace function private.processar_virada_lote_esgotamento_setor(p_setor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_setor public.setores%rowtype;
  v_evento public.eventos%rowtype;
  v_ativo public.lotes%rowtype;
  v_prox public.lotes%rowtype;
  v_disp_lote integer;
  v_disp_evento integer;
  v_pagos integer;
  v_ts timestamptz := now();
begin
  select * into v_setor from public.setores s where s.id = p_setor_id;
  if not found then
    raise exception 'Setor % nao encontrado', p_setor_id using errcode = '23503';
  end if;

  select * into v_evento from public.eventos e where e.id = v_setor.evento_id for update;
  if v_evento.status = 'CANCELADO' then
    return jsonb_build_object('resultado', 'EVENTO_CANCELADO');
  end if;
  if v_evento.status = 'REALIZADO' then
    return jsonb_build_object('resultado', 'EVENTO_REALIZADO');
  end if;

  select * into v_ativo from public.lotes l
   where l.setor_id = p_setor_id and l.status = 'ATIVO' for update;
  if not found then
    return jsonb_build_object('resultado', 'SEM_LOTE_ATIVO', 'setor_id', p_setor_id);
  end if;

  v_disp_lote := private.calcular_disponibilidade_lote(v_ativo.id);
  if v_disp_lote > 0 then
    return jsonb_build_object('resultado', 'SEM_VIRADA', 'disponibilidade_lote', v_disp_lote, 'setor_id', p_setor_id);
  end if;

  v_disp_evento := private.calcular_disponibilidade_evento(v_evento.id);
  if v_disp_evento <= 0 then
    return jsonb_build_object('resultado', 'ESTOQUE_EVENTO_ESGOTADO', 'setor_id', p_setor_id);
  end if;

  select * into v_prox from public.lotes l
   where l.setor_id = p_setor_id and l.status = 'INATIVO' and l.tipo_ativacao = 'ESGOTAMENTO'
     and l.ordem > v_ativo.ordem
   order by l.ordem asc limit 1 for update;

  if not found then
    -- Sem proximo lote: reservas ainda nao pagas podem vencer e devolver
    -- ingressos. So encerra quando os ingressos PAGOS preenchem o lote.
    select count(*) into v_pagos
      from public.ingressos i
     where i.lote_id = v_ativo.id and i.status in ('VALIDO', 'UTILIZADO');

    if v_pagos < v_ativo.quantidade then
      return jsonb_build_object('resultado', 'ESGOTADO_TEMPORARIO', 'lote_id', v_ativo.id,
                                'pagos', v_pagos, 'quantidade', v_ativo.quantidade, 'setor_id', p_setor_id);
    end if;

    update public.lotes set status = 'ENCERRADO', encerrado_em = v_ts where id = v_ativo.id;
    return jsonb_build_object('resultado', 'ESGOTADO_SEM_PROXIMO_LOTE', 'lote_encerrado_id', v_ativo.id, 'setor_id', p_setor_id);
  end if;

  update public.lotes set status = 'ENCERRADO', encerrado_em = v_ts where id = v_ativo.id;
  update public.lotes set status = 'ATIVO', ativado_em = v_ts, encerrado_em = null where id = v_prox.id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values (null, 'LOTE_VIRADO_POR_ESGOTAMENTO', 'lotes', v_prox.id,
    jsonb_build_object('lote_anterior_id', v_ativo.id, 'lote_anterior_ordem', v_ativo.ordem),
    jsonb_build_object('lote_novo_id', v_prox.id, 'lote_novo_ordem', v_prox.ordem, 'ativado_em', v_ts, 'setor_id', p_setor_id));

  return jsonb_build_object('resultado', 'VIRADO', 'lote_anterior_id', v_ativo.id, 'lote_novo_id', v_prox.id,
                            'lote_novo_ordem', v_prox.ordem, 'setor_id', p_setor_id);
end;
$$;

-- Evento: processa cada setor com lote ativo. Com um setor so, devolve o mesmo
-- resultado de antes; com varios, {resultado: POR_SETOR, setores: [...]}.
create or replace function private.processar_virada_lote_esgotamento(p_evento_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_evento public.eventos%rowtype;
  v_rec record;
  v_lista jsonb := '[]'::jsonb;
begin
  select * into v_evento from public.eventos e where e.id = p_evento_id for update;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if v_evento.status = 'CANCELADO' then
    return jsonb_build_object('resultado', 'EVENTO_CANCELADO');
  end if;
  if v_evento.status = 'REALIZADO' then
    return jsonb_build_object('resultado', 'EVENTO_REALIZADO');
  end if;

  for v_rec in
    select s.id
      from public.setores s
     where s.evento_id = p_evento_id
       and exists (select 1 from public.lotes l where l.setor_id = s.id and l.status = 'ATIVO')
     order by s.ordem
  loop
    v_lista := v_lista || jsonb_build_array(private.processar_virada_lote_esgotamento_setor(v_rec.id));
  end loop;

  if jsonb_array_length(v_lista) = 0 then
    return jsonb_build_object('resultado', 'SEM_LOTE_ATIVO');
  end if;
  if jsonb_array_length(v_lista) = 1 then
    return v_lista->0;
  end if;
  return jsonb_build_object('resultado', 'POR_SETOR', 'setores', v_lista);
end;
$$;

create or replace function private.processar_viradas_lote_por_data(p_evento_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_rec record;
  v_evento public.eventos%rowtype;
  v_ativo public.lotes%rowtype;
  v_cand public.lotes%rowtype;
  v_ordem_ref integer;
  v_ts timestamptz;
  v_viradas jsonb := '[]'::jsonb;
begin
  for v_rec in
    select distinct l.evento_id, l.setor_id
      from public.lotes l
     where l.status = 'INATIVO' and l.tipo_ativacao = 'DATA_HORA' and l.ativacao_em <= now()
       and (p_evento_id is null or l.evento_id = p_evento_id)
  loop
    select * into v_evento from public.eventos e where e.id = v_rec.evento_id for update;
    if v_evento.status in ('CANCELADO', 'REALIZADO') then
      continue;
    end if;

    v_ativo := null;
    select * into v_ativo from public.lotes l
     where l.setor_id = v_rec.setor_id and l.status = 'ATIVO' for update;
    v_ordem_ref := coalesce(v_ativo.ordem, 0);

    select * into v_cand from public.lotes l
     where l.setor_id = v_rec.setor_id and l.status = 'INATIVO' and l.tipo_ativacao = 'DATA_HORA'
       and l.ativacao_em <= now() and l.ordem > v_ordem_ref
     order by l.ordem desc limit 1 for update;
    if not found then
      continue;
    end if;

    v_ts := now();
    if v_ativo.id is not null then
      update public.lotes set status = 'ENCERRADO', encerrado_em = v_ts where id = v_ativo.id;
    end if;
    update public.lotes set status = 'ATIVO', ativado_em = v_ts, encerrado_em = null where id = v_cand.id;

    insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
    values (null, 'LOTE_VIRADO_POR_DATA', 'lotes', v_cand.id,
      jsonb_build_object('lote_anterior_id', v_ativo.id, 'lote_anterior_ordem', v_ativo.ordem),
      jsonb_build_object('lote_novo_id', v_cand.id, 'lote_novo_ordem', v_cand.ordem, 'ativado_em', v_ts, 'setor_id', v_rec.setor_id));

    v_viradas := v_viradas || jsonb_build_object('evento_id', v_rec.evento_id, 'setor_id', v_rec.setor_id,
                                                 'lote_anterior_id', v_ativo.id, 'lote_novo_id', v_cand.id);
  end loop;

  return jsonb_build_object('viradas', v_viradas, 'total', jsonb_array_length(v_viradas));
end;
$$;

revoke all on function private.processar_virada_lote_esgotamento_setor(uuid) from public, anon, authenticated;
grant execute on function private.processar_virada_lote_esgotamento_setor(uuid) to service_role;

-- Ativar / encerrar lote manualmente: o outro lote afetado e o do mesmo setor
select pg_temp.trocar_trecho('private.ativar_lote_manual(uuid)',
  'where l.evento_id = v_lote.evento_id and l.status = ''ATIVO'' and l.id <> v_lote.id for update;',
  'where l.setor_id = v_lote.setor_id and l.status = ''ATIVO'' and l.id <> v_lote.id for update;');

select pg_temp.trocar_trecho('private.encerrar_lote_admin(uuid,boolean)',
  'where l.evento_id = v_lote.evento_id and l.status = ''INATIVO'' and l.ordem > v_lote.ordem',
  'where l.setor_id = v_lote.setor_id and l.status = ''INATIVO'' and l.ordem > v_lote.ordem');

-- Encerrar o evento encerra o lote ativo de todos os setores
select pg_temp.trocar_trecho('private.encerrar_evento(uuid)',
  'update public.lotes set status = ''ENCERRADO'', encerrado_em = v_ts where id = v_lote.id;',
  'update public.lotes set status = ''ENCERRADO'', encerrado_em = v_ts where evento_id = p_evento_id and status = ''ATIVO'';');

-- 6) SITUACAO DE VENDA ------------------------------------------------------------------
-- Evento: disponivel quando algum setor tem lote ativo com ingressos.
create or replace function private.calcular_situacao_venda(p_evento_id uuid)
returns text
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_e public.eventos%rowtype;
begin
  select * into v_e from public.eventos e where e.id = p_evento_id;
  if not found then
    return null;
  end if;

  if v_e.status = 'CANCELADO' then
    return 'CANCELADO';
  end if;
  if v_e.status = 'REALIZADO' then
    return 'ENCERRADO';
  end if;

  -- Passou o prazo da venda online (ou o produtor encerrou as vendas).
  if v_e.vendas_status <> 'ABERTAS' or now() >= private.fim_vendas_online(v_e.inicio_em) then
    if v_e.status = 'EM_ANDAMENTO' then
      return 'EVENTO_EM_ANDAMENTO';
    end if;
    return 'VENDAS_ENCERRADAS';
  end if;

  if not exists (select 1 from public.lotes l where l.evento_id = v_e.id and l.status = 'ATIVO') then
    return 'SEM_LOTE';
  end if;

  if private.calcular_disponibilidade_evento(v_e.id) <= 0 then
    return 'ESGOTADO';
  end if;

  if exists (
    select 1 from public.lotes l
     where l.evento_id = v_e.id and l.status = 'ATIVO'
       and private.calcular_disponibilidade_lote(l.id) > 0
  ) then
    return 'DISPONIVEL';
  end if;

  return 'ESGOTADO';
end;
$$;

-- Setor: mesma regra, olhando so o lote ativo do setor.
create or replace function private.calcular_situacao_setor(p_setor_id uuid)
returns text
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_evento_id uuid;
  v_situacao text;
  v_lote_id uuid;
begin
  select s.evento_id into v_evento_id from public.setores s where s.id = p_setor_id;
  if v_evento_id is null then
    return null;
  end if;

  v_situacao := private.calcular_situacao_venda(v_evento_id);
  if v_situacao not in ('DISPONIVEL', 'ESGOTADO') then
    return v_situacao;
  end if;

  select l.id into v_lote_id from public.lotes l where l.setor_id = p_setor_id and l.status = 'ATIVO';
  if v_lote_id is null then
    return 'SEM_LOTE';
  end if;

  if private.calcular_disponibilidade_evento(v_evento_id) <= 0
     or private.calcular_disponibilidade_lote(v_lote_id) <= 0 then
    return 'ESGOTADO';
  end if;

  return 'DISPONIVEL';
end;
$$;

revoke all on function private.calcular_situacao_setor(uuid) from public, anon, authenticated;

-- Vitrine e pagina do evento: com varios setores, mostra o menor preco ("a partir de")
select pg_temp.trocar_trecho('private.listar_eventos_publicos()',
  E'     where lo.evento_id = e.id and lo.status = ''ATIVO''\n     limit 1',
  E'     where lo.evento_id = e.id and lo.status = ''ATIVO''\n     order by lo.preco asc\n     limit 1');
select pg_temp.trocar_trecho('private.listar_eventos_publicos_organizacao(text)',
  E'     where lo.evento_id = e.id and lo.status = ''ATIVO''\n     limit 1',
  E'     where lo.evento_id = e.id and lo.status = ''ATIVO''\n     order by lo.preco asc\n     limit 1');
select pg_temp.trocar_trecho('private.obter_evento_publico(text)',
  E'     where lo.evento_id = e.id and lo.status = ''ATIVO''\n     limit 1',
  E'     where lo.evento_id = e.id and lo.status = ''ATIVO''\n     order by lo.preco asc\n     limit 1');
select pg_temp.trocar_trecho('private.obter_evento_publico_organizacao(text,text)',
  E'     where lo.evento_id = e.id and lo.status = ''ATIVO''\n     limit 1',
  E'     where lo.evento_id = e.id and lo.status = ''ATIVO''\n     order by lo.preco asc\n     limit 1');

-- 7) PAGINA PUBLICA: SETORES DO EVENTO ------------------------------------------------
-- Um item por setor que tem lote cadastrado, com o lote ativo e a situacao.
create or replace function private.listar_setores_evento_publico(p_org_slug text, p_evento_slug text)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'setor_id', s.id,
             'nome', s.nome,
             'ordem', s.ordem,
             'lote_id', la.id,
             'lote_nome', la.nome,
             'preco', la.preco,
             'situacao_venda', private.calcular_situacao_setor(s.id)
           ) order by s.ordem), '[]'::jsonb)
    from public.eventos e
    join public.organizacoes o on o.id = e.organizacao_id
    join public.setores s on s.evento_id = e.id
    left join lateral (
      select l.id, l.nome, l.preco from public.lotes l
       where l.setor_id = s.id and l.status = 'ATIVO'
       limit 1
    ) la on true
   where o.slug = lower(btrim(coalesce(p_org_slug, '')))
     and o.ativo
     and o.aprovada
     and e.slug = lower(btrim(coalesce(p_evento_slug, '')))
     and e.publicacao_status = 'PUBLICADO'
     and exists (select 1 from public.lotes l where l.setor_id = s.id);
$$;

create or replace function public.listar_setores_evento_publico(p_org_slug text, p_evento_slug text)
returns jsonb
language sql
stable
set search_path to ''
as $$ select private.listar_setores_evento_publico(p_org_slug, p_evento_slug); $$;

revoke all on function private.listar_setores_evento_publico(text, text) from public;
grant execute on function private.listar_setores_evento_publico(text, text) to anon, authenticated, service_role;
revoke all on function public.listar_setores_evento_publico(text, text) from public;
grant execute on function public.listar_setores_evento_publico(text, text) to anon, authenticated, service_role;

-- 8) PAINEL DO PRODUTOR: SETORES E LOTES --------------------------------------------
create or replace function private.listar_setores_admin_json(p_evento_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'setor_id', s.id,
             'nome', s.nome,
             'ordem', s.ordem,
             'total_lotes', (select count(*) from public.lotes l where l.setor_id = s.id),
             'quantidade', (select coalesce(sum(l.quantidade), 0) from public.lotes l where l.setor_id = s.id),
             'vendidos', (
               select count(*) from public.ingressos i join public.lotes l on l.id = i.lote_id
                where l.setor_id = s.id and i.status in ('VALIDO', 'UTILIZADO')
             )
           ) order by s.ordem), '[]'::jsonb)
    from public.setores s
   where s.evento_id = p_evento_id;
$$;

revoke all on function private.listar_setores_admin_json(uuid) from public, anon, authenticated;

select pg_temp.trocar_trecho('private.listar_lotes_admin(uuid)',
  E'               ''lote_id'', l.id,\n',
  E'               ''lote_id'', l.id,\n               ''setor_id'', l.setor_id,\n');
select pg_temp.trocar_trecho('private.listar_lotes_admin(uuid)',
  'return jsonb_build_object(''evento'', v_evento, ''lotes'', v_lotes);',
  'return jsonb_build_object(''evento'', v_evento, ''lotes'', v_lotes, ''setores'', private.listar_setores_admin_json(p_evento_id));');

-- Valida acesso do administrador ao evento e se ele ainda aceita mudancas.
create or replace function private.validar_evento_setor_admin(p_evento_id uuid)
returns void
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_status public.status_evento;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;
  if p_evento_id is null or not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;
  select e.status into v_status from public.eventos e where e.id = p_evento_id;
  if v_status in ('REALIZADO', 'CANCELADO') then
    raise exception 'Evento % nao permite alterar setores (status=%)', p_evento_id, v_status using errcode = '23514';
  end if;
end;
$$;

create or replace function private.normalizar_nome_setor(p_nome text)
returns text
language plpgsql
immutable
set search_path to ''
as $$
declare
  v_nome text := regexp_replace(btrim(coalesce(p_nome, '')), '\s+', ' ', 'g');
begin
  if v_nome = '' then
    raise exception 'Informe o nome do setor' using errcode = '23514';
  end if;
  if char_length(v_nome) > 40 then
    raise exception 'Nome do setor muito longo (maximo 40 caracteres)' using errcode = '23514';
  end if;
  return v_nome;
end;
$$;

revoke all on function private.validar_evento_setor_admin(uuid) from public, anon, authenticated;
revoke all on function private.normalizar_nome_setor(text) from public, anon, authenticated;

create or replace function private.criar_setor_admin(p_evento_id uuid, p_nome text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_nome text;
  v_ordem integer;
  v_id uuid;
begin
  perform private.validar_evento_setor_admin(p_evento_id);
  v_nome := private.normalizar_nome_setor(p_nome);

  perform 1 from public.eventos e where e.id = p_evento_id for update;

  if exists (select 1 from public.setores s where s.evento_id = p_evento_id and lower(s.nome) = lower(v_nome)) then
    raise exception 'Ja existe um setor com esse nome' using errcode = '23505';
  end if;
  if (select count(*) from public.setores s where s.evento_id = p_evento_id) >= 10 then
    raise exception 'Limite de 10 setores por evento' using errcode = '23514';
  end if;

  select coalesce(max(s.ordem), 0) + 1 into v_ordem from public.setores s where s.evento_id = p_evento_id;

  insert into public.setores (evento_id, nome, ordem) values (p_evento_id, v_nome, v_ordem)
  returning id into v_id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos)
  values (auth.uid(), 'SETOR_CRIADO_ADMIN', 'setores', v_id,
          jsonb_build_object('evento_id', p_evento_id, 'nome', v_nome, 'ordem', v_ordem));

  return jsonb_build_object('setor_id', v_id, 'evento_id', p_evento_id, 'nome', v_nome, 'ordem', v_ordem);
end;
$$;

create or replace function private.renomear_setor_admin(p_setor_id uuid, p_nome text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_setor public.setores%rowtype;
  v_nome text;
begin
  select * into v_setor from public.setores s where s.id = p_setor_id for update;
  if not found then
    raise exception 'Setor % nao encontrado', p_setor_id using errcode = '23503';
  end if;
  perform private.validar_evento_setor_admin(v_setor.evento_id);
  v_nome := private.normalizar_nome_setor(p_nome);

  if exists (select 1 from public.setores s
              where s.evento_id = v_setor.evento_id and s.id <> v_setor.id and lower(s.nome) = lower(v_nome)) then
    raise exception 'Ja existe um setor com esse nome' using errcode = '23505';
  end if;

  update public.setores set nome = v_nome where id = v_setor.id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values (auth.uid(), 'SETOR_RENOMEADO_ADMIN', 'setores', v_setor.id,
          jsonb_build_object('nome', v_setor.nome), jsonb_build_object('nome', v_nome));

  return jsonb_build_object('setor_id', v_setor.id, 'nome', v_nome);
end;
$$;

-- So exclui setor sem lotes; o evento sempre fica com pelo menos um setor.
create or replace function private.excluir_setor_admin(p_setor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_setor public.setores%rowtype;
begin
  select * into v_setor from public.setores s where s.id = p_setor_id for update;
  if not found then
    raise exception 'Setor % nao encontrado', p_setor_id using errcode = '23503';
  end if;
  perform private.validar_evento_setor_admin(v_setor.evento_id);

  if exists (select 1 from public.lotes l where l.setor_id = v_setor.id) then
    raise exception 'Setor com lotes nao pode ser excluido' using errcode = '23514';
  end if;
  if (select count(*) from public.setores s where s.evento_id = v_setor.evento_id) <= 1 then
    raise exception 'O evento precisa de pelo menos um setor' using errcode = '23514';
  end if;

  delete from public.setores where id = v_setor.id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores)
  values (auth.uid(), 'SETOR_EXCLUIDO_ADMIN', 'setores', v_setor.id,
          jsonb_build_object('evento_id', v_setor.evento_id, 'nome', v_setor.nome));

  return jsonb_build_object('setor_id', v_setor.id, 'resultado', 'EXCLUIDO');
end;
$$;

create or replace function public.criar_setor_admin(p_evento_id uuid, p_nome text)
returns jsonb language sql set search_path to ''
as $$ select private.criar_setor_admin(p_evento_id, p_nome); $$;
create or replace function public.renomear_setor_admin(p_setor_id uuid, p_nome text)
returns jsonb language sql set search_path to ''
as $$ select private.renomear_setor_admin(p_setor_id, p_nome); $$;
create or replace function public.excluir_setor_admin(p_setor_id uuid)
returns jsonb language sql set search_path to ''
as $$ select private.excluir_setor_admin(p_setor_id); $$;

revoke all on function private.criar_setor_admin(uuid, text) from public, anon;
revoke all on function private.renomear_setor_admin(uuid, text) from public, anon;
revoke all on function private.excluir_setor_admin(uuid) from public, anon;
revoke all on function public.criar_setor_admin(uuid, text) from public, anon;
revoke all on function public.renomear_setor_admin(uuid, text) from public, anon;
revoke all on function public.excluir_setor_admin(uuid) from public, anon;
grant execute on function private.criar_setor_admin(uuid, text) to authenticated, service_role;
grant execute on function private.renomear_setor_admin(uuid, text) to authenticated, service_role;
grant execute on function private.excluir_setor_admin(uuid) to authenticated, service_role;
grant execute on function public.criar_setor_admin(uuid, text) to authenticated, service_role;
grant execute on function public.renomear_setor_admin(uuid, text) to authenticated, service_role;
grant execute on function public.excluir_setor_admin(uuid) to authenticated, service_role;

-- Criar lote no setor escolhido (null = primeiro setor do evento)
do $$
declare
  v_def text;
begin
  if to_regprocedure('private.criar_lote_admin(uuid,text,integer,numeric,tipo_ativacao_lote,timestamptz,uuid)') is not null then
    return;
  end if;

  v_def := pg_get_functiondef('private.criar_lote_admin(uuid,text,integer,numeric,tipo_ativacao_lote,timestamptz)'::regprocedure);
  v_def := replace(v_def, E'\r', '');

  if position('p_ativacao_em timestamp with time zone DEFAULT NULL::timestamp with time zone)' in v_def) = 0
     or position('insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, ativacao_em, status)' in v_def) = 0
     or position('values (p_evento_id, btrim(p_nome), v_ordem, p_quantidade, p_preco, p_tipo_ativacao, v_ativacao, ''INATIVO'')' in v_def) = 0
     or position(E'      ''tipo_ativacao'', p_tipo_ativacao,\n' in v_def) = 0 then
    raise exception 'criar_lote_admin nao tem o texto esperado; migracao abortada';
  end if;

  v_def := replace(v_def,
    'p_ativacao_em timestamp with time zone DEFAULT NULL::timestamp with time zone)',
    'p_ativacao_em timestamp with time zone DEFAULT NULL::timestamp with time zone, p_setor_id uuid DEFAULT NULL::uuid)');
  v_def := replace(v_def,
    'insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, ativacao_em, status)',
    'insert into public.lotes (evento_id, setor_id, nome, ordem, quantidade, preco, tipo_ativacao, ativacao_em, status)');
  v_def := replace(v_def,
    'values (p_evento_id, btrim(p_nome), v_ordem, p_quantidade, p_preco, p_tipo_ativacao, v_ativacao, ''INATIVO'')',
    'values (p_evento_id, p_setor_id, btrim(p_nome), v_ordem, p_quantidade, p_preco, p_tipo_ativacao, v_ativacao, ''INATIVO'')');
  v_def := replace(v_def,
    E'      ''tipo_ativacao'', p_tipo_ativacao,\n',
    E'      ''tipo_ativacao'', p_tipo_ativacao,\n      ''setor_id'', p_setor_id,\n');

  execute v_def;
end;
$$;

drop function if exists public.criar_lote_admin(uuid, text, integer, numeric, public.tipo_ativacao_lote, timestamptz);
drop function if exists private.criar_lote_admin(uuid, text, integer, numeric, public.tipo_ativacao_lote, timestamptz);

create or replace function public.criar_lote_admin(
  p_evento_id uuid,
  p_nome text,
  p_quantidade integer,
  p_preco numeric,
  p_tipo_ativacao public.tipo_ativacao_lote,
  p_ativacao_em timestamptz default null,
  p_setor_id uuid default null
)
returns jsonb
language sql
set search_path to ''
as $$
  select private.criar_lote_admin(p_evento_id, p_nome, p_quantidade, p_preco, p_tipo_ativacao, p_ativacao_em, p_setor_id);
$$;

revoke all on function private.criar_lote_admin(uuid, text, integer, numeric, public.tipo_ativacao_lote, timestamptz, uuid) from public, anon;
grant execute on function private.criar_lote_admin(uuid, text, integer, numeric, public.tipo_ativacao_lote, timestamptz, uuid) to authenticated, service_role;
revoke all on function public.criar_lote_admin(uuid, text, integer, numeric, public.tipo_ativacao_lote, timestamptz, uuid) from public, anon;
grant execute on function public.criar_lote_admin(uuid, text, integer, numeric, public.tipo_ativacao_lote, timestamptz, uuid) to authenticated, service_role;

-- 9) "SETOR · LOTE" ONDE O LOTE APARECE -------------------------------------------------
select pg_temp.trocar_trecho('private.listar_eventos_venda_manual_admin()',
  '''nome'', l.nome,', '''nome'', private.nome_lote_exibicao(l.id),');
select pg_temp.trocar_trecho('private.listar_ingressos_admin(uuid,uuid,text,status_ingresso)',
  '''lote_nome'', l.nome', '''lote_nome'', private.nome_lote_exibicao(l.id)');
select pg_temp.trocar_trecho('private.listar_pedidos_admin(uuid,text,status_pedido,status_pagamento,tipo_preco_pedido,timestamptz,timestamptz)',
  '''lote_nome'', l.nome,', '''lote_nome'', private.nome_lote_exibicao(l.id),');
select pg_temp.trocar_trecho('private.obter_checkout_pedido(uuid)',
  '''lote_nome'', v_lote.nome,', '''lote_nome'', private.nome_lote_exibicao(v_lote.id),');
select pg_temp.trocar_trecho('private.obter_ingresso_admin(uuid)',
  '''lote_nome'', v_lote.nome,', '''lote_nome'', private.nome_lote_exibicao(v_lote.id),');
select pg_temp.trocar_trecho('private.obter_pedido_admin(uuid)',
  '''lote_nome'', v_lote.nome,', '''lote_nome'', private.nome_lote_exibicao(v_lote.id),');

-- 10) PORTARIA E INGRESSOS DO COMPRADOR: SETOR DO INGRESSO ----------------------------
create or replace function private.anexar_meia_entrada(p_resultado jsonb)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  select p_resultado || jsonb_build_object(
    'meia',
    coalesce((
      select i.meia from public.ingressos i
       where i.id = nullif(p_resultado->>'ingresso_id', '')::uuid
    ), false),
    'setor_nome',
    private.setor_nome_ingresso(nullif(p_resultado->>'ingresso_id', '')::uuid)
  );
$$;

select pg_temp.trocar_trecho('private.buscar_ingressos_por_nome(uuid,text)',
  E'                 ''meia'', i.meia,\n',
  E'                 ''meia'', i.meia,\n                 ''setor_nome'', private.setor_nome_ingresso(i.id),\n');
select pg_temp.trocar_trecho('private.montar_ingressos_pedido(uuid)',
  E'                 ''meia'', i.meia,\n',
  E'                 ''meia'', i.meia,\n                 ''setor_nome'', private.setor_nome_ingresso(i.id),\n');
select pg_temp.trocar_trecho('private.obter_ingressos_checkout(uuid)',
  E'                 ''meia'', i.meia,\n',
  E'                 ''meia'', i.meia,\n                 ''setor_nome'', private.setor_nome_ingresso(i.id),\n');

-- 11) PAINEL DO EVENTO: VENDAS POR SETOR ------------------------------------------------
create or replace function private.resumo_setores_evento(p_evento_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'setor_id', s.id,
             'nome', s.nome,
             'vendidos', x.vendidos,
             'utilizados', x.utilizados,
             'receita', x.receita,
             'capacidade', (select coalesce(sum(l.quantidade), 0) from public.lotes l where l.setor_id = s.id),
             'lote_atual', (
               select jsonb_build_object('nome', l.nome, 'preco', l.preco,
                                         'disponiveis', private.calcular_disponibilidade_lote(l.id))
                 from public.lotes l where l.setor_id = s.id and l.status = 'ATIVO'
             )
           ) order by s.ordem), '[]'::jsonb)
    from public.setores s
    cross join lateral (
      select count(*) filter (where i.status in ('VALIDO', 'UTILIZADO'))::int as vendidos,
             count(*) filter (where i.status = 'UTILIZADO')::int as utilizados,
             coalesce(sum(i.valor_unitario) filter (where i.status in ('VALIDO', 'UTILIZADO')), 0) as receita
        from public.ingressos i
        join public.lotes l on l.id = i.lote_id
       where l.setor_id = s.id
    ) x
   where s.evento_id = p_evento_id
     and exists (select 1 from public.lotes l where l.setor_id = s.id);
$$;

revoke all on function private.resumo_setores_evento(uuid) from public, anon, authenticated;

select pg_temp.trocar_trecho('private.obter_painel_evento_admin(uuid)',
  E'    ''extras'', jsonb_build_object(\n',
  E'    ''setores'', private.resumo_setores_evento(p_evento_id),\n    ''extras'', jsonb_build_object(\n');

-- 12) Registro da migracao (quem roda este arquivo direto no SQL Editor) ------------
do $$
begin
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    insert into supabase_migrations.schema_migrations (version, name)
    values ('20261103010000', 'setores_ingresso')
    on conflict (version) do nothing;
  end if;
end;
$$;
