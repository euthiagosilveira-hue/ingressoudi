-- =============================================================================
-- GZ1 Ingresso - Portaria: busca por nome com desambiguacao (telefone)
-- Migration: portaria_busca_nome_desambiguacao
--
-- Reaplica private/public.buscar_ingressos_por_nome adicionando SOMENTE o
-- campo 'telefone' a cada resultado, para o operador desambiguar homonimos:
--   * INGRESSO -> telefone do comprador (pedidos.comprador_telefone);
--   * VIP      -> telefone da lista (lista_vip.telefone), pode ser null.
--
-- Preserva integralmente:
--   * assinatura (uuid, text);
--   * permissao (ADMINISTRADOR/PORTARIA via private.usuario_pode_operar_portaria);
--   * busca case/acento/ordem tolerante;
--   * resultados de INGRESSO + VIP com origem/status/ids existentes;
--   * nenhuma informacao financeira (valor, pagamento, email).
--
-- O telefone vai cru na resposta (RPC restrita a operadores) e e MASCARADO no
-- frontend antes de exibir. Pode ser null (VIP sem telefone / venda manual).
-- =============================================================================

create or replace function private.buscar_ingressos_por_nome(p_evento_id uuid, p_nome text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_alvo text;
begin
  if not private.usuario_pode_operar_portaria() then
    raise exception 'Permissao negada para operar portaria' using errcode = '42501';
  end if;

  v_alvo := translate(
    lower(btrim(coalesce(p_nome, ''))),
    'áàâãäéèêëíìîïóòôõöúùûüçñ',
    'aaaaaeeeeiiiiooooouuuucn'
  );

  if v_alvo = '' then
    return '[]'::jsonb;
  end if;

  return (
    select coalesce(
             jsonb_agg(item order by item->>'participante_nome', item->>'origem'),
             '[]'::jsonb
           )
      from (
        -- Ingressos normais
        select jsonb_build_object(
                 'origem', 'INGRESSO',
                 'ingresso_id', i.id,
                 'vip_id', null,
                 'codigo', i.codigo,
                 'participante_nome', i.participante_nome,
                 'status', i.status,
                 'utilizado_em', i.utilizado_em,
                 'entrada_em', i.utilizado_em,
                 'telefone', (
                   select p.comprador_telefone
                     from public.pedidos p
                    where p.id = i.pedido_id
                 )
               ) as item
          from public.ingressos i
         where i.evento_id = p_evento_id
           and not exists (
             select 1
               from unnest(string_to_array(v_alvo, ' ')) as tok
              where btrim(tok) <> ''
                and position(
                      btrim(tok) in translate(
                        lower(i.participante_nome),
                        'áàâãäéèêëíìîïóòôõöúùûüçñ',
                        'aaaaaeeeeiiiiooooouuuucn'
                      )
                    ) = 0
           )
        union all
        -- Lista VIP (apenas ativos); status derivado da entrada
        select jsonb_build_object(
                 'origem', 'VIP',
                 'ingresso_id', null,
                 'vip_id', lv.id,
                 'codigo', null,
                 'participante_nome', lv.nome,
                 'status', case when ev.id is null then 'VALIDO' else 'UTILIZADO' end,
                 'utilizado_em', ev.entrada_em,
                 'entrada_em', ev.entrada_em,
                 'telefone', lv.telefone
               ) as item
          from public.lista_vip lv
          left join lateral (
            select e.id, e.entrada_em
              from public.entradas_vip e
             where e.lista_vip_id = lv.id
               and e.anulada_em is null
             order by e.entrada_em desc
             limit 1
          ) ev on true
         where lv.evento_id = p_evento_id
           and lv.ativo = true
           and not exists (
             select 1
               from unnest(string_to_array(v_alvo, ' ')) as tok
              where btrim(tok) <> ''
                and position(
                      btrim(tok) in translate(
                        lower(lv.nome),
                        'áàâãäéèêëíìîïóòôõöúùûüçñ',
                        'aaaaaeeeeiiiiooooouuuucn'
                      )
                    ) = 0
           )
      ) t
  );
end;
$$;

create or replace function public.buscar_ingressos_por_nome(p_evento_id uuid, p_nome text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select private.buscar_ingressos_por_nome(p_evento_id, p_nome); $$;

-- ACL
grant usage on schema private to authenticated, service_role;

revoke all on function private.buscar_ingressos_por_nome(uuid, text) from public;
grant execute on function private.buscar_ingressos_por_nome(uuid, text) to authenticated, service_role;

revoke execute on function public.buscar_ingressos_por_nome(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.buscar_ingressos_por_nome(uuid, text) to authenticated, service_role;

comment on function public.buscar_ingressos_por_nome(uuid, text) is
  'Busca por nome no evento (ingressos + Lista VIP), tolerante a acento/ordem, com telefone para desambiguacao. Campo origem = INGRESSO|VIP. Sem valores/pagamento.';
