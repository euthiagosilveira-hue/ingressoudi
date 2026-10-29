-- =============================================================================
-- Ingressoudi - Busca de ingressos por telefone + e-mail (sem codigo do pedido)
-- Migration: busca_ingressos_telefone_email
--
--   * public.buscar_ingressos_contato(telefone, email)
--       -> { ok, pedidos: [{ pedido_id, codigo_pedido, checkout_token,
--            organizacao_slug, evento_slug, evento_nome, evento_inicio_em,
--            evento_local, quantidade }] }
--
-- Telefone E e-mail precisam casar com o mesmo pedido PAGO/APROVADO. Devolve o
-- checkout_token (o mesmo do link da compra) para o comprador guardar no
-- aparelho e mandar o link para o proprio WhatsApp. Nunca devolve qr_token.
-- Somente eventos a partir de 2 dias atras. Rate limit por telefone (5 falhas
-- em 15 min) usando public.tentativas_recuperacao. Resposta sempre generica.
-- =============================================================================

create or replace function private.buscar_ingressos_contato(p_telefone text, p_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_digitos text;
  v_email text;
  v_chave text;
  v_tentativas integer;
  v_pedidos jsonb;
begin
  v_digitos := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  -- aceita com ou sem o 55 do Brasil
  if length(v_digitos) >= 12 and left(v_digitos, 2) = '55' then
    v_digitos := substr(v_digitos, 3);
  end if;
  v_email := lower(btrim(coalesce(p_email, '')));

  if length(v_digitos) < 10 or position('@' in v_email) < 2 then
    return jsonb_build_object('ok', false);
  end if;

  v_chave := 'CONTATO:' || v_digitos;

  select count(*) into v_tentativas
    from public.tentativas_recuperacao t
   where t.codigo_normalizado = v_chave
     and t.sucesso = false
     and t.criado_em > now() - interval '15 minutes';

  if v_tentativas >= 5 then
    insert into public.tentativas_recuperacao (codigo_normalizado, sucesso)
    values (v_chave, false);
    return jsonb_build_object('ok', false);
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'pedido_id', x.id,
               'codigo_pedido', x.codigo,
               'checkout_token', x.checkout_token,
               'organizacao_slug', x.organizacao_slug,
               'evento_slug', x.evento_slug,
               'evento_nome', x.evento_nome,
               'evento_inicio_em', x.inicio_em,
               'evento_local', x.local,
               'quantidade', x.quantidade
             ) order by x.inicio_em, x.codigo
           ),
           '[]'::jsonb
         )
    into v_pedidos
    from (
      select p.id, p.codigo, p.checkout_token,
             o.slug as organizacao_slug, e.slug as evento_slug, e.nome as evento_nome,
             e.inicio_em, e.local,
             (select count(*) from public.ingressos i
               where i.pedido_id = p.id and i.status in ('VALIDO', 'UTILIZADO'))::integer as quantidade
        from public.pedidos p
        join public.eventos e on e.id = p.evento_id
        left join public.organizacoes o on o.id = e.organizacao_id
       where lower(btrim(coalesce(p.comprador_email, ''))) = v_email
         and p.status = 'PAGO'
         and e.inicio_em > now() - interval '2 days'
         and v_digitos in (
               regexp_replace(coalesce(p.comprador_telefone, ''), '\D', '', 'g'),
               '55' || regexp_replace(coalesce(p.comprador_telefone, ''), '\D', '', 'g'),
               substr(regexp_replace(coalesce(p.comprador_telefone, ''), '\D', '', 'g'), 3)
             )
         and exists (
           select 1 from public.pagamentos pg
            where pg.pedido_id = p.id and pg.status = 'APROVADO'
         )
       order by e.inicio_em, p.codigo
       limit 20
    ) x;

  insert into public.tentativas_recuperacao (codigo_normalizado, sucesso)
  values (v_chave, jsonb_array_length(v_pedidos) > 0);

  if jsonb_array_length(v_pedidos) = 0 then
    return jsonb_build_object('ok', false);
  end if;

  return jsonb_build_object('ok', true, 'pedidos', v_pedidos);
end;
$$;

create or replace function public.buscar_ingressos_contato(p_telefone text, p_email text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.buscar_ingressos_contato(p_telefone, p_email);
$$;

revoke all on function private.buscar_ingressos_contato(text, text) from public;
grant execute on function private.buscar_ingressos_contato(text, text) to anon, authenticated, service_role;

revoke execute on function public.buscar_ingressos_contato(text, text) from public, anon, authenticated, service_role;
grant execute on function public.buscar_ingressos_contato(text, text) to anon, authenticated, service_role;

comment on function public.buscar_ingressos_contato(text, text) is
  'Pedidos pagos do comprador por telefone + e-mail (eventos a partir de 2 dias atras). Resposta generica.';
