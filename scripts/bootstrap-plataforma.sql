-- =============================================================================
-- Ingressoudi - Bootstrap da plataforma (rodar UMA vez, no SQL Editor do
-- projeto do INGRESSOUDI — nunca no projeto do GZ1).
--
-- Antes: crie o seu usuario em Authentication > Users > Add user (com senha).
-- Depois: troque os 3 valores abaixo e execute este script inteiro.
-- Resultado: voce vira super admin e ADMINISTRADOR da primeira organizacao.
-- =============================================================================
do $$
declare
  v_email text := 'seu-email@exemplo.com';     -- e-mail do usuario criado no Auth
  v_nome  text := 'Seu Nome';
  v_org   text := 'Nome da Primeira Organizacao';
  v_uid uuid;
  v_org_id uuid;
begin
  select id into v_uid from auth.users where lower(email) = lower(v_email);
  if v_uid is null then
    raise exception 'Usuario % nao existe em auth.users. Crie-o em Authentication > Users.', v_email;
  end if;

  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin)
  values (v_uid, v_nome, lower(v_email), 'ADMINISTRADOR', true, true)
  on conflict (id) do update set super_admin = true, ativo = true;

  insert into public.organizacoes (nome, slug)
  values (v_org, trim(both '-' from regexp_replace(lower(v_org), '[^a-z0-9]+', '-', 'g')))
  returning id into v_org_id;

  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil)
  values (v_org_id, v_uid, 'ADMINISTRADOR')
  on conflict do nothing;

  update public.usuarios set organizacao_ativa_id = v_org_id where id = v_uid;

  raise notice 'Pronto: % e super admin e administrador da organizacao % (%).', v_email, v_org, v_org_id;
end $$;
