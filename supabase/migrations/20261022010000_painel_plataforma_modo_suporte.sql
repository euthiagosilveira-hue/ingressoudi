-- =============================================================================
-- Ingressoudi - Painel da plataforma e modo suporte (somente super admin)
--
-- 1) MODO SUPORTE: o super admin pode ativar QUALQUER casa ativa como
--    ADMINISTRADOR sem virar membro da equipe dela. Todo o escopo do sistema
--    passa por organizacao_atual_id() e perfil_usuario_atual(), entao as telas
--    da casa (eventos, lotes, pedidos, portaria, lista VIP...) funcionam sem
--    mudar nenhuma RPC. Cada entrada fica na auditoria (MODO_SUPORTE_INICIADO).
--    Bloqueado no modo suporte: desconectar o Mercado Pago e alterar usuarios
--    (conectar o Mercado Pago e convidar ja exigem ser membro, no backend).
-- 2) obter_painel_plataforma(p_desde): numeros de todas as casas, eventos de
--    agora e dos proximos dias, ranking, alertas e atividade recente.
--    Valores seguem as regras de Todos os eventos e da Receita: pedidos PAGO;
--    online = pagamento APROVADO no Mercado Pago; taxa so das vendas online.
-- =============================================================================

-- 1) MODO SUPORTE ---------------------------------------------------------------

-- Casa ativa: membro ativo, ou super admin em qualquer casa ativa.
create or replace function private.organizacao_atual_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select u.organizacao_ativa_id
    from public.usuarios u
    join public.organizacoes o
      on o.id = u.organizacao_ativa_id
     and o.ativo = true
   where u.id = auth.uid()
     and u.ativo = true
     and (
       exists (
         select 1 from public.membros_organizacao m
          where m.organizacao_id = u.organizacao_ativa_id
            and m.usuario_id = u.id
            and m.ativo = true)
       or u.super_admin = true
     );
$$;

-- Perfil na casa ativa: o do membro; super admin fora da equipe = ADMINISTRADOR.
create or replace function private.perfil_usuario_atual()
returns public.perfil_usuario
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
           (select m.perfil
              from public.membros_organizacao m
             where m.usuario_id = u.id
               and m.organizacao_id = u.organizacao_ativa_id
               and m.ativo = true),
           case when u.super_admin then 'ADMINISTRADOR'::public.perfil_usuario end)
    from public.usuarios u
    join public.organizacoes o
      on o.id = u.organizacao_ativa_id
     and o.ativo = true
   where u.id = auth.uid()
     and u.ativo = true;
$$;

-- true quando o super admin esta numa casa da qual nao e membro ativo.
create or replace function private.em_modo_suporte()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select u.super_admin
           and o.id is not null
           and not exists (
             select 1 from public.membros_organizacao m
              where m.organizacao_id = u.organizacao_ativa_id
                and m.usuario_id = u.id
                and m.ativo = true)
      from public.usuarios u
      left join public.organizacoes o
        on o.id = u.organizacao_ativa_id
       and o.ativo = true
     where u.id = auth.uid()
       and u.ativo = true), false);
$$;

revoke all on function private.em_modo_suporte() from public, anon;
grant execute on function private.em_modo_suporte() to authenticated, service_role;

