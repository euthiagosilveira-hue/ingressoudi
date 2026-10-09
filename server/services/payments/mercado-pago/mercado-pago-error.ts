import { MercadoPagoHttpError } from './mercado-pago-client.ts'

export interface MpErroSanitizado {
  httpStatus: number | null
  requestId: string | null
  code: string | null
  message: string | null
  cause: unknown
  errors: unknown
}

const CAMPOS_PERMITIDOS = [
  'code',
  'message',
  'description',
  'type',
  'details',
  'cause',
  'reason'
]
const LIMITE_TEXTO = 300
const LIMITE_ITENS = 10
const PROFUNDIDADE_MAXIMA = 4

function texto(valor: unknown): string | null {
  if (typeof valor !== 'string') return null
  const limpo = valor.trim()
  if (!limpo) return null
  const redigido = limpo
    .replace(/bearer\s+[A-Za-z0-9._-]+/gi, '[redigido]')
    .replace(/app_usr-?[A-Za-z0-9._-]+/gi, '[redigido]')
  return redigido.slice(0, LIMITE_TEXTO)
}

/**
 * Reduz um valor arbitrário a uma estrutura segura (apenas campos funcionais,
 * com limites de itens/tamanho/profundidade). Nunca inclui headers, tokens ou
 * o corpo bruto.
 */
function objetoSeguro(valor: unknown, profundidade: number): unknown {
  if (valor == null) return null
  if (typeof valor === 'string') return texto(valor)
  if (typeof valor === 'number' || typeof valor === 'boolean') return valor
  if (Array.isArray(valor)) {
    if (profundidade >= PROFUNDIDADE_MAXIMA) return null
    return valor.slice(0, LIMITE_ITENS).map((item) => objetoSeguro(item, profundidade + 1))
  }
  if (typeof valor === 'object') {
    if (profundidade >= PROFUNDIDADE_MAXIMA) return null
    const origem = valor as Record<string, unknown>
    const saida: Record<string, unknown> = {}
    for (const chave of CAMPOS_PERMITIDOS) {
      if (origem[chave] !== undefined) saida[chave] = objetoSeguro(origem[chave], profundidade + 1)
    }
    return Object.keys(saida).length > 0 ? saida : null
  }
  return texto(String(valor))
}

/**
 * Extrai apenas campos tecnicos seguros de um erro do Mercado Pago, incluindo
 * o campo `errors` retornado pela Orders API (ex.: HTTP 402).
 */
export function sanitizarErroMercadoPago(erro: unknown): MpErroSanitizado {
  const httpStatus = erro instanceof MercadoPagoHttpError ? erro.status : null

  const bruto =
    erro instanceof MercadoPagoHttpError || erro instanceof Error
      ? erro.message
      : typeof erro === 'string'
        ? erro
        : ''

  let json: Record<string, unknown> | null = null
  if (bruto) {
    try {
      const parsed = JSON.parse(bruto)
      if (parsed && typeof parsed === 'object') json = parsed as Record<string, unknown>
    } catch {
      json = null
    }
  }

  return {
    httpStatus,
    requestId: erro instanceof MercadoPagoHttpError ? texto(erro.requestId) : null,
    code: json ? texto(json.error) ?? texto(json.code) : null,
    message: json ? texto(json.message) : texto(bruto),
    cause: json ? objetoSeguro(json.cause ?? null, 0) : null,
    errors: json ? objetoSeguro(json.errors ?? null, 0) : null
  }
}

export interface MpErroLogContexto {
  endpoint: string
  operation: string
  pagamentoId: string | null
  pedidoCodigo: string | null
}

/**
 * Monta a linha de log sanitizada e JA SERIALIZADA (JSON string), para que
 * estruturas aninhadas como errors[].details aparecam expandidas no Runtime Log
 * (evita o console mostrar "[Array]"). Nunca inclui headers/tokens/body bruto.
 */
export function serializarLogErroMercadoPago(contexto: MpErroLogContexto, erro: unknown): string {
  return JSON.stringify({
    ...contexto,
    ...sanitizarErroMercadoPago(erro)
  })
}
