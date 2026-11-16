-- =============================================================================
-- Ingressoudi - CPF/CNPJ do organizador + Contrato do Organizador com aceite
--
--  * organizacoes: tipo_documento (CPF/CNPJ), documento (so digitos, com digito
--    verificador conferido), responsavel_nome (nome completo ou razao social),
--    telefone e contrato_exigido.
--  * aceites_contrato_organizador: registro de cada aceite (casa, usuario,
--    versao, data/hora, IP, navegador). So aceita inclusao: nunca altera nem
--    exclui. Gravado pelo servidor (rota /api/contrato/aceitar, service role),
--    que e quem conhece o IP real.
--  * Casa com contrato pendente (dados incompletos ou sem aceite da versao
--    vigente) nao publica evento novo. Eventos ja publicados seguem vendendo.
--  * obter_sessao_operador devolve organizacao.contrato_pendente (o painel
--    leva o administrador para a tela de dados e aceite).
--  * obter_organizacao_publica devolve o organizador e o documento para
--    exibicao (CNPJ completo; CPF mascarado).
--  * concluir_cadastro_produtor ganha os dados do documento e do telefone.
--  * Super admin: obter_contrato_organizacao_plataforma (dados + aceites).
--
-- Versao vigente do contrato: private.contrato_organizador_versao(). Ao publicar
-- um texto novo, troque a versao aqui (nova migration) e em
-- app/utils/contratoOrganizador.ts: todas as casas aceitam de novo.
-- =============================================================================

-- 1) VALIDACAO DE CPF E CNPJ ---------------------------------------------------
create or replace function private.so_digitos(p_texto text)
returns text
language sql
immutable
set search_path = ''
as $$ select regexp_replace(coalesce(p_texto, ''), '[^0-9]', '', 'g'); $$;

