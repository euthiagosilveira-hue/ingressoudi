import { mapearCasaComDono, type CasaComDono } from '~/utils/donosPlataforma'

/** Donos de todas as casas (somente super admin). */
export async function listarDonosPlataforma(): Promise<CasaComDono[]> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('listar_donos_plataforma')
  if (error) {
    const m = (error.message ?? '').toLowerCase()
    if (m.includes('permiss')) throw new Error('Apenas o super administrador vê os donos das casas.')
    throw new Error('Não foi possível carregar os donos das casas.')
  }
  return ((data ?? []) as Array<Record<string, unknown>>).map(mapearCasaComDono)
}
