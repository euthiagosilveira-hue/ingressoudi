import { assinarEstado } from '../../../utils/mercado-pago-cripto'
import { exigirAdminOrganizacaoAtiva } from '../../../utils/organizacao-admin'
import { montarUrlAutorizacao } from '../../../services/payments/mercado-pago/mercado-pago-oauth'

const VALIDADE_ESTADO_MS = 10 * 60 * 1000

/**
 * Inicia a conexao da conta Mercado Pago da ORGANIZACAO ATIVA (somente ADMINISTRADOR).
 * Redireciona para a tela de autorizacao do Mercado Pago com um `state` assinado
 * (organizacao + usuario + validade), conferido no callback.
 */
export default defineEventHandler(async (event) => {
  const config = useRuntimeConfig(event)
  const clientId = String(config.mercadoPagoClientId ?? '')
  const tokenKey = String(config.mercadoPagoTokenKey ?? '')

  if (!clientId || tokenKey.length < 32) {
    return sendRedirect(event, '/configuracoes/mercado-pago?status=indisponivel', 302)
  }

  let admin
  try {
    admin = await exigirAdminOrganizacaoAtiva(event)
  } catch {
    return sendRedirect(event, '/configuracoes/mercado-pago?status=sem-permissao', 302)
  }

  const siteUrl = String(config.public.siteUrl || getRequestURL(event).origin).replace(/\/+$/, '')
  const state = assinarEstado(
    { o: admin.organizacaoId, u: admin.usuarioId, e: Date.now() + VALIDADE_ESTADO_MS },
    tokenKey
  )

  const url = montarUrlAutorizacao({
    clientId,
    redirectUri: `${siteUrl}/api/mercadopago/oauth/callback`,
    state
  })
  return sendRedirect(event, url, 302)
})
