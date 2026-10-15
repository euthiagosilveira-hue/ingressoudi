-- =============================================================================
-- Ingressoudi - Higiene de seguranca: funcoes de trigger sem EXECUTE para
-- PUBLIC/anon/authenticated. Triggers continuam funcionando (o privilegio so e
-- exigido ao criar o trigger), mas a funcao deixa de aparecer como "exposta".
-- =============================================================================
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as fn
      from pg_proc p
     where p.pronamespace in ('public'::regnamespace, 'private'::regnamespace)
       and p.prorettype = 'trigger'::regtype
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.fn);
  end loop;
end $$;