create or replace function private.cpf_valido(p_cpf text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text := private.so_digitos(p_cpf);
  v_soma int;
  v_dv int;
  i int;
begin
  if length(v) <> 11 or v ~ '^(\d)\1{10}$' then
    return false;
  end if;
  v_soma := 0;
  for i in 1..9 loop
    v_soma := v_soma + substr(v, i, 1)::int * (11 - i);
  end loop;
  v_dv := (v_soma * 10) % 11;
  if v_dv = 10 then v_dv := 0; end if;
  if v_dv <> substr(v, 10, 1)::int then
    return false;
  end if;
  v_soma := 0;
  for i in 1..10 loop
    v_soma := v_soma + substr(v, i, 1)::int * (12 - i);
  end loop;
  v_dv := (v_soma * 10) % 11;
  if v_dv = 10 then v_dv := 0; end if;
  return v_dv = substr(v, 11, 1)::int;
end;
$$;

create or replace function private.cnpj_valido(p_cnpj text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text := private.so_digitos(p_cnpj);
  v_pesos1 int[] := array[5,4,3,2,9,8,7,6,5,4,3,2];
  v_pesos2 int[] := array[6,5,4,3,2,9,8,7,6,5,4,3,2];
  v_soma int;
  v_resto int;
  v_dv1 int;
  v_dv2 int;
  i int;
begin
  if length(v) <> 14 or v ~ '^(\d)\1{13}$' then
    return false;
  end if;
  v_soma := 0;
  for i in 1..12 loop
    v_soma := v_soma + substr(v, i, 1)::int * v_pesos1[i];
  end loop;
  v_resto := v_soma % 11;
  v_dv1 := case when v_resto < 2 then 0 else 11 - v_resto end;
  v_soma := 0;
  for i in 1..13 loop
    v_soma := v_soma + substr(v, i, 1)::int * v_pesos2[i];
  end loop;
  v_resto := v_soma % 11;
  v_dv2 := case when v_resto < 2 then 0 else 11 - v_resto end;
  return v_dv1 = substr(v, 13, 1)::int and v_dv2 = substr(v, 14, 1)::int;
end;
$$;

create or replace function private.documento_valido(p_tipo text, p_documento text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case p_tipo
           when 'CPF' then private.cpf_valido(p_documento)
           when 'CNPJ' then private.cnpj_valido(p_documento)
           else false
         end;
$$;

/** Documento para exibicao publica: CNPJ completo, CPF mascarado. */
create or replace function private.documento_exibicao(p_tipo text, p_documento text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
           when p_tipo = 'CNPJ' and length(p_documento) = 14 then
             substr(p_documento, 1, 2) || '.' || substr(p_documento, 3, 3) || '.' || substr(p_documento, 6, 3)
             || '/' || substr(p_documento, 9, 4) || '-' || substr(p_documento, 13, 2)
           when p_tipo = 'CPF' and length(p_documento) = 11 then
             '***.' || substr(p_documento, 4, 3) || '.' || substr(p_documento, 7, 3) || '-**'
           else null
         end;
$$;

revoke all on function private.so_digitos(text) from public;
revoke all on function private.cpf_valido(text) from public;
revoke all on function private.cnpj_valido(text) from public;
revoke all on function private.documento_valido(text, text) from public;
revoke all on function private.documento_exibicao(text, text) from public;
grant execute on function private.so_digitos(text) to authenticated, service_role;
grant execute on function private.cpf_valido(text) to authenticated, service_role;
grant execute on function private.cnpj_valido(text) to authenticated, service_role;
grant execute on function private.documento_valido(text, text) to authenticated, service_role;
grant execute on function private.documento_exibicao(text, text) to anon, authenticated, service_role;

-- 2) COLUNAS DA CASA -----------------------------------------------------------
alter table public.organizacoes
  add column tipo_documento text null,
  add column documento text null,
  add column responsavel_nome text null,
  add column telefone text null,
  add column contrato_exigido boolean not null default false;

alter table public.organizacoes
  add constraint ck_organizacoes_tipo_documento
    check (tipo_documento is null or tipo_documento in ('CPF', 'CNPJ')),
  add constraint ck_organizacoes_documento
    check ((tipo_documento is null and documento is null)
           or (tipo_documento is not null and private.documento_valido(tipo_documento, documento)
               and documento = private.so_digitos(documento))),
  add constraint ck_organizacoes_responsavel_nome
    check (responsavel_nome is null or btrim(responsavel_nome) <> ''),
  add constraint ck_organizacoes_telefone
    check (telefone is null or telefone ~ '^[0-9]{10,11}$');

-- Todas as casas que ja existem precisam completar os dados e aceitar.
-- Casas criadas pelo cadastro tambem (concluir_cadastro_produtor marca).
update public.organizacoes set contrato_exigido = true;

-- 3) VERSAO VIGENTE DO CONTRATO -----------------------------------------------
create or replace function private.contrato_organizador_versao()
returns text
language sql
immutable
set search_path = ''
as $$ select 'v1-2026-11'::text; $$;

revoke all on function private.contrato_organizador_versao() from public;
grant execute on function private.contrato_organizador_versao() to anon, authenticated, service_role;

-- 4) ACEITES ------------------------------------------------------------------
create table public.aceites_contrato_organizador (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  usuario_id uuid not null references public.usuarios (id) on delete restrict,
  versao text not null,
  aceito_em timestamptz not null default now(),
  ip text null,
  user_agent text null,
  -- Copia dos dados da casa no momento do aceite (prova do que foi declarado).
  tipo_documento text null,
  documento text null,
  responsavel_nome text null,
  telefone text null,
  constraint ck_aceites_versao check (btrim(versao) <> '')
);

create index idx_aceites_contrato_org on public.aceites_contrato_organizador (organizacao_id, aceito_em desc);

alter table public.aceites_contrato_organizador enable row level security;
revoke all on table public.aceites_contrato_organizador from public, anon, authenticated;
grant select, insert on table public.aceites_contrato_organizador to service_role;

create or replace function private.bloquear_alteracao_aceite()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Registro de aceite nao pode ser alterado nem excluido' using errcode = '42501';
end;
$$;

revoke all on function private.bloquear_alteracao_aceite() from public, anon, authenticated;

create trigger trg_aceites_contrato_imutavel
  before update or delete on public.aceites_contrato_organizador
  for each row execute function private.bloquear_alteracao_aceite();

-- 5) SITUACAO DO CONTRATO DA CASA ----------------------------------------------
create or replace function private.dados_organizador_completos(p_organizacao_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select o.tipo_documento is not null and o.documento is not null
           and coalesce(btrim(o.responsavel_nome), '') <> '' and o.telefone is not null
      from public.organizacoes o where o.id = p_organizacao_id), false);
$$;

create or replace function private.contrato_pendente(p_organizacao_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select o.contrato_exigido
           and (not private.dados_organizador_completos(o.id)
                or not exists (
                  select 1 from public.aceites_contrato_organizador a
                   where a.organizacao_id = o.id
                     and a.versao = private.contrato_organizador_versao()))
      from public.organizacoes o where o.id = p_organizacao_id), false);
