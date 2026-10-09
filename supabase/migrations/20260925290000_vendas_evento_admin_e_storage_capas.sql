-- =============================================================================
-- GZ1 Ingresso - Vendas do evento (abrir/encerrar) + Storage de capas
-- Migration: vendas_evento_admin_e_storage_capas
--
-- 1) Abertura/fechamento de vendas via RPC de dominio (ADMINISTRADOR):
--      public.definir_vendas_evento_admin(p_evento_id, p_vendas_status)
--    Mantem a regra de ativar_lote_manual (vendas ABERTAS) como fonte de verdade;
--    a RPC apenas permite o admin abrir/fechar as vendas de forma auditada.
--
-- 2) Bucket publico de capas de evento (leitura publica, escrita ADMIN).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Definir vendas_status
-- -----------------------------------------------------------------------------
create or replace function private.definir_vendas_evento_admin(
  p_evento_id uuid,
  p_vendas_status public.status_vendas
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_evento public.eventos%rowtype;
  v_anterior public.status_vendas;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  if p_vendas_status is null then
    raise exception 'Informe o status de vendas' using errcode = '23514';
  end if;

  select * into v_evento from public.eventos e where e.id = p_evento_id for update;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if v_evento.status in ('REALIZADO', 'CANCELADO') then
    raise exception 'Evento % nao permite alterar vendas (status=%)', p_evento_id, v_evento.status using errcode = '23514';
  end if;

  v_anterior := v_evento.vendas_status;

  if v_anterior <> p_vendas_status then
    update public.eventos set vendas_status = p_vendas_status, atualizado_em = now() where id = p_evento_id;

    insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
    values (
      auth.uid(),
      'EVENTO_VENDAS_ALTERADAS',
      'eventos',
      p_evento_id,
      jsonb_build_object('vendas_status', v_anterior),
      jsonb_build_object('vendas_status', p_vendas_status)
    );
  end if;

  return jsonb_build_object('evento_id', p_evento_id, 'vendas_status', p_vendas_status);
end;
$$;

create or replace function public.definir_vendas_evento_admin(
  p_evento_id uuid,
  p_vendas_status public.status_vendas
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.definir_vendas_evento_admin(p_evento_id, p_vendas_status);
$$;

-- -----------------------------------------------------------------------------
-- 2) Storage: bucket publico de capas de evento
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('eventos-capas', 'eventos-capas', true, 5242880, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Leitura publica (capa usada na pagina publica do evento)
drop policy if exists "eventos_capas_leitura_publica" on storage.objects;
create policy "eventos_capas_leitura_publica" on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'eventos-capas');

-- Escrita apenas ADMINISTRADOR
drop policy if exists "eventos_capas_insert_admin" on storage.objects;
create policy "eventos_capas_insert_admin" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'eventos-capas' and private.usuario_e_admin());

drop policy if exists "eventos_capas_update_admin" on storage.objects;
create policy "eventos_capas_update_admin" on storage.objects
  for update to authenticated
  using (bucket_id = 'eventos-capas' and private.usuario_e_admin())
  with check (bucket_id = 'eventos-capas' and private.usuario_e_admin());

drop policy if exists "eventos_capas_delete_admin" on storage.objects;
create policy "eventos_capas_delete_admin" on storage.objects
  for delete to authenticated
  using (bucket_id = 'eventos-capas' and private.usuario_e_admin());

-- -----------------------------------------------------------------------------
-- ACL
-- -----------------------------------------------------------------------------
-- Storage policy pode chamar private.usuario_e_admin() no contexto do usuario.
grant execute on function private.usuario_e_admin() to authenticated;

revoke all on function private.definir_vendas_evento_admin(uuid, public.status_vendas) from public;
grant execute on function private.definir_vendas_evento_admin(uuid, public.status_vendas) to authenticated, service_role;

revoke execute on function public.definir_vendas_evento_admin(uuid, public.status_vendas)
  from public, anon, authenticated, service_role;
grant execute on function public.definir_vendas_evento_admin(uuid, public.status_vendas)
  to authenticated, service_role;

comment on function public.definir_vendas_evento_admin(uuid, public.status_vendas) is
  'Abre/encerra as vendas de um evento (ADMINISTRADOR). Nao altera eventos REALIZADO/CANCELADO.';
