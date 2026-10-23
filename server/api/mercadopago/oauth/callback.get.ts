import { serverSupabaseUser } from '#supabase/server'

import { alertarErroPagamento } from '../../../utils/alerta-pagamento'
import { verificarEstado } from '../../../utils/mercado-pago-cripto'
import { exigirAdminOrganizacaoAtiva } from '../../../utils/organizacao-admin'
import { trocarCodigoPorToken } from '../../../services/payments/mercado-pago/mercado-pago-oauth'
import { salvarConexao } from '../../../services/payments/mercado-pago/mercado-pago-conexao'

const DESTINO = '/configuracoes/mercado-pago'

/**
 * Retorno do OAuth do Mercado Pago.
 *  1. confere o `state` assinado (organizacao, usuario, validade);
 *  2. confere que a sessao atual e do mesmo usuario e que ele continua
 *     ADMINISTRADOR da mesma organizacao;
 *  3. troca o `code` pelo token, cifra e grava a conexao (service role);
 *  4. volta para a tela de configuracao com o resultado.
 * Nunca devolve nem registra tokens.
 */
export default defineEventHandler(async (event) => {
  const config = useRuntimeConfig(event)
  const query = getQuery(event)
  const code = String(query.code ?? '').trim()
  const state = String(query.state ?? '').trim()
  const tokenKey = String(config.mercadoPagoTokenKey ?? '')

  if (tokenKey.length < 32) {
    await alertarErroPagamento(event, {
      tipo: 'CONFIGURACAO',
      mensagem: 'MERCADO_PAGO_TOKEN_KEY ausente ou curta na Vercel: casas não conseguem conectar o Mercado Pago.'
    })
  }
  if (query.error || !code || !state || tokenKey.length < 32) {
    return sendRedirect(event, `${DESTINO}?status=erro`, 302)
  }

  const estado = verificarEstado(state, tokenKey, Date.now())
  if (!estado) {
    return sendRedirect(event, `${DESTINO}?status=expirado`, 302)
  }

  const claims = await serverSupabaseUser(event).catch(() => null)
  if (!claims?.sub || String(claims.sub) !== estado.u) {
    return sendRedirect(event, `${DESTINO}?status=sem-permissao`, 302)
  }

  try {
    const admin = await exigirAdminOrganizacaoAtiva(event)
    if (admin.organizacaoId !== estado.o) {
      return sendRedirect(event, `${DESTINO}?status=organizacao-trocada`, 302)
    }
  } catch {
    return sendRedirect(event, `${DESTINO}?status=sem-permissao`, 302)
  }

  const siteUrl = String(config.public.siteUrl || getRequestURL(event).origin).replace(/\/+$/, '')
  try {
    const token = await trocarCodigoPorToken({
      clientId: String(config.mercadoPagoClientId ?? ''),
      clientSecret: String(config.mercadoPagoClientSecret ?? ''),
      code,
      redirectUri: `${siteUrl}/api/mercadopago/oauth/callback`,
      testToken: String(config.mercadoPagoOauthTestToken ?? 'false') === 'true'
    })
    await salvarConexao(event, estado.o, estado.u, token)
  } catch (erro) {
    console.error('[mercado-pago] callback OAuth falhou', {
      organizacaoId: estado.o,
      mensagem: erro instanceof Error ? erro.message : 'erro'
    })
    await alertarErroPagamento(event, {
      tipo: 'OAUTH_MP',
      organizacaoId: estado.o,
      mensagem: 'A casa tentou conectar o Mercado Pago e a troca do código pelo token falhou.',
      detalhe: { erro: erro instanceof Error ? erro.message.slice(0, 300) : 'erro' }
    })
    return sendRedirect(event, `${DESTINO}?status=erro`, 302)
  }

  return sendRedirect(event, `${DESTINO}?status=conectado`, 302)
})
