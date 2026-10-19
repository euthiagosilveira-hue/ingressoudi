import { mapearEventoPlataforma, type EventoPlataforma } from '~/utils/eventosPlataforma'

/** Todos os eventos de todas as casas (somente super admin). */
export async function listarEventosPlataforma(): Promise<EventoPlataforma[]> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('listar_eventos_plataforma')
  if (error) {
    const m = (error.message ?? '').toLowerCase()
    if (m.includes('permiss')) throw new Error('Apenas o super administrador vê os eventos de todas as casas.')
    throw new Error('Não foi possível carregar os eventos.')
  }
  return ((data ?? []) as Array<Record<string, unknown>>).map(mapearEventoPlataforma)
}
