/** Erros de pagamento da plataforma (somente super admin). Sem dependencias, para testes. */

export type TipoErroPagamento =
  | 'PIX_CRIACAO'
  | 'CONTA_MP_DESCONECTADA'
  | 'TOKEN_MP'
  | 'OAUTH_MP'
  | 'WEBHOOK'
  | 'CONFIRMACAO'
  | 'VALOR_DIVERGENTE'
  | 'REEMBOLSO'
  | 'CONFIGURACAO'

export interface ErroPagamento {
  id: string
  tipo: TipoErroPagamento
  mensagem: string
  detalhe: Record<string, unknown> | null
  referencia: string | null
  avisado: boolean
  criadoEm: string
  organizacaoId: string | null
  organizacaoNome: string | null
}

export const ROTULOS_TIPO_ERRO: Record<TipoErroPagamento, string> = {
  PIX_CRIACAO: 'Geração do Pix',
  CONTA_MP_DESCONECTADA: 'Mercado Pago não conectado',
  TOKEN_MP: 'Token do Mercado Pago',
  OAUTH_MP: 'Conexão do Mercado Pago',
  WEBHOOK: 'Aviso do Mercado Pago',
  CONFIRMACAO: 'Confirmação do pagamento',
  VALOR_DIVERGENTE: 'Valor divergente',
  REEMBOLSO: 'Reembolso',
  CONFIGURACAO: 'Configuração'
}

export function rotuloTipoErro(tipo: string): string {
  return ROTULOS_TIPO_ERRO[tipo as TipoErroPagamento] ?? tipo
}

export function mapearErroPagamento(linha: Record<string, unknown>): ErroPagamento {
  const detalhe = linha.detalhe
  return {
    id: String(linha.id ?? ''),
    tipo: String(linha.tipo ?? '') as TipoErroPagamento,
    mensagem: String(linha.mensagem ?? ''),
    detalhe: detalhe && typeof detalhe === 'object' && !Array.isArray(detalhe) ? (detalhe as Record<string, unknown>) : null,
    referencia: linha.referencia ? String(linha.referencia) : null,
    avisado: Boolean(linha.avisado),
    criadoEm: String(linha.criado_em ?? ''),
    organizacaoId: linha.organizacao_id ? String(linha.organizacao_id) : null,
    organizacaoNome: linha.organizacao_nome ? String(linha.organizacao_nome) : null
  }
}

export type PeriodoErros = '24H' | '7D' | 'TODOS'

export function filtrarErrosPagamento(
  erros: ErroPagamento[],
  filtro: { tipo: string; periodo: PeriodoErros },
  agoraMs: number
): ErroPagamento[] {
  const limite =
    filtro.periodo === '24H' ? agoraMs - 24 * 3600_000 : filtro.periodo === '7D' ? agoraMs - 7 * 24 * 3600_000 : null
  return erros.filter((e) => {
    if (filtro.tipo && e.tipo !== filtro.tipo) return false
    if (limite !== null) {
      const t = Date.parse(e.criadoEm)
      if (Number.isNaN(t) || t < limite) return false
    }
    return true
  })
}

/** Quantos erros por tipo, do mais frequente para o menos. */
export function contarPorTipo(erros: ErroPagamento[]): Array<{ tipo: TipoErroPagamento; total: number }> {
  const mapa = new Map<TipoErroPagamento, number>()
  for (const e of erros) mapa.set(e.tipo, (mapa.get(e.tipo) ?? 0) + 1)
  return [...mapa.entries()].map(([tipo, total]) => ({ tipo, total })).sort((a, b) => b.total - a.total)
}

/** Detalhe tecnico em texto curto para exibir (ou null se nao houver). */
export function textoDetalhe(detalhe: Record<string, unknown> | null): string | null {
  if (!detalhe) return null
  const partes = Object.entries(detalhe)
    .filter(([, v]) => v !== null && v !== undefined && v !== '')
    .map(([k, v]) => `${k}: ${typeof v === 'object' ? JSON.stringify(v) : String(v)}`)
  return partes.length ? partes.join(' · ') : null
}
