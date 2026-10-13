import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto'

/**
 * Criptografia dos tokens OAuth do Mercado Pago (AES-256-GCM) e assinatura do
 * parametro `state` do OAuth (HMAC-SHA256).
 * Chave: MERCADO_PAGO_TOKEN_KEY (texto aleatorio com 32+ caracteres).
 * Modulo puro (sem auto-imports do Nuxt) para poder ser testado com node --test.
 */

const PREFIXO = 'v1'

function chave(segredo: string, contexto: string): Buffer {
  if (!segredo || segredo.length < 32) {
    throw new Error('MERCADO_PAGO_TOKEN_KEY ausente ou com menos de 32 caracteres.')
  }
  return createHash('sha256').update(`${contexto}:${segredo}`).digest()
}

function b64url(buf: Buffer): string {
  return buf.toString('base64url')
}

export function cifrarToken(texto: string, segredo: string): string {
  const iv = randomBytes(12)
  const cipher = createCipheriv('aes-256-gcm', chave(segredo, 'token'), iv)
  const conteudo = Buffer.concat([cipher.update(texto, 'utf8'), cipher.final()])
  const tag = cipher.getAuthTag()
  return [PREFIXO, b64url(iv), b64url(tag), b64url(conteudo)].join('.')
}

export function decifrarToken(valor: string, segredo: string): string {
  const partes = String(valor ?? '').split('.')
  if (partes.length !== 4 || partes[0] !== PREFIXO) {
    throw new Error('Token cifrado em formato invalido.')
  }
  const [, iv, tag, conteudo] = partes
  const decipher = createDecipheriv('aes-256-gcm', chave(segredo, 'token'), Buffer.from(iv, 'base64url'))
  decipher.setAuthTag(Buffer.from(tag, 'base64url'))
  return Buffer.concat([decipher.update(Buffer.from(conteudo, 'base64url')), decipher.final()]).toString('utf8')
}

export interface EstadoOAuth {
  /** organizacao_id */
  o: string
  /** usuario que iniciou a conexao */
  u: string
  /** expiracao (epoch ms) */
  e: number
  /** nonce */
  n: string
}

export function assinarEstado(dados: Omit<EstadoOAuth, 'n'>, segredo: string): string {
  const payload: EstadoOAuth = { ...dados, n: randomBytes(12).toString('base64url') }
  const corpo = b64url(Buffer.from(JSON.stringify(payload), 'utf8'))
  const assinatura = b64url(createHmac('sha256', chave(segredo, 'estado')).update(corpo).digest())
  return `${corpo}.${assinatura}`
}

/** Valida assinatura e validade do `state`. Retorna null se invalido/expirado. */
export function verificarEstado(estado: string, segredo: string, agoraMs: number): EstadoOAuth | null {
  const [corpo, assinatura] = String(estado ?? '').split('.')
  if (!corpo || !assinatura) return null

  const esperado = createHmac('sha256', chave(segredo, 'estado')).update(corpo).digest()
  const recebido = Buffer.from(assinatura, 'base64url')
  if (recebido.length !== esperado.length || !timingSafeEqual(recebido, esperado)) return null

  try {
    const dados = JSON.parse(Buffer.from(corpo, 'base64url').toString('utf8')) as EstadoOAuth
    if (!dados?.o || !dados?.u || typeof dados.e !== 'number') return null
    if (agoraMs > dados.e) return null
    return dados
  } catch {
    return null
  }
}
