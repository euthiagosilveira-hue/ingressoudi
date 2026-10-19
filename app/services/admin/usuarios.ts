import type {
  AdminUsuarioRow,
  ConviteUsuarioInput,
  EdicaoUsuarioInput,
  ResultadoConvite
} from '~/types/usuario'
import {
  mensagemErroConvite,
  mensagemErroUsuario,
  montarPayloadAtualizacao
} from '~/utils/usuarios'

/** Lista usuarios reais (RPC segura, ADMINISTRADOR). */
export async function listarUsuariosAdmin(busca?: string): Promise<AdminUsuarioRow[]> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('listar_usuarios_admin', {
    p_busca: busca?.trim() ? busca.trim() : null
  })
  if (error) {
    throw new Error(mensagemErroUsuario(error, 'Não foi possível carregar os usuários.'))
  }
  return (data ?? []) as AdminUsuarioRow[]
}

/** Atualiza nome/perfil/ativo (RPC segura, ADMINISTRADOR). Sem troca de e-mail. */
export async function atualizarUsuarioAdmin(input: EdicaoUsuarioInput): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('atualizar_usuario_admin', montarPayloadAtualizacao(input))
  if (error) {
    throw new Error(mensagemErroUsuario(error, 'Não foi possível atualizar o usuário.'))
  }
}

interface RespostaConvite {
  ok?: boolean
  error?: string
  message?: string
  link?: string
  vinculado?: boolean
  pendente?: boolean
}

interface ErroFetch {
  status?: number
  statusCode?: number
  data?: RespostaConvite
}

async function postarConvite(url: string, body: Record<string, unknown>): Promise<RespostaConvite> {
  try {
    const resposta = await $fetch<RespostaConvite>(url, { method: 'POST', body })
    if (!resposta?.ok) {
      throw new Error(mensagemErroConvite(resposta?.error))
    }
    return resposta
  } catch (e) {
    const erro = e as ErroFetch & Error
    if (erro instanceof Error && !erro.data && !erro.status && !erro.statusCode) {
      throw erro
    }
    throw new Error(erro.data?.message ?? mensagemErroConvite(erro.data?.error))
  }
}

/**
 * Convida um usuario via endpoint server-side (service role + Supabase Auth).
 * Devolve o link do convite para o administrador enviar. O frontend nunca ve a
 * service key nem auth.users.
 */
export async function convidarUsuarioAdmin(input: ConviteUsuarioInput): Promise<ResultadoConvite> {
  const resposta = await postarConvite('/api/admin/users/invite', {
    nome: input.nome.trim(),
    email: input.email.trim(),
    perfil: input.perfil
  })
  return {
    link: resposta.link ?? null,
    vinculado: resposta.vinculado === true,
    pendente: resposta.pendente === true
  }
}

/** Gera um novo link de convite para um usuario pendente da organizacao. */
export async function gerarNovoLinkConviteAdmin(usuarioId: string): Promise<string> {
  const resposta = await postarConvite('/api/admin/users/link-convite', { usuarioId })
  if (!resposta.link) throw new Error(mensagemErroConvite('FALHA_CONVITE'))
  return resposta.link
}
