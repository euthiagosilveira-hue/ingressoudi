import { decidirAcessoOperador, resolverUid, uidDoUsuario } from '~/utils/auth'

/**
 * Protege a area da portaria.
 * - sem sessao real -> /login
 * - sessao sem perfil permitido/inativo -> signOut + /login
 * Nao derruba a sessao por atraso reativo (usa uid explicito) nem por erro
 * transitorio de consulta. A seguranca real continua no backend (RPCs).
 */
export default defineNuxtRouteMiddleware(async (to) => {
  const user = useSupabaseUser()
  const session = useSupabaseSession()
  const supabase = useSupabaseClient()

  // No SSR: useSupabaseUser() = JWT claims (`sub`) e a sessao nao tem `user`.
  // No cliente: sessao.user.id existe. Por isso consideramos os dois campos.
  let uid = resolverUid(uidDoUsuario(user.value), session.value?.user?.id)

  if (!uid && import.meta.client) {
    try {
      const { data } = await supabase.auth.getSession()
      uid = data.session?.user?.id ?? null
    } catch {
      uid = null
    }
  }

  if (!uid) {
    return navigateTo(`/login?redirect=${encodeURIComponent(to.fullPath)}`)
  }

  // No servidor apenas garantimos a existencia de sessao.
  if (import.meta.server) return

  const { carregarOperador } = useOperatorAuth()

  let perfil = null
  try {
    perfil = await carregarOperador(uid)
  } catch {
    // Erro transitorio: nao derruba a sessao; a pagina pode tentar de novo.
    return
  }

  const decisao = decidirAcessoOperador({
    temSessao: true,
    perfil: perfil?.perfil ?? null,
    ativo: perfil?.ativo ?? null
  })

  if (decisao !== 'PERMITIR') {
    await supabase.auth.signOut()
    return navigateTo('/login?erro=SEM_PERMISSAO')
  }
})