create or replace function private.definir_organizacao_ativa(p_organizacao_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_perfil public.perfil_usuario;
  v_suporte boolean := false;
begin
  if v_uid is null then
    raise exception 'Permissao negada' using errcode = '42501';
  end if;

  select m.perfil into v_perfil
    from public.membros_organizacao m
    join public.organizacoes o on o.id = m.organizacao_id and o.ativo = true
    join public.usuarios u on u.id = m.usuario_id and u.ativo = true
   where m.organizacao_id = p_organizacao_id
     and m.usuario_id = v_uid
     and m.ativo = true;

  -- Super admin fora da equipe: entra como ADMINISTRADOR (modo suporte).
  if v_perfil is null
     and private.usuario_e_super_admin()
     and exists (select 1 from public.organizacoes o where o.id = p_organizacao_id and o.ativo = true) then
    v_perfil := 'ADMINISTRADOR';
    v_suporte := true;
  end if;

  if v_perfil is null then
    raise exception 'Organizacao % nao encontrada', p_organizacao_id using errcode = '23503';
  end if;

  -- usuarios.perfil acompanha a organizacao ativa (compatibilidade com o front)
  update public.usuarios
     set organizacao_ativa_id = p_organizacao_id,
         perfil = v_perfil
   where id = v_uid;

  if v_suporte then
    insert into public.auditoria (usuario_id, acao, entidade, entidade_id, organizacao_id, observacao)
    values (v_uid, 'MODO_SUPORTE_INICIADO', 'organizacoes', p_organizacao_id, p_organizacao_id,
            'Super admin entrou na casa pelo modo suporte');
  end if;

  return private.obter_sessao_operador();
end;
$$;

-- Volta para a primeira casa da qual o usuario e membro (ou nenhuma).
create or replace function private.sair_modo_suporte()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_org uuid;
  v_perfil public.perfil_usuario;
begin
  if v_uid is null then
    raise exception 'Permissao negada' using errcode = '42501';
  end if;

  select m.organizacao_id, m.perfil into v_org, v_perfil
    from public.membros_organizacao m
    join public.organizacoes o on o.id = m.organizacao_id and o.ativo = true
   where m.usuario_id = v_uid and m.ativo = true
   order by o.nome
   limit 1;

  update public.usuarios
     set organizacao_ativa_id = v_org,
         perfil = coalesce(v_perfil, perfil)
   where id = v_uid;

  return private.obter_sessao_operador();
end;
$$;

create or replace function public.sair_modo_suporte()
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.sair_modo_suporte(); $$;

revoke all on function private.sair_modo_suporte() from public, anon;
revoke all on function public.sair_modo_suporte() from public, anon;
grant execute on function private.sair_modo_suporte() to authenticated, service_role;
grant execute on function public.sair_modo_suporte() to authenticated, service_role;

-- Sessao: casa ativa tambem no modo suporte, com a marca modo_suporte.
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
                              'lista_vip', o.lista_vip_ativa)
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

-- Bloqueios do modo suporte: conta de recebimento e equipe sao do produtor.
create or replace function private.exigir_fora_do_modo_suporte()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if private.em_modo_suporte() then
    raise exception 'Indisponivel no modo suporte: a conta do Mercado Pago e a equipe sao do produtor.'
      using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.exigir_fora_do_modo_suporte() from public, anon;
grant execute on function private.exigir_fora_do_modo_suporte() to authenticated, service_role;

create or replace function private.desconectar_mercado_pago()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.organizacao_atual_id();
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;
  perform private.exigir_fora_do_modo_suporte();

  delete from public.organizacoes_mercado_pago where organizacao_id = v_org;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, organizacao_id)
  values (auth.uid(), 'MERCADO_PAGO_DESCONECTADO', 'organizacoes', v_org, v_org);

  return jsonb_build_object('conectado', false);
end;
$$;

