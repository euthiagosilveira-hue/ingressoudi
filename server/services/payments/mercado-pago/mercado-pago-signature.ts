import { createHmac, timingSafeEqual } from 'node:crypto'

export interface AssinaturaMp {
  xSignature: string | null
  xRequestId: string | null
  dataId: string | null
}

/**
 * Monta o manifest oficial:
 *   id:<data.id lowercase>;request-id:<x-request-id>;ts:<ts>;
 * Campos ausentes sao omitidos (regra oficial).
 */
export function montarManifest(assinatura: AssinaturaMp): string | null {
  const xSignature = assinatura.xSignature ?? ''
  const xRequestId = (assinatura.xRequestId ?? '').trim()
  const dataId = (assinatura.dataId ?? '').trim().toLowerCase()

  let ts: string | null = null
  for (const parte of xSignature.split(',')) {
    const igual = parte.indexOf('=')
    if (igual === -1) continue
    const chave = parte.slice(0, igual).trim()
    const valor = parte.slice(igual + 1).trim()
    if (chave === 'ts') ts = valor
  }

  if (!ts) return null

  const partes: string[] = []
  if (dataId) partes.push(`id:${dataId}`)
  if (xRequestId) partes.push(`request-id:${xRequestId}`)
  partes.push(`ts:${ts}`)

  return `${partes.join(';')};`
}

/** Extrai o valor de v1 (assinatura) do header x-signature. */
export function extrairV1(xSignature: string | null): string | null {
  if (!xSignature) return null
  for (const parte of xSignature.split(',')) {
    const igual = parte.indexOf('=')
    if (igual === -1) continue
    const chave = parte.slice(0, igual).trim()
    const valor = parte.slice(igual + 1).trim()
    if (chave === 'v1') return valor
  }
  return null
}

/** Valida HMAC-SHA256 com comparacao constant-time. */
export function validarAssinaturaMp(assinatura: AssinaturaMp, secret: string): boolean {
  if (!secret) return false

  const manifest = montarManifest(assinatura)
  const recebido = extrairV1(assinatura.xSignature)
  if (!manifest || !recebido) return false

  const calculado = createHmac('sha256', secret).update(manifest).digest('hex')
  const a = Buffer.from(calculado, 'utf8')
  const b = Buffer.from(recebido, 'utf8')
  if (a.length !== b.length) return false
  return timingSafeEqual(a, b)
}
