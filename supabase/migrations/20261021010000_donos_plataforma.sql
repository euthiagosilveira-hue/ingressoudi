-- =============================================================================
-- Ingressoudi - Donos das casas (Plataforma, somente super admin)
-- listar_donos_plataforma(): uma linha por casa com os dados de quem a
-- cadastrou (nome, e-mail, cadastro, ultimo acesso, termos aceitos), os outros
-- administradores e um resumo da atividade (eventos, ingressos, Mercado Pago).
-- Dono = quem registrou a casa (auditoria ORGANIZACAO_CADASTRADA); se nao houver
-- esse registro, o administrador ativo mais antigo da casa.
-- Somente leitura. Nao devolve tokens nem dados de compradores.
-- =============================================================================

create or replace function private.listar_donos_plataforma()
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
             'organizacao_nome', o.nome,
             'organizacao_slug', o.slug,
             'ativo', o.ativo,
             'aprovada', o.aprovada,
             'criado_em', o.criado_em,
             'dono', case when u.id is null then null else jsonb_build_object(
               'usuario_id', u.id,
               'nome', u.nome,
               'email', u.email,
               'ativo', u.ativo,
               'cadastrado_em', coalesce(au.created_at, u.criado_em),
               'ultimo_acesso_em', coalesce(au.last_sign_in_at, u.ultimo_acesso_em),
               'email_confirmado', au.email_confirmed_at is not null,
               'termos_versao', u.termos_versao,
               'termos_aceitos_em', u.termos_aceitos_em,
               'outras_casas', (
                 select count(*) from public.membros_organizacao m2
                  where m2.usuario_id = u.id and m2.ativo and m2.organizacao_id <> o.id)
             ) end,
             'outros_administradores', coalesce((
               select jsonb_agg(jsonb_build_object('nome', ua.nome, 'email', ua.email) order by ua.email)
                 from public.membros_organizacao m
                 join public.usuarios ua on ua.id = m.usuario_id
                where m.organizacao_id = o.id and m.ativo and m.perfil = 'ADMINISTRADOR'
                  and ua.id is distinct from u.id), '[]'::jsonb),
             'equipe', (
               select count(*) from public.membros_organizacao m
                where m.organizacao_id = o.id and m.ativo),
             'eventos', (select count(*) from public.eventos e where e.organizacao_id = o.id),
             'ingressos_vendidos', (
               select count(*) from public.ingressos i
                where i.organizacao_id = o.id and i.status in ('VALIDO', 'UTILIZADO')),
             'mercado_pago_conectado', mp.organizacao_id is not null,
             'mercado_pago_conectado_em', mp.conectado_em
           ) order by o.criado_em desc)
      from public.organizacoes o
      left join lateral (
        select coalesce(
                 (select a.usuario_id
                    from public.auditoria a
                    join public.usuarios ux on ux.id = a.usuario_id
                   where a.acao = 'ORGANIZACAO_CADASTRADA' and a.entidade_id = o.id
                   order by a.criado_em
                   limit 1),
                 (select m.usuario_id
                    from public.membros_organizacao m
                   where m.organizacao_id = o.id and m.ativo and m.perfil = 'ADMINISTRADOR'
                   order by m.criado_em
                   limit 1)) as usuario_id
      ) d on true
      left join public.usuarios u on u.id = d.usuario_id
      left join auth.users au on au.id = u.id
      left join public.organizacoes_mercado_pago mp on mp.organizacao_id = o.id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.listar_donos_plataforma()
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.listar_donos_plataforma(); $$;

revoke all on function private.listar_donos_plataforma() from public, anon;
revoke all on function public.listar_donos_plataforma() from public, anon;
grant execute on function private.listar_donos_plataforma() to authenticated, service_role;
grant execute on function public.listar_donos_plataforma() to authenticated, service_role;
