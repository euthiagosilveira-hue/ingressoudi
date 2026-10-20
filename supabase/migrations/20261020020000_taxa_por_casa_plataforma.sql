-- =============================================================================
-- Migration: taxa_por_casa_plataforma
--
-- A taxa de servico de cada casa e controle exclusivo do super admin
-- (definir_taxa_organizacao ja exige super admin; a tabela organizacoes nao
-- tem permissao de escrita para os usuarios). Esta migration so passa a
-- devolver a taxa na lista de casas, para o super admin ajustar qualquer casa
-- sem precisar ser membro dela.
-- =============================================================================

create or replace function private.listar_organizacoes_plataforma()
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
             'nome', o.nome,
             'slug', o.slug,
             'ativo', o.ativo,
             'aprovada', o.aprovada,
             'lista_vip_ativa', o.lista_vip_ativa,
             'taxa_servico', o.taxa_servico,
             'criado_em', o.criado_em,
             'mercado_pago_conectado', exists (
               select 1 from public.organizacoes_mercado_pago mp where mp.organizacao_id = o.id),
             'administradores', coalesce((
               select string_agg(u.email, ', ' order by u.email)
                 from public.membros_organizacao m
                 join public.usuarios u on u.id = m.usuario_id
                where m.organizacao_id = o.id and m.ativo and m.perfil = 'ADMINISTRADOR'), ''),
             'eventos', (select count(*) from public.eventos e where e.organizacao_id = o.id)
           ) order by o.aprovada, o.criado_em desc)
      from public.organizacoes o
  ), '[]'::jsonb);
end;
$$;
