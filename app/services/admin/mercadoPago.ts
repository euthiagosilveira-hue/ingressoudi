export interface StatusMercadoPago {
  conectado: boolean
  mpUserId: string | null
  liveMode: boolean | null
  conectadoEm: string | null
  expiraEm: string | null
  taxaServico: number
}

interface StatusRow {
  conectado: boolean
  mp_user_id: string | null
  live_mode: boolean | null
  conectado_em: string | null
  expira_em: string | null
  taxa_servico: number | string | null
}

export interface TaxaEvento {
  taxaRepassada: boolean
  taxaServico: number
}

function mensagem(erro: { message?: string } | null, padrao: string): string {
  const m = (erro?.message ?? '').toLowerCase()
  if (m.includes('permiss')) return 'Você não tem permissão para esta ação.'
  if (m.includes('nao encontrad')) return 'Registro não encontrado.'
  return padrao
}

/** Status da conta Mercado Pago da organizacao ativa (nunca expoe tokens). */
export async function obterStatusMercadoPago(): Promise<StatusMercadoPago> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_status_mercado_pago')
  if (error || !data) throw new Error(mensagem(error, 'Não foi possível carregar o Mercado Pago.'))
  const row = data as StatusRow
  return {
    conectado: Boolean(row.conectado),
    mpUserId: row.mp_user_id,
    liveMode: row.live_mode,
    conectadoEm: row.conectado_em,
    expiraEm: row.expira_em,
    taxaServico: Number(row.taxa_servico ?? 0)
  }
}

export async function desconectarMercadoPago(): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('desconectar_mercado_pago')
  if (error) throw new Error(mensagem(error, 'Não foi possível desconectar o Mercado Pago.'))
}

/** Somente super admin. */
export async function definirTaxaOrganizacao(organizacaoId: string, taxa: number): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('definir_taxa_organizacao', {
    p_organizacao_id: organizacaoId,
    p_taxa: taxa
  })
  if (error) throw new Error(mensagem(error, 'Não foi possível salvar a taxa.'))
}

export async function obterTaxaEvento(eventoId: string): Promise<TaxaEvento> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_evento_admin', { p_evento_id: eventoId })
  if (error || !data) throw new Error(mensagem(error, 'Não foi possível carregar a taxa do evento.'))
  const row = data as { taxa_repassada?: boolean | null; taxa_servico?: number | string | null }
  return {
    taxaRepassada: row.taxa_repassada !== false,
    taxaServico: Number(row.taxa_servico ?? 0)
  }
}

export async function definirTaxaEvento(eventoId: string, taxaRepassada: boolean): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('definir_taxa_evento_admin', {
    p_evento_id: eventoId,
    p_taxa_repassada: taxaRepassada
  })
  if (error) throw new Error(mensagem(error, 'Não foi possível salvar a taxa do evento.'))
}
