import type { PaymentProvider } from '~/types/pagamento'

const ROTULOS: Record<PaymentProvider, string> = {
  STONE: 'Stone',
  MERCADO_PAGO: 'Mercado Pago',
  DINHEIRO: 'Dinheiro'
}

export function rotuloProvider(provider: PaymentProvider): string {
  return ROTULOS[provider]
}

/**
 * Valor exato a ser codificado no QR Code do Pix. Deve ser o proprio
 * pix_copia_cola para que o QR decodifique exatamente para o payload.
 */
export function valorQrPix(
  pix: { pixCopyPaste?: string | null } | null | undefined
): string | null {
  const codigo = pix?.pixCopyPaste?.trim()
  return codigo ? codigo : null
}
