import type { OperadorProfile, PerfilOperador } from '~/types/operador'

interface UsuarioRow {
  id: string
  nome: string
  email: string
  perfil: string
  ativo: boolean
}

/**
 * Le a PROPRIA linha em public.usuarios.
 * RLS permite a `authenticated` ler apenas a propria linha (policy
 * usuarios_select_proprio) — unica leitura direta prevista.
 */
export async function obterOperadorAtual(userId: string): Promise<OperadorProfile | null> {
  const client = useSupabaseClient()
  const { data, error } = await client
    .from('usuarios')
    .select('id,nome,email,perfil,ativo')
    .eq('id', userId)
    .maybeSingle()

  if (error) {
    throw new Error('Não foi possível carregar o perfil do operador.')
  }
  if (!data) return null

  const row = data as UsuarioRow
  return {
    id: row.id,
    nome: row.nome,
    email: row.email,
    perfil: row.perfil as PerfilOperador,
    ativo: row.ativo
  }
}
