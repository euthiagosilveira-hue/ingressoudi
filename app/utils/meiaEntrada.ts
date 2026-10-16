/**
 * Meia-entrada (Lei 12.933/2013). O produtor liga a opcao no evento; a meia
 * vale 50% do preco do lote, arredondada em centavos (mesma regra do banco,
 * private.preco_meia). A taxa de servico por ingresso nao muda.
 * O valor cobrado de verdade e sempre calculado pelo banco (criar_reserva).
 */

export const AVISO_MEIA_ENTRADA =
  'Apresente na entrada um documento que comprove o direito à meia-entrada (estudante, idoso, pessoa com deficiência ou ID Jovem).'

function centavos(valor: number): number {
  return Math.round(valor * 100) / 100
}

/** Preco da meia a partir do preco da inteira. */
export function precoMeia(preco: number | null | undefined): number {
  const valor = Number(preco ?? 0)
  if (!Number.isFinite(valor) || valor <= 0) return 0
  const centavosInteira = Math.round(valor * 100)
  return Math.round(centavosInteira / 2) / 100
}

/** Quantos itens estao marcados como meia-entrada. */
export function contarMeias(itens: ReadonlyArray<{ meia?: boolean | null }>): number {
  return itens.reduce((total, item) => total + (item.meia ? 1 : 0), 0)
}

/** Soma dos ingressos com inteiras e meias (sem taxa). */
export function valorIngressosComMeia(
  preco: number | null | undefined,
  quantidade: number,
  quantidadeMeia = 0
): number {
  const qtd = Math.max(0, Math.floor(quantidade || 0))
  const meias = Math.min(qtd, Math.max(0, Math.floor(quantidadeMeia || 0)))
  return centavos((preco ?? 0) * (qtd - meias) + precoMeia(preco) * meias)
}

/** Rotulo curto do tipo do ingresso. */
export function rotuloTipoIngresso(meia: boolean | null | undefined): string {
  return meia ? 'Meia-entrada' : 'Inteira'
}
