import type { OperadorProfile, OrganizacaoDoOperador, OrganizacaoResumo, PerfilOperador } from '~/types/operador'

interface SessaoRpc {
  id: string
  nome: string
  email: string
  perfil: string | null
  ativo: boolean
  super_admin: boolean
  modo_suporte?: boolean
  organizacao: (OrganizacaoResumo & { lista_vip?: boolean }) | null
  organizacoes: Array<OrganizacaoResumo & { perfil: string }>
}

function mapearSessao(data: unknown): OperadorProfile | null {
  if (!data || typeof data !== 'object') return null
  const s = data as SessaoRpc
  return {
    id: s.id,
    nome: s.nome,
    email: s.email,
    // perfil na organizacao ativa; sem organizacao, nao ha perfil valido
    perfil: (s.perfil ?? '') as PerfilOperador,
    ativo: Boolean(s.ativo),
    superAdmin: Boolean(s.super_admin),
    modoSuporte: Boolean(s.modo_suporte),
    organizacao: s.organizacao
      ? {
          id: s.organizacao.id,
          nome: s.organizacao.nome,
          slug: s.organizacao.slug,
          aprovada: s.organizacao.aprovada,
          listaVip: Boolean(s.organizacao.lista_vip)
        }
      : null,
    organizacoes: (s.organizacoes ?? []).map((o) => ({
      id: o.id,
      nome: o.nome,
      slug: o.slug,
      perfil: o.perfil as PerfilOperador
    })) as OrganizacaoDoOperador[]
  }
}

/**
 * Sessao do operador autenticado: perfil NA ORGANIZACAO ATIVA e lista de
 * organizacoes (RPC public.obter_sessao_operador). O userId e mantido na
 * assinatura por compatibilidade; a identidade vem do JWT no backend.
 */
export async function obterOperadorAtual(_userId: string): Promise<OperadorProfile | null> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_sessao_operador')
  if (error) {
    throw new Error('Não foi possível carregar o perfil do operador.')
  }
  return mapearSessao(data)
}

/** Troca a organizacao ativa e devolve a sessao atualizada. */
export async function definirOrganizacaoAtiva(organizacaoId: string): Promise<OperadorProfile | null> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('definir_organizacao_ativa', {
    p_organizacao_id: organizacaoId
  })
  if (error) {
    throw new Error('Não foi possível trocar de organização.')
  }
  return mapearSessao(data)
}

/** Sai do modo suporte: volta para a primeira casa da qual o usuario e membro. */
export async function sairModoSuporte(): Promise<OperadorProfile | null> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('sair_modo_suporte')
  if (error) {
    throw new Error('Não foi possível sair do modo suporte.')
  }
  return mapearSessao(data)
}