$$;

revoke all on function private.dados_organizador_completos(uuid) from public, anon;
revoke all on function private.contrato_pendente(uuid) from public, anon;
grant execute on function private.dados_organizador_completos(uuid) to authenticated, service_role;
grant execute on function private.contrato_pendente(uuid) to authenticated, service_role;

-- 6) CASA COM CONTRATO PENDENTE NAO PUBLICA EVENTO -----------------------------
-- "zzz": roda depois da trava de casa em analise (a mensagem dela vem primeiro).
create or replace function private.exigir_contrato_para_publicar()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.publicacao_status = 'PUBLICADO'
     and (tg_op = 'INSERT' or old.publicacao_status is distinct from new.publicacao_status)
     and private.contrato_pendente(new.organizacao_id) then
    raise exception 'Complete os dados do organizador e aceite o Contrato do Organizador para publicar eventos'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function private.exigir_contrato_para_publicar() from public, anon, authenticated;

create trigger trg_zzz_eventos_exige_contrato
  before insert or update of publicacao_status on public.eventos
  for each row execute function private.exigir_contrato_para_publicar();

-- 7) DADOS DA CASA (TELA DO ADMINISTRADOR) ------------------------------------
-- Devolve os dados do organizador, a versao vigente e o ultimo aceite.
create or replace function private.obter_dados_organizador()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.organizacao_atual_id();
  v_res jsonb;
begin
  if v_org is null or not private.usuario_e_admin() then
    raise exception 'Permissao negada' using errcode = '42501';
  end if;

  select jsonb_build_object(
           'organizacao_id', o.id,
           'nome', o.nome,
           'tipo_documento', o.tipo_documento,
           'documento', o.documento,
           'responsavel_nome', o.responsavel_nome,
           'telefone', o.telefone,
           'versao_vigente', private.contrato_organizador_versao(),
           'dados_completos', private.dados_organizador_completos(o.id),
           'contrato_pendente', private.contrato_pendente(o.id),
           'ultimo_aceite', (
             select jsonb_build_object('versao', a.versao, 'aceito_em', a.aceito_em,
                                       'usuario_nome', u.nome, 'usuario_email', u.email)
               from public.aceites_contrato_organizador a
               join public.usuarios u on u.id = a.usuario_id
              where a.organizacao_id = o.id
              order by a.aceito_em desc
              limit 1))
    into v_res
    from public.organizacoes o
   where o.id = v_org;

  return v_res;
end;
$$;

create or replace function private.salvar_dados_organizador(
  p_tipo_documento text,
  p_documento text,
  p_responsavel_nome text,
  p_telefone text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.organizacao_atual_id();
  v_tipo text := upper(btrim(coalesce(p_tipo_documento, '')));
  v_doc text := private.so_digitos(p_documento);
  v_tel text := private.so_digitos(p_telefone);
  v_nome text := btrim(coalesce(p_responsavel_nome, ''));
begin
  if v_org is null or not private.usuario_e_admin() then
    raise exception 'Permissao negada' using errcode = '42501';
  end if;
  if v_tipo not in ('CPF', 'CNPJ') then
    raise exception 'Informe se o documento e CPF ou CNPJ' using errcode = '23514';
  end if;
  if not private.documento_valido(v_tipo, v_doc) then
    raise exception '% invalido: confira os numeros', v_tipo using errcode = '23514';
  end if;
  if v_nome = '' then
    raise exception 'Informe o nome completo ou a razao social' using errcode = '23514';
  end if;
  if v_tel !~ '^[0-9]{10,11}$' then
    raise exception 'Telefone invalido: informe DDD e numero' using errcode = '23514';
  end if;

  update public.organizacoes
     set tipo_documento = v_tipo, documento = v_doc, responsavel_nome = v_nome, telefone = v_tel
   where id = v_org;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos, organizacao_id)
  values (auth.uid(), 'DADOS_ORGANIZADOR_ATUALIZADOS', 'organizacoes', v_org,
          jsonb_build_object('tipo_documento', v_tipo, 'documento', v_doc,
                             'responsavel_nome', v_nome, 'telefone', v_tel), v_org);

  return private.obter_dados_organizador();
end;
$$;

