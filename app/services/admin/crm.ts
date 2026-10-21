import {
  dadosParaBanco,
  mapearIndicadoresCrm,
  mapearProdutorCrm,
  type FormProdutorCrm,
  type IndicadoresCrm,
  type ProdutorCrm
} from '~/utils/crm'

function mensagemErro(mensagem: string | undefined, padrao: string): string {
  const m = (mensagem ?? '').toLowerCase()
  if (m.includes('permiss')) return 'Apenas o super administrador acessa o CRM.'
  if (m.includes('nome do produtor')) return 'Informe o nome do produtor.'
  if (m.includes('ja esta ligada')) return 'Essa casa já está ligada a outro produtor do CRM.'
  if (m.includes('nao encontrad')) return 'Registro não encontrado. Atualize a página.'
  if (m.includes('periodo invalido')) return 'A data final deve ser igual ou posterior à inicial.'
  return padrao
}

/** Produtores do CRM, com os numeros reais das casas ligadas (somente super admin). */
export async function listarProdutoresCrm(): Promise<ProdutorCrm[]> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('crm_listar_produtores')
  if (error) throw new Error(mensagemErro(error.message, 'Não foi possível carregar o CRM.'))
  return ((data ?? []) as Array<Record<string, unknown>>).map(mapearProdutorCrm)
}

/** Cria (id null) ou atualiza um produtor. */
export async function salvarProdutorCrm(id: string | null, form: FormProdutorCrm): Promise<string> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('crm_salvar_produtor', { p_id: id, p_dados: dadosParaBanco(form) })
  if (error) throw new Error(mensagemErro(error.message, 'Não foi possível salvar o produtor.'))
  return String((data as Record<string, unknown> | null)?.id ?? id ?? '')
}

export async function excluirProdutorCrm(id: string): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('crm_excluir_produtor', { p_id: id })
  if (error) throw new Error(mensagemErro(error.message, 'Não foi possível excluir o produtor.'))
}

/** Traz para o CRM as casas da plataforma que ainda nao estao nele. */
export async function importarCasasCrm(): Promise<number> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('crm_importar_casas')
  if (error) throw new Error(mensagemErro(error.message, 'Não foi possível importar as casas.'))
  return Number((data as Record<string, unknown> | null)?.importados ?? 0)
}

/** Funil e indicadores; sem datas = desde o inicio. */
export async function obterIndicadoresCrm(inicio: string | null, fim: string | null): Promise<IndicadoresCrm> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('crm_indicadores', { p_inicio: inicio, p_fim: fim })
  if (error || !data) throw new Error(mensagemErro(error?.message, 'Não foi possível carregar os indicadores.'))
  return mapearIndicadoresCrm(data as Record<string, unknown>)
}
