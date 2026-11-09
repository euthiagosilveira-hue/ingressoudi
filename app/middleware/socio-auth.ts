import { destinoInicialPerfil } from '~/utils/navegacao'
import { resolverUid, uidDoUsuario } from '~/utils/auth'

/**
 * Protege a area do Socio do Evento (/socio).
 * Exige sessao + perfil SOCIO ativo na organizacao ativa. Outros perfis vao
 * para a tela inicial deles. A seguranca real esta nas RPCs do socio.
 */
export default defineNuxtRouteMiddleware(async (to) => {
  const user = useSupabaseUser()
  const session = useSupabaseSession()
  const supabase = useSupabaseClient()

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

  if (!perfil || !perfil.ativo) {
    await supabase.auth.signOut()
    return navigateTo('/login?erro=SEM_PERMISSAO')
  }

  if (perfil.perfil !== 'SOCIO') {
    return navigateTo(destinoInicialPerfil(perfil.perfil))
  }
})