revoke all on function private.obter_dados_organizador() from public, anon;
revoke all on function private.salvar_dados_organizador(text, text, text, text) from public, anon;
grant execute on function private.obter_dados_organizador() to authenticated, service_role;
grant execute on function private.salvar_dados_organizador(text, text, text, text) to authenticated, service_role;

create or replace function public.obter_dados_organizador()
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.obter_dados_organizador(); $$;

create or replace function public.salvar_dados_organizador(
  p_tipo_documento text, p_documento text, p_responsavel_nome text, p_telefone text
)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.salvar_dados_organizador(p_tipo_documento, p_documento, p_responsavel_nome, p_telefone); $$;

revoke all on function public.obter_dados_organizador() from public, anon;
revoke all on function public.salvar_dados_organizador(text, text, text, text) from public, anon;
grant execute on function public.obter_dados_organizador() to authenticated, service_role;
grant execute on function public.salvar_dados_organizador(text, text, text, text) to authenticated, service_role;

-- 8) REGISTRO DO ACEITE (somente servidor / service role) ---------------------
-- A rota do servidor confere a sessao e informa usuario, casa, IP e navegador.
create or replace function private.registrar_aceite_contrato(
  p_usuario_id uuid,
  p_organizacao_id uuid,
  p_versao text,
  p_ip text,
  p_user_agent text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_org public.organizacoes%rowtype;
  v_id uuid;
  v_em timestamptz;
begin
  if not exists (
    select 1
      from public.membros_organizacao m
      join public.usuarios u on u.id = m.usuario_id and u.ativo
     where m.organizacao_id = p_organizacao_id and m.usuario_id = p_usuario_id
       and m.ativo and m.perfil = 'ADMINISTRADOR'
  ) then
    raise exception 'Apenas um administrador da casa pode aceitar o contrato' using errcode = '42501';
  end if;

  if btrim(coalesce(p_versao, '')) <> private.contrato_organizador_versao() then
    raise exception 'Versao do contrato desatualizada: recarregue a pagina' using errcode = '23514';
  end if;

  select * into v_org from public.organizacoes o where o.id = p_organizacao_id and o.ativo;
  if not found then
    raise exception 'Casa nao encontrada' using errcode = '23503';
  end if;
  if not private.dados_organizador_completos(p_organizacao_id) then
    raise exception 'Complete os dados do organizador antes de aceitar' using errcode = '23514';
  end if;

  insert into public.aceites_contrato_organizador
    (organizacao_id, usuario_id, versao, ip, user_agent, tipo_documento, documento, responsavel_nome, telefone)
  values
    (p_organizacao_id, p_usuario_id, private.contrato_organizador_versao(),
     nullif(left(btrim(coalesce(p_ip, '')), 64), ''), nullif(left(btrim(coalesce(p_user_agent, '')), 400), ''),
     v_org.tipo_documento, v_org.documento, v_org.responsavel_nome, v_org.telefone)
  returning id, aceito_em into v_id, v_em;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos, organizacao_id)
  values (p_usuario_id, 'CONTRATO_ORGANIZADOR_ACEITO', 'aceites_contrato_organizador', v_id,
          jsonb_build_object('versao', private.contrato_organizador_versao(), 'ip', p_ip), p_organizacao_id);

  return jsonb_build_object('aceite_id', v_id, 'aceito_em', v_em, 'versao', private.contrato_organizador_versao());
end;
$$;

revoke all on function private.registrar_aceite_contrato(uuid, uuid, text, text, text) from public, anon, authenticated;
grant execute on function private.registrar_aceite_contrato(uuid, uuid, text, text, text) to service_role;

create or replace function public.registrar_aceite_contrato(
  p_usuario_id uuid, p_organizacao_id uuid, p_versao text, p_ip text, p_user_agent text
)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.registrar_aceite_contrato(p_usuario_id, p_organizacao_id, p_versao, p_ip, p_user_agent); $$;

