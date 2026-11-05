/** Cartao de credito no checkout publico (Mercado Pago Card Payment Brick). */

export interface ConfigCartaoPublico {
  disponivel: boolean
  publicKey: string | null
  valor: number
  maxParcelas: number
  tentativasRestantes: number
  email: string | null
}

const SDK_URL = 'https://sdk.mercadopago.com/js/v2'

// Tipagem minima do SDK v2 (window.MercadoPago).
type MercadoPagoCtor = new (
  publicKey: string,
  opcoes?: { locale?: string }
) => {
  bricks: () => {
    create: (tipo: string, containerId: string, settings: Record<string, unknown>) => Promise<{ unmount: () => void }>
  }
}

let carregamento: Promise<MercadoPagoCtor> | null = null

/** Carrega o SDK do Mercado Pago uma vez (so no navegador). */
export function carregarSdkMercadoPago(): Promise<MercadoPagoCtor> {
  const janela = window as unknown as { MercadoPago?: MercadoPagoCtor }
  if (janela.MercadoPago) return Promise.resolve(janela.MercadoPago)
  if (carregamento) return carregamento
  carregamento = new Promise<MercadoPagoCtor>((resolve, reject) => {
    const script = document.createElement('script')
    script.src = SDK_URL
    script.async = true
    script.onload = () => (janela.MercadoPago ? resolve(janela.MercadoPago) : reject(new Error('SDK ausente')))
    script.onerror = () => {
      carregamento = null
      reject(new Error('Falha ao carregar o SDK do Mercado Pago'))
    }
    document.head.appendChild(script)
  })
  return carregamento
}

/** Identificador do aparelho gerado pelo SDK (ajuda o antifraude). */
export function deviceIdMercadoPago(): string | null {
  const valor = (window as unknown as { MP_DEVICE_SESSION_ID?: unknown }).MP_DEVICE_SESSION_ID
  return typeof valor === 'string' && valor.trim() ? valor : null
}

/** Normaliza a resposta de GET /api/payments/cartao. */
export function mapearConfigCartao(dados: unknown): ConfigCartaoPublico {
  const d = (dados ?? {}) as Record<string, unknown>
  const publicKey = typeof d.publicKey === 'string' && d.publicKey.trim() ? d.publicKey : null
  const valor = Number(d.valor)
  return {
    disponivel: d.disponivel === true && Boolean(publicKey) && valor > 0,
    publicKey,
    valor: Number.isFinite(valor) ? valor : 0,
    maxParcelas: Math.min(12, Math.max(1, Math.floor(Number(d.maxParcelas) || 1))),
    tentativasRestantes: Math.max(0, Math.floor(Number(d.tentativasRestantes) || 0)),
    email: typeof d.email === 'string' && d.email.trim() ? d.email : null
  }
}

/** Texto da forma de pagamento no detalhe do pedido. */
export function rotuloFormaPagamento(
  forma: string | null | undefined,
  parcelas?: number | null,
  bandeira?: string | null,
  final?: string | null
): string | null {
  if (forma === 'PIX') return 'Pix'
  if (forma !== 'CARTAO') return null
  const partes = ['Cartão de crédito']
  if (bandeira) partes.push(bandeira.toUpperCase())
  if (final) partes.push(`final ${final}`)
  const texto = partes.join(' ')
  return parcelas && parcelas > 1 ? `${texto} em ${parcelas}x` : `${texto} à vista`
}
