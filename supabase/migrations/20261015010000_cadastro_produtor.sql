-- =============================================================================
-- Ingressoudi - Fase 3B (parte 2): cadastro do produtor com aprovacao e termos
--  * organizacoes.aprovada (existentes = aprovadas; cadastro self-service = em analise)
--  * casa em analise nao publica eventos (trigger) e nao aparece nas paginas publicas
--  * usuarios.termos_aceitos_em / termos_versao
--  * concluir_cadastro_produtor (usuario autenticado cria perfil + casa)
--  * slug_organizacao_disponivel (anon, para o formulario de cadastro)
--  * super admin: listar_organizacoes_plataforma / definir_aprovacao_organizacao
--  * obter_sessao_operador devolve organizacao.aprovada
-- =============================================================================

-- 1) COLUNAS ----------------------------------------------------------------------
alter table public.organizacoes
  add column aprovada boolean not null default true;

alter table public.usuarios
  add column termos_aceitos_em timestamptz null,
  add column termos_versao text null;

-- 2) CASA EM ANALISE NAO PUBLICA EVENTOS ------------------------------------------
create or replace function private.exigir_organizacao_aprovada_para_publicar()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.publicacao_status = 'PUBLICADO'
     and (tg_op = 'INSERT' or old.publicacao_status is distinct from new.publicacao_status)
     and not exists (
       select 1 from public.organizacoes o
        where o.id = new.organizacao_id and o.aprovada
     ) then
    raise exception 'Sua casa ainda esta em analise: voce podera publicar eventos apos a aprovacao'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function private.exigir_organizacao_aprovada_para_publicar() from public, anon, authenticated;

-- "zz" para rodar depois do trigger que preenche organizacao_id
create trigger trg_zz_eventos_exige_organizacao_aprovada
  before insert or update of publicacao_status on public.eventos
  for each row execute function private.exigir_organizacao_aprovada_para_publicar();

