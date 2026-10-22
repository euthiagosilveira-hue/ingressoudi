/**
 * No modo suporte, a conta do Mercado Pago e a equipe sao do produtor:
 * o super admin volta para Configuracoes (o banco tambem bloqueia).
 * Roda depois de admin-auth, que ja carregou a sessao.
 */
export default defineNuxtRouteMiddleware(() => {
  if (import.meta.server) return
  const { operador } = useOperatorAuth()
  if (operador.value?.modoSuporte) {
    return navigateTo('/configuracoes?bloqueado=suporte')
  }
})
