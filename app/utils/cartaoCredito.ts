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
// Script de antifraude do Mercado Pago: gera o identificador do aparelho
// (window.MP_DEVICE_SESSION_ID). Sem ele o antifraude recusa muito mais
// (cc_rejected_high_risk).
const SECURITY_URL = 'https://www.mercadopago.com/v2/security.js'

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

let segurancaCarregada = false

/** Carrega o script de antifraude uma vez (so no navegador). */
export function carregarSegurancaMercadoPago(): void {
  if (segurancaCarregada || deviceIdMercadoPago()) return
  segurancaCarregada = true
  const script = document.createElement('script')
  script.src = SECURITY_URL
  script.async = true
  script.setAttribute('view', 'checkout')
  script.setAttribute('output', 'deviceId')
  script.onerror = () => {
    segurancaCarregada = false
  }
  document.head.appendChild(script)
}

/** Espera o identificador do aparelho por ate `ms` (nao bloqueia o pagamento). */
export async function aguardarDeviceIdMercadoPago(ms = 3000): Promise<string | null> {
  const inicio = Date.now()
  while (Date.now() - inicio < ms) {
    const id = deviceIdMercadoPago()
    if (id) return id
    await new Promise((r) => setTimeout(r, 150))
  }
  return deviceIdMercadoPago()
}

/** Identificador do aparelho gerado pelo script de antifraude. */
export function deviceIdMercadoPago(): string | null {
  const janela = window as unknown as { MP_DEVICE_SESSION_ID?: unknown; deviceId?: unknown }
  const valor = janela.MP_DEVICE_SESSION_ID ?? janela.deviceId
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
