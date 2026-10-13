/**
 * Taxa de servico exibida ao comprador. O valor cobrado de verdade e sempre
 * calculado pelo banco (criar_reserva); aqui e so a previa do checkout.
 */
export interface ValoresCheckout {
  valorIngressos: number
  valorTaxa: number
  total: number
}

function centavos(valor: number): number {
  return Math.round(valor * 100) / 100
}

/** `taxaPorIngresso` ja vem 0 quando o produtor absorve a taxa. */
export function calcularValoresCheckout(
  preco: number | null | undefined,
  quantidade: number,
  taxaPorIngresso: number | null | undefined
): ValoresCheckout {
  const qtd = Math.max(0, Math.floor(quantidade || 0))
  const valorIngressos = centavos((preco ?? 0) * qtd)
  const taxa = Math.max(0, Number(taxaPorIngresso ?? 0) || 0)
  const valorTaxa = centavos(taxa * qtd)
  return { valorIngressos, valorTaxa, total: centavos(valorIngressos + valorTaxa) }
}

/** Taxa que o comprador paga (0 quando absorvida pelo produtor). */
export function taxaVisivelAoComprador(
  valorTaxaTotal: number | null | undefined,
  taxaRepassada: boolean | null | undefined
): number {
  if (taxaRepassada === false) return 0
  return Math.max(0, Number(valorTaxaTotal ?? 0) || 0)
}
