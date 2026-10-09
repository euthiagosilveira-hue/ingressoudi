import QRCode from 'qrcode'
import { serverSupabaseServiceRole } from '#supabase/server'

import { limitar } from '../../../../utils/rate-limit'

/**
 * Gera a imagem (SVG) do QR Code de um ingresso compartilhado.
 * O qr_token e lido apenas no servidor; o browser nao recebe o token textual.
 */
export default defineEventHandler(async (event) => {
  setHeader(event, 'Cache-Control', 'private, no-store')

  if (!limitar(event)) {
    setResponseStatus(event, 429)
    return { error: 'MUITAS_REQUISICOES' }
  }

  const token = String(getRouterParam(event, 'token') ?? '').trim()
  if (!token || token.length > 200) {
    setResponseStatus(event, 404)
    return { error: 'NAO_ENCONTRADO' }
  }

  const client = serverSupabaseServiceRole(event)
  const { data, error } = await client.rpc('obter_qr_compartilhamento', { p_token: token })

  if (error || !data) {
    setResponseStatus(event, 404)
    return { error: 'NAO_ENCONTRADO' }
  }

  const svg = await QRCode.toString(String(data), {
    type: 'svg',
    errorCorrectionLevel: 'M',
    margin: 4
  })

  setHeader(event, 'Content-Type', 'image/svg+xml; charset=utf-8')
  return svg
})
