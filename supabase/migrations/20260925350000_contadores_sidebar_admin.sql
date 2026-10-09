-- =============================================================================
-- GZ1 Ingresso - Contadores do sidebar administrativo (somente leitura)
-- Migration: contadores_sidebar_admin
--
-- RPC ADMIN-only e leve (apenas contagens agregadas, sem carregar linhas) para
-- os badges do sidebar:
--   pedidos  = total real de pedidos (public.pedidos)
--   entradas = entradas efetivas, ou seja, nao anuladas (anulada_em is null).
--              Nao conta tentativas recusadas (tentativas_entrada).
--
-- Nao expoe tokens/segredos e nao altera RLS/ACL.
-- =============================================================================

create or replace function public.obter_contadores_admin()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_pedidos integer;
  v_entradas integer;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select count(*) into v_pedidos
    from public.pedidos;

  select count(*) into v_entradas
    from public.entradas en
   where en.anulada_em is null;

  return jsonb_build_object(
    'pedidos', v_pedidos,
    'entradas', v_entradas
  );
end;
$$;

revoke execute on function public.obter_contadores_admin() from public, anon, authenticated, service_role;
grant execute on function public.obter_contadores_admin() to authenticated, service_role;

comment on function public.obter_contadores_admin() is 'Contagens agregadas leves para os badges do sidebar (ADMINISTRADOR): total de pedidos e entradas efetivas (nao anuladas). Sem tokens.';
