-- =============================================================================
-- Ingressoudi - Convite de usuarios por link
--
-- 1) listar_usuarios_admin passa a informar:
--    - pendente: o usuario ainda nao criou a senha (convite nao aceito);
--    - ultimo_acesso_em: ultimo login real (auth.users.last_sign_in_at).
--      Antes vinha de usuarios.ultimo_acesso_em, que nunca era preenchido.
-- 2) situacao_convite_usuario: usada SOMENTE pelo backend (service role) para
--    decidir se um novo link de convite pode ser gerado para o usuario.
-- =============================================================================

create or replace function private.listar_usuarios_admin(p_busca text default null::text)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_itens jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'id', u.id,
               'nome', u.nome,
               'email', u.email,
               'perfil', m.perfil,
               'ativo', (m.ativo and u.ativo),
               'pendente', coalesce(au.encrypted_password, '') = '',
               'ultimo_acesso_em', coalesce(au.last_sign_in_at, u.ultimo_acesso_em),
               'criado_em', u.criado_em
             )
             order by (m.ativo and u.ativo) desc, m.perfil, u.nome
           ),
           '[]'::jsonb
         )
    into v_itens
    from public.membros_organizacao m
    join public.usuarios u on u.id = m.usuario_id
    left join auth.users au on au.id = u.id
   where m.organizacao_id = (select private.organizacao_atual_id())
     and (
       p_busca is null
       or btrim(p_busca) = ''
       or u.nome ilike '%' || p_busca || '%'
       or u.email ilike '%' || p_busca || '%'
     );

  return v_itens;
end;
$function$;

comment on function public.listar_usuarios_admin(text) is 'Lista membros da organizacao ativa (ADMINISTRADOR). Campos: id, nome, email, perfil, ativo, pendente, ultimo_acesso_em, criado_em.';

-- Situacao do convite de um usuario em relacao a uma organizacao.
-- pendente: ainda sem senha. outras_organizacoes: vinculos fora desta organizacao
-- (o backend so gera novo link quando o usuario pertence apenas a ela).
create or replace function private.situacao_convite_usuario(p_usuario_id uuid, p_organizacao_id uuid)
returns jsonb
language sql
stable security definer
set search_path to ''
as $function$
  select jsonb_build_object(
    'existe', au.id is not null,
    'membro', exists (
      select 1 from public.membros_organizacao m
       where m.usuario_id = p_usuario_id and m.organizacao_id = p_organizacao_id
    ),
    'pendente', au.id is not null and coalesce(au.encrypted_password, '') = '',
    'email_confirmado', au.email_confirmed_at is not null,
    'outras_organizacoes', (
      select count(*) from public.membros_organizacao m
       where m.usuario_id = p_usuario_id and m.organizacao_id <> p_organizacao_id
    )
  )
  from (select p_usuario_id as id) alvo
  left join auth.users au on au.id = alvo.id;
$function$;

create or replace function public.situacao_convite_usuario(p_usuario_id uuid, p_organizacao_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $w$ select private.situacao_convite_usuario(p_usuario_id, p_organizacao_id); $w$;

revoke all on function private.situacao_convite_usuario(uuid, uuid) from public, anon, authenticated;
revoke all on function public.situacao_convite_usuario(uuid, uuid) from public, anon, authenticated;
grant execute on function private.situacao_convite_usuario(uuid, uuid) to service_role;
grant execute on function public.situacao_convite_usuario(uuid, uuid) to service_role;
