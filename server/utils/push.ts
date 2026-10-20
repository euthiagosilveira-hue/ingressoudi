import webpush from 'web-push'

import { assinaturaExpirada, type AvisoPush } from './push-mensagens'

export interface AssinaturaPush {
  endpoint: string
  p256dh: string
  auth: string
}

/**
 * Envia o aviso para cada aparelho. Devolve os endpoints que o servico de push
 * informou como inexistentes (para remover do banco). Sem chaves VAPID
 * configuradas, nao envia nada.
 */
export async function enviarPush(assinaturas: AssinaturaPush[], aviso: AvisoPush): Promise<{ enviados: number; expirados: string[] }> {
  const config = useRuntimeConfig()
  const publica = String(config.public.vapidPublicKey ?? '')
  const privada = String(config.vapidPrivateKey ?? '')
  const assunto = String(config.vapidSubject ?? '') || 'mailto:contato@ingressoudi.com.br'
  if (!publica || !privada || assinaturas.length === 0) return { enviados: 0, expirados: [] }

  webpush.setVapidDetails(assunto, publica, privada)
  const payload = JSON.stringify(aviso)
  const expirados: string[] = []
  let enviados = 0

  await Promise.all(
    assinaturas.map(async (a) => {
      try {
        await webpush.sendNotification({ endpoint: a.endpoint, keys: { p256dh: a.p256dh, auth: a.auth } }, payload, {
          TTL: 60 * 60 * 24
        })
        enviados += 1
      } catch (e) {
        const statusCode = (e as { statusCode?: number })?.statusCode
        if (assinaturaExpirada(statusCode)) expirados.push(a.endpoint)
      }
    })
  )
  return { enviados, expirados }
}
