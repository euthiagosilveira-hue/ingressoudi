-- =============================================================================
-- Ingressoudi - Testes: taxa de servico por casa e exclusiva do super admin
-- Executar como owner. begin/rollback.
-- =============================================================================

begin;

-- [Ingressoudi] Fixture multiempresa (Etapa A) ---------------------------------
-- Cria uma organizacao de teste; eventos inseridos sem organizacao caem nela e
-- todo usuario criado (ou com perfil alterado) vira membro dela com o mesmo
-- perfil. Tudo e desfeito pelo rollback ao final do arquivo.
do $fx$
declare
  v_org uuid;
begin
  -- taxa_servico 0: os testes herdados validam valores sem a taxa da plataforma
  insert into public.organizacoes (nome, slug, taxa_servico)
  values ('Org Teste', 'org-teste-' || replace(gen_random_uuid()::text, '-', ''), 0)
  returning id into v_org;
  execute format('alter table public.eventos alter column organizacao_id set default %L::uuid', v_org);
  perform set_config('teste.organizacao_id', v_org::text, true);
end
$fx$;

create function private.teste_vincular_membro()
returns trigger
language plpgsql
set search_path = ''
as $fx$
begin
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil, ativo)
  values (current_setting('teste.organizacao_id')::uuid, new.id, new.perfil, true)
  on conflict (organizacao_id, usuario_id) do update set perfil = excluded.perfil;
  return new;
end
$fx$;

create trigger trg_teste_vincular_membro
  after insert or update of perfil on public.usuarios
  for each row execute function private.teste_vincular_membro();
-- [/Ingressoudi] ------------------------------------------------------------------

do $$
declare
  v_org uuid := current_setting('teste.organizacao_id')::uuid;
  v_outra uuid;
  v_dono uuid := gen_random_uuid();
  v_super uuid := gen_random_uuid();
  v_taxa numeric;
  v_n integer;
begin
  -- casa onde o super admin NAO e membro
  insert into public.organizacoes (nome, slug, taxa_servico)
  values ('Casa Outra', 'casa-outra-' || replace(gen_random_uuid()::text, '-', ''), 1.00)
  returning id into v_outra;

  insert into auth.users (id) values (v_dono), (v_super);
  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin) values
    (v_dono, 'Dono Casa', 'dono_' || replace(v_dono::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false),
    (v_super, 'Super Taxa', 'supertaxa_' || replace(v_super::text,'-','') || '@test.local', 'ADMINISTRADOR', true, true);
  -- o dono passa a ser membro (administrador) da casa outra; o super admin nao
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil, ativo)
  values (v_outra, v_dono, 'ADMINISTRADOR', true);
  delete from public.membros_organizacao where organizacao_id = v_outra and usuario_id = v_super;

  -- A) dono da casa nao altera a taxa (nem pela RPC nem direto na tabela)
  perform set_config('request.jwt.claims', json_build_object('sub', v_dono::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_dono::text, true);
  begin
    perform public.definir_taxa_organizacao(v_outra, 0);
    raise exception 'A: dono nao deveria alterar a taxa';
  exception when others then
    if position('super administrador' in sqlerrm) = 0 then raise exception 'A: %', sqlerrm; end if;
  end;
  if has_table_privilege('authenticated', 'public.organizacoes', 'UPDATE') then
    raise exception 'A: authenticated nao pode ter UPDATE em organizacoes'; end if;
  if has_column_privilege('authenticated', 'public.organizacoes', 'taxa_servico', 'UPDATE') then
    raise exception 'A: authenticated nao pode alterar taxa_servico'; end if;
  begin
    perform public.listar_organizacoes_plataforma();
    raise exception 'A: dono nao deveria listar as casas';
  exception when others then
    if position('super administrador' in sqlerrm) = 0 then raise exception 'A: %', sqlerrm; end if;
  end;

  -- B) super admin ve a taxa de cada casa e altera uma casa da qual nao e membro
  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);
  select (o->>'taxa_servico')::numeric into v_taxa
    from jsonb_array_elements(public.listar_organizacoes_plataforma()) o
   where o->>'organizacao_id' = v_outra::text;
  if v_taxa is distinct from 1.00 then raise exception 'B: lista deveria trazer a taxa (%)', v_taxa; end if;

  perform public.definir_taxa_organizacao(v_outra, 2.50);
  select taxa_servico into v_taxa from public.organizacoes where id = v_outra;
  if v_taxa <> 2.50 then raise exception 'B: taxa nao alterada (%)', v_taxa; end if;
  select count(*) into v_n from public.auditoria where acao = 'ORGANIZACAO_TAXA_DEFINIDA' and entidade_id = v_outra;
  if v_n <> 1 then raise exception 'B: auditoria ausente'; end if;
end $$;

select 'taxa_por_casa_plataforma: todos os testes passaram' as resultado;

rollback;