create or replace function private.atualizar_usuario_admin(p_usuario_id uuid, p_nome text, p_perfil public.perfil_usuario, p_ativo boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
  v_membro public.membros_organizacao%rowtype;
  v_nome_anterior text;
  v_nome text;
  v_outros_admins integer;
  v_acao text;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;
  perform private.exigir_fora_do_modo_suporte();

  v_org := private.organizacao_atual_id();

  v_nome := btrim(coalesce(p_nome, ''));
  if v_nome = '' then
    raise exception 'Informe o nome do usuario.' using errcode = '23514';
  end if;

  if p_perfil is null or p_ativo is null then
    raise exception 'Dados invalidos: perfil e status sao obrigatorios.' using errcode = '23514';
  end if;

  select * into v_membro
    from public.membros_organizacao m
   where m.organizacao_id = v_org
     and m.usuario_id = p_usuario_id
   for update;

  if not found then
    raise exception 'Usuario nao encontrado.' using errcode = '23503';
  end if;

  select u.nome into v_nome_anterior from public.usuarios u where u.id = p_usuario_id;

  -- Nunca permitir auto-desativacao
  if p_usuario_id = auth.uid() and p_ativo = false then
    raise exception 'Voce nao pode desativar o seu proprio usuario.' using errcode = '42501';
  end if;

  -- Nunca deixar a organizacao sem ADMINISTRADOR ativo
  if v_membro.perfil = 'ADMINISTRADOR'
     and v_membro.ativo = true
     and (p_ativo = false or p_perfil <> 'ADMINISTRADOR') then
    select count(*) into v_outros_admins
      from public.membros_organizacao m
      join public.usuarios u on u.id = m.usuario_id
     where m.organizacao_id = v_org
       and m.perfil = 'ADMINISTRADOR'
       and m.ativo = true
       and u.ativo = true
       and m.usuario_id <> p_usuario_id;

    if v_outros_admins = 0 then
      raise exception 'E necessario manter pelo menos um administrador ativo.' using errcode = '23514';
    end if;
  end if;

  update public.membros_organizacao
     set perfil = p_perfil,
         ativo = p_ativo
   where organizacao_id = v_org
     and usuario_id = p_usuario_id;

  update public.usuarios u
     set nome = v_nome,
         perfil = case when u.organizacao_ativa_id = v_org then p_perfil else u.perfil end
   where u.id = p_usuario_id;

  v_acao := case
    when v_membro.ativo <> p_ativo and p_ativo then 'USUARIO_ATIVADO'
    when v_membro.ativo <> p_ativo and not p_ativo then 'USUARIO_DESATIVADO'
    when v_membro.perfil <> p_perfil then 'USUARIO_PERFIL_ALTERADO'
    else 'USUARIO_ATUALIZADO'
  end;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos, organizacao_id)
  values (
    auth.uid(),
    v_acao,
    'usuarios',
    p_usuario_id,
    jsonb_build_object('nome', v_nome_anterior, 'perfil', v_membro.perfil, 'ativo', v_membro.ativo),
    jsonb_build_object('nome', v_nome, 'perfil', p_perfil, 'ativo', p_ativo),
    v_org
  );

  return jsonb_build_object('ok', true);
end;
$$;

