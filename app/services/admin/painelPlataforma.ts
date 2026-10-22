import { mapearPainelPlataforma, type PainelPlataforma } from '~/utils/painelPlataforma'

/** Numeros de todas as casas para o Painel da plataforma (somente super admin). */
export async function obterPainelPlataforma(desde: string | null): Promise<PainelPlataforma> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_painel_plataforma', { p_desde: desde })
  if (error) {
    const m = (error.message ?? '').toLowerCase()
    if (m.includes('permiss')) throw new Error('Apenas o super administrador vê o painel da plataforma.')
    throw new Error('Não foi possível carregar o painel da plataforma.')
  }
  return mapearPainelPlataforma(data)
}
