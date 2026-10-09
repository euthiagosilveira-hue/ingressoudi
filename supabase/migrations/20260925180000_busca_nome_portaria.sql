-- =============================================================================
-- GZ1 Ingresso - Busca por nome da portaria tolerante (sem filtro de status)
-- Migration: busca_nome_portaria
--
-- Objetivo: manter ingressos ja UTILIZADOS visiveis na busca por nome e tornar
-- o match mais tolerante (case/acento/espaco/ordem das palavras), preservando
-- a assinatura, o SECURITY DEFINER e a ACL atuais.
--
-- Importante: NAO filtra por status (VALIDO e UTILIZADO aparecem; CANCELADO/
-- EXPIRADO/RESERVADO continuam aparecendo conforme regra atual). A decisao de
-- entrada continua exclusiva de registrar_entrada_nome/registrar_entrada_qr.
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
             jsonb_agg(
               jsonb_build_object(
                 'ingresso_id', i.id,
                 'codigo', i.codigo,
                 'participante_nome', i.participante_nome,
                 'status', i.status,
                 'utilizado_em', i.utilizado_em
               ) order by i.participante_nome, i.codigo
             ),
             '[]'::jsonb
           )
      from public.ingressos i
     where i.evento_id = p_evento_id
       -- todos os tokens digitados precisam aparecer no nome (ordem livre)
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
  );
end;
$$;

-- ACL (preservada / reafirmada) ----------------------------------------------
grant usage on schema private to authenticated, service_role;

revoke all on function private.buscar_ingressos_por_nome(uuid, text) from public;
grant execute on function private.buscar_ingressos_por_nome(uuid, text) to authenticated, service_role;

revoke execute on function public.buscar_ingressos_por_nome(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.buscar_ingressos_por_nome(uuid, text) to authenticated, service_role;

comment on function public.buscar_ingressos_por_nome(uuid, text) is
  'Busca ingressos por nome no evento (case/acento/ordem tolerantes). Inclui '
  'UTILIZADO. Nao filtra por status; entrada continua via registrar_entrada_*.';
