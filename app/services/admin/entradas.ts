import type { AdminEntryRow, EntryMethod, EntryStateFilter } from '~/types/entrada'

export interface AdminEntryFiltros {
  eventoId?: string | null
  busca?: string | null
  de?: string | null
  ate?: string | null
  metodo?: EntryMethod | null
  situacao?: EntryStateFilter | null
}

/** Listagem administrativa real de entradas (RPC segura, ADMINISTRADOR). */
export async function listarEntradasAdmin(
  filtros: AdminEntryFiltros = {}
): Promise<AdminEntryRow[]> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('listar_entradas_admin', {
    p_evento_id: filtros.eventoId ?? null,
    p_busca: filtros.busca?.trim() ? filtros.busca.trim() : null,
    p_de: filtros.de ?? null,
    p_ate: filtros.ate ?? null,
    p_metodo: filtros.metodo ?? null,
    p_situacao: filtros.situacao ?? null
  })
  if (error) {
    throw new Error('Não foi possível carregar as entradas.')
  }
  return (data ?? []) as AdminEntryRow[]
}