-- 3) PAGINAS PUBLICAS SO DE CASAS APROVADAS ------------------------------------------
CREATE OR REPLACE FUNCTION private.obter_organizacao_publica(p_slug text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object('organizacao_id', o.id, 'nome', o.nome, 'slug', o.slug,
                            'logo_url', o.logo_url, 'cor_primaria', o.cor_primaria)
    from public.organizacoes o
   where o.slug = lower(btrim(coalesce(p_slug, '')))
     and o.ativo
     and o.aprovada
   limit 1;
$function$;

CREATE OR REPLACE FUNCTION private.listar_eventos_publicos_organizacao(p_org_slug text)
 RETURNS TABLE(evento_id uuid, slug text, nome text, descricao text, imagem_url text, inicio_em timestamp with time zone, local text, endereco text, status status_evento, vendas_status status_vendas, lote_id uuid, lote_nome text, preco numeric, situacao_venda text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    e.id, e.slug, e.nome, e.descricao, e.imagem_url, e.inicio_em, e.local, e.endereco,
    e.status, e.vendas_status,
    l.id, l.nome, l.preco,
    private.calcular_situacao_venda(e.id)
  from public.eventos e
  join public.organizacoes o on o.id = e.organizacao_id
  left join lateral (
    select lo.id, lo.nome, lo.preco
      from public.lotes lo
     where lo.evento_id = e.id and lo.status = 'ATIVO'
     limit 1
  ) l on true
  where o.slug = lower(btrim(coalesce(p_org_slug, '')))
    and o.ativo
     and o.aprovada
    and e.publicacao_status = 'PUBLICADO'
    and e.status = 'AGENDADO'
    and e.inicio_em >= now()
  order by e.inicio_em asc;
$function$;

CREATE OR REPLACE FUNCTION private.obter_evento_publico_organizacao(p_org_slug text, p_evento_slug text)
 RETURNS TABLE(evento_id uuid, slug text, nome text, descricao text, imagem_url text, inicio_em timestamp with time zone, local text, endereco text, status status_evento, vendas_status status_vendas, lote_id uuid, lote_nome text, preco numeric, situacao_venda text, taxa_servico numeric, taxa_repassada boolean, organizacao_slug text, organizacao_nome text, organizacao_logo_url text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    e.id, e.slug, e.nome, e.descricao, e.imagem_url, e.inicio_em, e.local, e.endereco,
    e.status, e.vendas_status,
    l.id, l.nome, l.preco,
    private.calcular_situacao_venda(e.id),
    case when e.taxa_repassada then o.taxa_servico else 0 end,
    e.taxa_repassada,
    o.slug, o.nome, o.logo_url
  from public.eventos e
  join public.organizacoes o on o.id = e.organizacao_id
  left join lateral (
    select lo.id, lo.nome, lo.preco
      from public.lotes lo
     where lo.evento_id = e.id and lo.status = 'ATIVO'
     limit 1
  ) l on true
  where o.slug = lower(btrim(coalesce(p_org_slug, '')))
    and o.ativo
     and o.aprovada
    and e.slug = lower(btrim(coalesce(p_evento_slug, '')))
    and e.publicacao_status = 'PUBLICADO'
  limit 1;
$function$;

CREATE OR REPLACE FUNCTION private.resolver_evento_publico(p_slug text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when count(*) = 1
              then jsonb_build_object('organizacao_slug', min(o.slug), 'evento_slug', min(e.slug))
         end
    from public.eventos e
    join public.organizacoes o on o.id = e.organizacao_id
   where e.slug = lower(btrim(coalesce(p_slug, '')))
     and e.publicacao_status = 'PUBLICADO'
     and o.ativo
     and o.aprovada;
$function$;

-- 4) SESSAO COM STATUS DE APROVACAO ------------------------------------------------
CREATE OR REPLACE FUNCTION private.obter_sessao_operador()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_usuario public.usuarios%rowtype;
  v_org uuid;
  v_perfil public.perfil_usuario;
  v_org_json jsonb;
  v_lista jsonb;
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
    select m.perfil, jsonb_build_object('id', o.id, 'nome', o.nome, 'slug', o.slug, 'aprovada', o.aprovada)
      into v_perfil, v_org_json
      from public.membros_organizacao m
      join public.organizacoes o on o.id = m.organizacao_id
     where m.organizacao_id = v_org and m.usuario_id = v_uid;
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
    'organizacao', v_org_json,
    'organizacoes', v_lista
  );
end;
$function$;

-- 5) CADASTRO DO PRODUTOR ---------------------------------------------------------
create or replace function private.slug_organizacao_disponivel(p_slug text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(btrim(p_slug), '') ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
     and not private.slug_organizacao_reservado(p_slug)
     and not exists (select 1 from public.organizacoes o where o.slug = btrim(p_slug));
$$;

create or replace function public.slug_organizacao_disponivel(p_slug text)
returns boolean language sql stable security invoker set search_path = ''
as $$ select private.slug_organizacao_disponivel(p_slug); $$;

create or replace function private.concluir_cadastro_produtor(
  p_nome text,
  p_casa_nome text,
  p_casa_slug text,
  p_termos_versao text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_usuario public.usuarios%rowtype;
  v_org uuid;
  v_slug text;
begin
  if v_uid is null then
    raise exception 'Faca login para concluir o cadastro' using errcode = '42501';
  end if;

  -- Idempotente: quem ja tem casa volta para ela.
  select m.organizacao_id into v_org
    from public.membros_organizacao m
   where m.usuario_id = v_uid and m.ativo
   order by m.criado_em
   limit 1;
  if v_org is not null then
    return jsonb_build_object('organizacao_id', v_org, 'ja_existente', true);
  end if;

  if p_nome is null or btrim(p_nome) = '' then
    raise exception 'Informe seu nome' using errcode = '23514';
  end if;
  if p_casa_nome is null or btrim(p_casa_nome) = '' then
    raise exception 'Informe o nome da casa' using errcode = '23514';
  end if;
  if p_termos_versao is null or btrim(p_termos_versao) = '' then
    raise exception 'Aceite os termos de uso para continuar' using errcode = '23514';
  end if;

  select u.email into v_email from auth.users u where u.id = v_uid;
  if v_email is null or btrim(v_email) = '' then
    raise exception 'Conta sem e-mail' using errcode = '23514';
  end if;

  select * into v_usuario from public.usuarios u where u.id = v_uid;
  if found and not v_usuario.ativo then
    raise exception 'Usuario inativo' using errcode = '42501';
  end if;

  v_slug := btrim(
    regexp_replace(
      lower(
        translate(
          btrim(coalesce(nullif(btrim(p_casa_slug), ''), p_casa_nome)),
          U&'\00E1\00E0\00E2\00E3\00E4\00E9\00E8\00EA\00EB\00ED\00EC\00EE\00EF\00F3\00F2\00F4\00F5\00F6\00FA\00F9\00FB\00FC\00E7\00F1',
          'aaaaaeeeeiiiiooooouuuucn'
        )
      ),
      '[^a-z0-9]+', '-', 'g'
    ),
    '-'
  );
  if v_slug = '' then
    raise exception 'Informe o endereco da casa' using errcode = '23514';
  end if;
  if private.slug_organizacao_reservado(v_slug) then
    raise exception 'Endereco indisponivel: escolha outro' using errcode = '23514';
  end if;

  insert into public.usuarios (id, nome, email, perfil, ativo)
  values (v_uid, btrim(p_nome), lower(btrim(v_email)), 'ADMINISTRADOR', true)
  on conflict (id) do nothing;

  begin
    insert into public.organizacoes (nome, slug, aprovada)
    values (btrim(p_casa_nome), v_slug, false)
    returning id into v_org;
  exception when unique_violation then
    raise exception 'Ja existe uma casa com esse endereco: escolha outro' using errcode = '23505';
  end;

  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil)
  values (v_org, v_uid, 'ADMINISTRADOR');

  update public.usuarios
     set organizacao_ativa_id = v_org,
         termos_aceitos_em = now(),
         termos_versao = btrim(p_termos_versao)
   where id = v_uid;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos, organizacao_id)
  values (v_uid, 'ORGANIZACAO_CADASTRADA', 'organizacoes', v_org,
          jsonb_build_object('nome', btrim(p_casa_nome), 'slug', v_slug, 'termos_versao', btrim(p_termos_versao)), v_org);

  return jsonb_build_object('organizacao_id', v_org, 'slug', v_slug, 'ja_existente', false);
end;
$$;

create or replace function public.concluir_cadastro_produtor(
  p_nome text, p_casa_nome text, p_casa_slug text, p_termos_versao text
)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.concluir_cadastro_produtor(p_nome, p_casa_nome, p_casa_slug, p_termos_versao); $$;

-- 6) SUPER ADMIN: APROVACAO -------------------------------------------------------
create or replace function private.listar_organizacoes_plataforma()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.usuario_e_super_admin() then
    raise exception 'Permissao negada: apenas super administrador' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'organizacao_id', o.id,
             'nome', o.nome,
             'slug', o.slug,
             'ativo', o.ativo,
             'aprovada', o.aprovada,
             'criado_em', o.criado_em,
             'mercado_pago_conectado', exists (
               select 1 from public.organizacoes_mercado_pago mp where mp.organizacao_id = o.id),
             'administradores', coalesce((
               select string_agg(u.email, ', ' order by u.email)
                 from public.membros_organizacao m
                 join public.usuarios u on u.id = m.usuario_id
                where m.organizacao_id = o.id and m.ativo and m.perfil = 'ADMINISTRADOR'), ''),
             'eventos', (select count(*) from public.eventos e where e.organizacao_id = o.id)
           ) order by o.aprovada, o.criado_em desc)
      from public.organizacoes o
  ), '[]'::jsonb);
