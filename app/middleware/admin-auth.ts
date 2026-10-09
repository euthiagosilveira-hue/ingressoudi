import { resolverUid, uidDoUsuario } from '~/utils/auth'

/**
 * Protege a area administrativa (/eventos etc.).
 * Exige sessao + perfil ADMINISTRADOR ativo.
 * Nao quebra /portaria (que usa operator-auth).
 */
export default defineNuxtRouteMiddleware(async (to) => {
  const user = useSupabaseUser()
  const session = useSupabaseSession()
  const supabase = useSupabaseClient()

  // Sessao pode ainda estar restaurando na hidratacao (refresh): usa a fonte
  // autoritativa do client quando os refs reativos ainda estiverem vazios.
  // No SSR user = claims (`sub`) e sessao sem `user`; no client ha session.user.
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

  if (import.meta.server) return

  const { carregarOperador } = useOperatorAuth()

  let perfil = null
  try {
    perfil = await carregarOperador(uid)
  } catch {
    return
  }

  if (!perfil || !perfil.ativo || perfil.perfil !== 'ADMINISTRADOR') {
    await supabase.auth.signOut()
    return navigateTo('/login?erro=SEM_PERMISSAO')
  }
})
