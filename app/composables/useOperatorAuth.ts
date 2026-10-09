import { computed, ref } from 'vue'

import { obterOperadorAtual } from '~/services/auth/operador'
import type { AuthErrorCode, OperadorProfile } from '~/types/operador'
import { codigoErroPerfil, mensagemLoginErro, perfilPermitido, resolverUid, uidDoUsuario } from '~/utils/auth'

export class AuthError extends Error {
  code: AuthErrorCode

  constructor(code: AuthErrorCode) {
    super(mensagemLoginErro(code))
    this.name = 'AuthError'
    this.code = code
  }
}

/**
 * Autenticacao do operador da portaria (Supabase Auth) + perfil em
 * public.usuarios. A autorizacao real permanece no backend/RPC.
 */
export function useOperatorAuth() {
  const supabase = useSupabaseClient()
  const user = useSupabaseUser()
  const operador = useState<OperadorProfile | null>('operator-profile', () => null)
  const carregando = ref(false)
  const carregado = useState<boolean>('operator-profile-loaded', () => false)

  const isAuthorized = computed(
    () => Boolean(operador.value && operador.value.ativo && perfilPermitido(operador.value.perfil))
  )

  async function carregarOperador(userId?: string): Promise<OperadorProfile | null> {
    // Nao depende do timing de useSupabaseUser: aceita uid explicito.
    const uid = resolverUid(userId, uidDoUsuario(user.value))
    if (!uid) {
      operador.value = null
      carregado.value = true
      return null
    }
    try {
      const perfil = await obterOperadorAtual(uid)
      operador.value = perfil
      return perfil
    } finally {
      carregado.value = true
    }
  }

  async function login(email: string, senha: string): Promise<OperadorProfile> {
    carregando.value = true
    try {
      const { data, error } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password: senha
      })
      if (error) throw new AuthError('CREDENCIAIS_INVALIDAS')

      // uid preferencialmente do retorno do signIn (nao do ref reativo).
      const uid = resolverUid(data?.user?.id, data?.session?.user?.id, uidDoUsuario(user.value))
      if (!uid) throw new AuthError('ERRO_TEMPORARIO')

      const perfil = await carregarOperador(uid)
      const codigo = codigoErroPerfil(perfil)
      if (codigo) {
        await supabase.auth.signOut()
        throw new AuthError(codigo)
      }
      return perfil as OperadorProfile
    } catch (e) {
      if (e instanceof AuthError) throw e
      throw new AuthError('ERRO_TEMPORARIO')
    } finally {
      carregando.value = false
    }
  }

  async function logout(): Promise<void> {
    await supabase.auth.signOut()
    operador.value = null
    carregado.value = false
  }

  return {
    user,
    operador,
    carregando,
    carregado,
    isAuthorized,
    login,
    logout,
    carregarOperador,
    refreshProfile: carregarOperador
  }
}