end;
$$;

create or replace function public.listar_organizacoes_plataforma()
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.listar_organizacoes_plataforma(); $$;

create or replace function private.definir_aprovacao_organizacao(p_organizacao_id uuid, p_aprovada boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not private.usuario_e_super_admin() then
    raise exception 'Permissao negada: apenas super administrador' using errcode = '42501';
  end if;
  update public.organizacoes set aprovada = coalesce(p_aprovada, false) where id = p_organizacao_id;
  if not found then
    raise exception 'Organizacao % nao encontrada', p_organizacao_id using errcode = '23503';
  end if;
  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos, organizacao_id)
  values (auth.uid(),
          case when coalesce(p_aprovada, false) then 'ORGANIZACAO_APROVADA' else 'ORGANIZACAO_EM_ANALISE' end,
          'organizacoes', p_organizacao_id, jsonb_build_object('aprovada', coalesce(p_aprovada, false)), p_organizacao_id);
  return jsonb_build_object('organizacao_id', p_organizacao_id, 'aprovada', coalesce(p_aprovada, false));
end;
$$;

create or replace function public.definir_aprovacao_organizacao(p_organizacao_id uuid, p_aprovada boolean)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.definir_aprovacao_organizacao(p_organizacao_id, p_aprovada); $$;

-- 7) PERMISSOES ------------------------------------------------------------------
revoke all on function private.slug_organizacao_disponivel(text) from public;
revoke all on function private.concluir_cadastro_produtor(text, text, text, text) from public, anon;
revoke all on function private.listar_organizacoes_plataforma() from public, anon;
revoke all on function private.definir_aprovacao_organizacao(uuid, boolean) from public, anon;
grant execute on function private.slug_organizacao_disponivel(text) to anon, authenticated, service_role;
grant execute on function private.concluir_cadastro_produtor(text, text, text, text) to authenticated, service_role;
grant execute on function private.listar_organizacoes_plataforma() to authenticated, service_role;
grant execute on function private.definir_aprovacao_organizacao(uuid, boolean) to authenticated, service_role;

revoke all on function public.slug_organizacao_disponivel(text) from public;
revoke all on function public.concluir_cadastro_produtor(text, text, text, text) from public, anon;
revoke all on function public.listar_organizacoes_plataforma() from public, anon;
revoke all on function public.definir_aprovacao_organizacao(uuid, boolean) from public, anon;
grant execute on function public.slug_organizacao_disponivel(text) to anon, authenticated, service_role;
grant execute on function public.concluir_cadastro_produtor(text, text, text, text) to authenticated, service_role;
grant execute on function public.listar_organizacoes_plataforma() to authenticated, service_role;
grant execute on function public.definir_aprovacao_organizacao(uuid, boolean) to authenticated, service_role;