-- 2) PAINEL DA PLATAFORMA --------------------------------------------------------
-- p_desde: inicio do periodo (null = desde sempre). O periodo anterior, de
-- mesmo tamanho, serve para a comparacao dos numeros do topo.
create or replace function private.obter_painel_plataforma(p_desde timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_agora timestamptz := now();
  v_anterior timestamptz;
  v_atual jsonb;
  v_prev jsonb;
  v_res jsonb;
begin
  if not private.usuario_e_super_admin() then
    raise exception 'Permissao negada: apenas super administrador' using errcode = '42501';
  end if;

  if p_desde is not null then
    v_anterior := p_desde - (v_agora - p_desde);
  end if;

  -- Vendas por periodo: pedidos PAGO pela data do pagamento
  with pagos as (
    select p.organizacao_id, p.quantidade, p.valor_total, p.valor_taxa_total, p.pago_em,
           exists (select 1 from public.pagamentos g
                    where g.pedido_id = p.id and g.status = 'APROVADO' and g.provedor = 'MERCADO_PAGO') as online
      from public.pedidos p
     where p.status = 'PAGO'
  )
  select
    jsonb_build_object(
      'ingressos', coalesce(sum(quantidade) filter (where p_desde is null or pago_em >= p_desde), 0),
      'valor', coalesce(sum(valor_total) filter (where p_desde is null or pago_em >= p_desde), 0),
      'taxa', coalesce(sum(valor_taxa_total) filter (where online and (p_desde is null or pago_em >= p_desde)), 0),
      'pedidos', count(*) filter (where p_desde is null or pago_em >= p_desde)),
    case when p_desde is null then null else jsonb_build_object(
      'ingressos', coalesce(sum(quantidade) filter (where pago_em >= v_anterior and pago_em < p_desde), 0),
      'valor', coalesce(sum(valor_total) filter (where pago_em >= v_anterior and pago_em < p_desde), 0),
      'taxa', coalesce(sum(valor_taxa_total) filter (where online and pago_em >= v_anterior and pago_em < p_desde), 0),
      'pedidos', count(*) filter (where pago_em >= v_anterior and pago_em < p_desde)) end
    into v_atual, v_prev
    from pagos;

  v_res := jsonb_build_object(
    'gerado_em', v_agora,
    'desde', p_desde,
    'metricas', v_atual || jsonb_build_object(
      'casas_ativas', (select count(*) from public.organizacoes o where o.ativo and o.aprovada),
      'casas_em_analise', (select count(*) from public.organizacoes o where o.ativo and not o.aprovada),
      'casas_novas', (select count(*) from public.organizacoes o
                       where o.ativo and (p_desde is null or o.criado_em >= p_desde)),
      'eventos_vendas_abertas', (select count(*) from public.eventos e
                                  where e.publicacao_status = 'PUBLICADO'
                                    and e.status in ('AGENDADO', 'EM_ANDAMENTO')
                                    and e.vendas_status = 'ABERTAS'),
      'casas_vendas_abertas', (select count(distinct e.organizacao_id) from public.eventos e
                                where e.publicacao_status = 'PUBLICADO'
                                  and e.status in ('AGENDADO', 'EM_ANDAMENTO')
                                  and e.vendas_status = 'ABERTAS')),
    'anterior', v_prev
  );

  -- Eventos acontecendo agora e nos proximos 14 dias (publicados)
  v_res := v_res || jsonb_build_object('eventos', coalesce((
    select jsonb_agg(x order by x->>'inicio_em')
      from (
        select jsonb_build_object(
                 'evento_id', e.id,
                 'nome', e.nome,
                 'slug', e.slug,
                 'imagem_url', e.imagem_url,
                 'inicio_em', e.inicio_em,
                 'local', e.local,
                 'status', e.status,
                 'vendas_status', e.vendas_status,
                 'capacidade_total', e.capacidade_total,
                 'organizacao_id', o.id,
                 'organizacao_nome', o.nome,
                 'organizacao_slug', o.slug,
                 'vendidos', (select count(*) from public.ingressos i
                               where i.evento_id = e.id and i.status in ('VALIDO', 'UTILIZADO')),
                 'utilizados', (select count(*) from public.ingressos i
                                 where i.evento_id = e.id and i.status = 'UTILIZADO')) as x
          from public.eventos e
          join public.organizacoes o on o.id = e.organizacao_id
         where e.publicacao_status = 'PUBLICADO'
           and (e.status = 'EM_ANDAMENTO'
                or (e.status = 'AGENDADO'
                    and e.inicio_em >= v_agora - interval '12 hours'
                    and e.inicio_em < v_agora + interval '14 days'))
         order by e.inicio_em
         limit 12
      ) t), '[]'::jsonb));

  -- Ranking de casas no periodo
  v_res := v_res || jsonb_build_object('ranking', coalesce((
    select jsonb_agg(r order by (r->>'valor')::numeric desc)
      from (
        select jsonb_build_object(
                 'organizacao_id', o.id,
                 'nome', o.nome,
                 'ingressos', sum(p.quantidade),
                 'pedidos', count(*),
                 'valor', sum(p.valor_total),
                 'taxa', coalesce(sum(p.valor_taxa_total) filter (where exists (
                           select 1 from public.pagamentos g
                            where g.pedido_id = p.id and g.status = 'APROVADO' and g.provedor = 'MERCADO_PAGO')), 0)
               ) as r
          from public.pedidos p
          join public.organizacoes o on o.id = p.organizacao_id
         where p.status = 'PAGO'
           and (p_desde is null or p.pago_em >= p_desde)
         group by o.id, o.nome
         order by sum(p.valor_total) desc
         limit 5
      ) t), '[]'::jsonb));

  -- Alertas
  v_res := v_res || jsonb_build_object('alertas', jsonb_build_object(
    'casas_sem_mercado_pago', coalesce((
      select jsonb_agg(jsonb_build_object('organizacao_id', o.id, 'nome', o.nome) order by o.criado_em)
        from public.organizacoes o
       where o.ativo and o.aprovada
         and not exists (select 1 from public.organizacoes_mercado_pago mp where mp.organizacao_id = o.id)
    ), '[]'::jsonb),
    'casas_sem_evento', coalesce((
      select jsonb_agg(jsonb_build_object('organizacao_id', o.id, 'nome', o.nome, 'criado_em', o.criado_em)
                       order by o.criado_em)
        from public.organizacoes o
       where o.ativo
         and o.criado_em < v_agora - interval '7 days'
         and not exists (select 1 from public.eventos e where e.organizacao_id = o.id)
    ), '[]'::jsonb),
    'eventos_sem_vendas', coalesce((
      select jsonb_agg(jsonb_build_object('evento_id', e.id, 'nome', e.nome, 'inicio_em', e.inicio_em,
                                          'organizacao_id', o.id, 'organizacao_nome', o.nome)
                       order by e.inicio_em)
        from public.eventos e
        join public.organizacoes o on o.id = e.organizacao_id
       where e.publicacao_status = 'PUBLICADO'
         and e.status in ('AGENDADO', 'EM_ANDAMENTO')
         and e.vendas_status = 'ABERTAS'
         and coalesce(e.publicado_em, e.criado_em) < v_agora - interval '3 days'
         and not exists (select 1 from public.pedidos p where p.evento_id = e.id and p.status = 'PAGO')
    ), '[]'::jsonb),
    'pix_recusados_24h', coalesce((
      select jsonb_agg(jsonb_build_object('organizacao_id', t.organizacao_id, 'nome', t.nome, 'quantidade', t.qtd)
                       order by t.qtd desc)
        from (
          select o.id as organizacao_id, o.nome, count(*) as qtd
            from public.pagamentos g
            join public.organizacoes o on o.id = g.organizacao_id
           where g.provedor = 'MERCADO_PAGO'
             and g.status = 'REJEITADO'
             and g.atualizado_em >= v_agora - interval '24 hours'
           group by o.id, o.nome
        ) t
    ), '[]'::jsonb)
  ));

  -- Atividade recente (ultimos 7 dias)
  v_res := v_res || jsonb_build_object('atividade', coalesce((
    select jsonb_agg(a order by a->>'em' desc)
      from (
        select a
          from (
            select jsonb_build_object('tipo', 'CASA_NOVA', 'em', o.criado_em,
                                      'organizacao_id', o.id, 'organizacao_nome', o.nome) as a
              from public.organizacoes o
             where o.criado_em >= v_agora - interval '7 days'
            union all
            select jsonb_build_object('tipo', 'EVENTO_PUBLICADO', 'em', e.publicado_em,
                                      'organizacao_id', o.id, 'organizacao_nome', o.nome,
                                      'evento_id', e.id, 'evento_nome', e.nome)
              from public.eventos e
              join public.organizacoes o on o.id = e.organizacao_id
             where e.publicacao_status = 'PUBLICADO'
               and e.publicado_em >= v_agora - interval '7 days'
            union all
            select jsonb_build_object('tipo', 'MERCADO_PAGO_CONECTADO', 'em', mp.conectado_em,
                                      'organizacao_id', o.id, 'organizacao_nome', o.nome)
              from public.organizacoes_mercado_pago mp
              join public.organizacoes o on o.id = mp.organizacao_id
             where mp.conectado_em >= v_agora - interval '7 days'
            union all
            select jsonb_build_object('tipo', 'VENDA', 'em', p.pago_em,
                                      'organizacao_id', o.id, 'organizacao_nome', o.nome,
                                      'evento_id', e.id, 'evento_nome', e.nome,
                                      'quantidade', p.quantidade, 'valor', p.valor_total)
              from public.pedidos p
              join public.eventos e on e.id = p.evento_id
              join public.organizacoes o on o.id = p.organizacao_id
             where p.status = 'PAGO'
               and p.pago_em >= v_agora - interval '7 days'
          ) u
         order by a->>'em' desc
         limit 12
      ) t), '[]'::jsonb));

  return v_res;
end;
$$;

create or replace function public.obter_painel_plataforma(p_desde timestamptz default null)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.obter_painel_plataforma(p_desde); $$;

revoke all on function private.obter_painel_plataforma(timestamptz) from public, anon;
revoke all on function public.obter_painel_plataforma(timestamptz) from public, anon;
grant execute on function private.obter_painel_plataforma(timestamptz) to authenticated, service_role;
grant execute on function public.obter_painel_plataforma(timestamptz) to authenticated, service_role;