revoke all on function public.registrar_aceite_contrato(uuid, uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.registrar_aceite_contrato(uuid, uuid, text, text, text) to service_role;

-- 9) SUPER ADMIN: DADOS E ACEITES DE UMA CASA ----------------------------------
create or replace function private.obter_contrato_organizacao_plataforma(p_organizacao_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_res jsonb;
begin
  if not private.usuario_e_super_admin() then
    raise exception 'Permissao negada: apenas super administrador' using errcode = '42501';
  end if;

  select jsonb_build_object(
           'tipo_documento', o.tipo_documento,
           'documento', o.documento,
           'responsavel_nome', o.responsavel_nome,
           'telefone', o.telefone,
           'contrato_exigido', o.contrato_exigido,
           'contrato_pendente', private.contrato_pendente(o.id),
           'versao_vigente', private.contrato_organizador_versao(),
           'aceites', coalesce((
             select jsonb_agg(jsonb_build_object(
                      'versao', a.versao, 'aceito_em', a.aceito_em, 'ip', a.ip, 'user_agent', a.user_agent,
                      'usuario_nome', u.nome, 'usuario_email', u.email,
                      'tipo_documento', a.tipo_documento, 'documento', a.documento,
                      'responsavel_nome', a.responsavel_nome, 'telefone', a.telefone)
                    order by a.aceito_em desc)
               from public.aceites_contrato_organizador a
               join public.usuarios u on u.id = a.usuario_id
              where a.organizacao_id = o.id), '[]'::jsonb))
    into v_res
    from public.organizacoes o
   where o.id = p_organizacao_id;

  if v_res is null then
    raise exception 'Casa nao encontrada' using errcode = '23503';
  end if;
  return v_res;
end;
$$;

revoke all on function private.obter_contrato_organizacao_plataforma(uuid) from public, anon;
grant execute on function private.obter_contrato_organizacao_plataforma(uuid) to authenticated, service_role;

create or replace function public.obter_contrato_organizacao_plataforma(p_organizacao_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.obter_contrato_organizacao_plataforma(p_organizacao_id); $$;

revoke all on function public.obter_contrato_organizacao_plataforma(uuid) from public, anon;
grant execute on function public.obter_contrato_organizacao_plataforma(uuid) to authenticated, service_role;

-- 10) PAGINA PUBLICA: QUEM ORGANIZA -------------------------------------------
create or replace function private.obter_organizacao_publica(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('organizacao_id', o.id, 'nome', o.nome, 'slug', o.slug,
                            'logo_url', o.logo_url, 'cor_primaria', o.cor_primaria,
                            'organizador_nome', o.responsavel_nome,
                            'organizador_documento', private.documento_exibicao(o.tipo_documento, o.documento),
                            'organizador_tipo_documento', o.tipo_documento)
    from public.organizacoes o
   where o.slug = lower(btrim(coalesce(p_slug, '')))
     and o.ativo
     and o.aprovada
   limit 1;
$$;

-- 11) CADASTRO SELF-SERVICE COM DOCUMENTO E TELEFONE ----------------------------
-- Documento e telefone sao opcionais aqui (contas criadas antes desta versao
-- nao os tem nos metadados); a casa nasce com contrato_exigido e o painel pede
-- o que faltar antes de liberar.
create or replace function private.concluir_cadastro_produtor(
  p_nome text,
  p_casa_nome text,
  p_casa_slug text,
  p_termos_versao text,
  p_tipo_documento text,
  p_documento text,
  p_responsavel_nome text,
  p_telefone text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_res jsonb;
  v_org uuid;
  v_tipo text := upper(btrim(coalesce(p_tipo_documento, '')));
  v_doc text := private.so_digitos(p_documento);
  v_tel text := private.so_digitos(p_telefone);
  v_nome text := btrim(coalesce(p_responsavel_nome, ''));
begin
  if v_tipo <> '' and not private.documento_valido(v_tipo, v_doc) then
    raise exception '% invalido: confira os numeros', v_tipo using errcode = '23514';
  end if;
  if v_tel <> '' and v_tel !~ '^[0-9]{10,11}$' then
    raise exception 'Telefone invalido: informe DDD e numero' using errcode = '23514';
  end if;

  v_res := private.concluir_cadastro_produtor(p_nome, p_casa_nome, p_casa_slug, p_termos_versao);
  if coalesce((v_res ->> 'ja_existente')::boolean, false) then
    return v_res;
  end if;

  v_org := (v_res ->> 'organizacao_id')::uuid;
  update public.organizacoes
     set contrato_exigido = true,
         tipo_documento = case when v_tipo <> '' then v_tipo end,
         documento = case when v_tipo <> '' then v_doc end,
         responsavel_nome = nullif(coalesce(nullif(v_nome, ''), btrim(coalesce(p_nome, ''))), ''),
         telefone = nullif(v_tel, '')
   where id = v_org;

  return v_res;
end;
$$;

revoke all on function private.concluir_cadastro_produtor(text, text, text, text, text, text, text, text) from public, anon;
grant execute on function private.concluir_cadastro_produtor(text, text, text, text, text, text, text, text)
  to authenticated, service_role;

create or replace function public.concluir_cadastro_produtor(
  p_nome text, p_casa_nome text, p_casa_slug text, p_termos_versao text,
  p_tipo_documento text, p_documento text, p_responsavel_nome text, p_telefone text
)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.concluir_cadastro_produtor(p_nome, p_casa_nome, p_casa_slug, p_termos_versao,
                                                p_tipo_documento, p_documento, p_responsavel_nome, p_telefone); $$;

revoke all on function public.concluir_cadastro_produtor(text, text, text, text, text, text, text, text) from public, anon;
grant execute on function public.concluir_cadastro_produtor(text, text, text, text, text, text, text, text)
  to authenticated, service_role;

-- A versao antiga (4 parametros) continua existindo para quem estiver com a
-- pagina antiga aberta durante o deploy; a casa tambem nasce exigindo contrato.
create or replace function public.concluir_cadastro_produtor(
  p_nome text, p_casa_nome text, p_casa_slug text, p_termos_versao text
)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.concluir_cadastro_produtor(p_nome, p_casa_nome, p_casa_slug, p_termos_versao,
                                                null, null, null, null); $$;

-- 12) SESSAO DO PAINEL: contrato_pendente --------------------------------------
create or replace function private.obter_sessao_operador()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_usuario public.usuarios%rowtype;
  v_org uuid;
  v_perfil public.perfil_usuario;
  v_org_json jsonb;
  v_lista jsonb;
  v_suporte boolean := false;
begin
  if v_uid is null then
    return null;
  end if;

  select * into v_usuario from public.usuarios u where u.id = v_uid;
  if not found then
    return null;
  end if;

  v_org := private.organizacao_atual_id();

  if v_org is null and v_usuario.ativo then
    select m.organizacao_id into v_org
      from public.membros_organizacao m
      join public.organizacoes o on o.id = m.organizacao_id and o.ativo = true
     where m.usuario_id = v_uid and m.ativo = true
     order by o.nome
     limit 1;
    if v_org is not null then
      update public.usuarios set organizacao_ativa_id = v_org where id = v_uid;
    end if;
  end if;

  if v_org is not null then
    select m.perfil into v_perfil
      from public.membros_organizacao m
     where m.organizacao_id = v_org and m.usuario_id = v_uid and m.ativo = true;

    if v_perfil is null and v_usuario.super_admin then
      v_perfil := 'ADMINISTRADOR';
      v_suporte := true;
    end if;

    select jsonb_build_object('id', o.id, 'nome', o.nome, 'slug', o.slug, 'aprovada', o.aprovada,
                              'lista_vip', o.lista_vip_ativa,
                              'contrato_pendente', private.contrato_pendente(o.id))
      into v_org_json
      from public.organizacoes o
     where o.id = v_org;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'nome', o.nome, 'slug', o.slug, 'perfil', m.perfil) order by o.nome), '[]'::jsonb)
    into v_lista
    from public.membros_organizacao m
    join public.organizacoes o on o.id = m.organizacao_id and o.ativo = true
   where m.usuario_id = v_uid and m.ativo = true;

  return jsonb_build_object(
    'id', v_usuario.id,
    'nome', v_usuario.nome,
    'email', v_usuario.email,
    'perfil', v_perfil,
    'ativo', (v_usuario.ativo and v_perfil is not null),
    'super_admin', v_usuario.super_admin,
    'modo_suporte', v_suporte,
    'organizacao', v_org_json,
    'organizacoes', v_lista
  );
end;
$$;

-- 13) ENDERECOS RESERVADOS: pagina do contrato (e /socio, que faltava) ----------
create or replace function private.slug_organizacao_reservado(p_slug text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lower(coalesce(p_slug, '')) = any (array['admin', 'ajuda', 'api', 'app', 'auth', 'cadastro', 'configuracoes', 'contato', 'contrato-organizador', 'dashboard-teste', 'entradas', 'eventos', 'eventos-publicos', 'financeiro', 'ingresso', 'ingressos', 'lista-vip', 'login', 'meus-ingressos', 'painel', 'pedidos', 'plataforma', 'portaria', 'privacidade', 'recuperar-ingressos', 'reembolso', 'sobre', 'socio', 'suporte', 'termos', 'www', '_nuxt']::text[]);
$$;
