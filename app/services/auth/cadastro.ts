import { lerMetadadosCadastro, mensagemErroCadastro, type MetadadosCadastro } from '~/utils/cadastro'

export interface CadastroConcluido {
  organizacaoId: string
  slug: string | null
  jaExistente: boolean
}

/** Endereco livre para uma nova casa (RPC publica, sem login). */
export async function slugDisponivel(slug: string): Promise<boolean> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('slug_organizacao_disponivel', { p_slug: slug })
  if (error) throw new Error('Não foi possível verificar o endereço agora.')
  return data === true
}

/**
 * Cria o perfil do produtor e a casa (em analise) para o usuario logado.
 * Idempotente: quem ja tem casa recebe a existente.
 */
export async function concluirCadastroProdutor(dados: MetadadosCadastro): Promise<CadastroConcluido> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('concluir_cadastro_produtor', {
    p_nome: dados.nome,
    p_casa_nome: dados.casa_nome,
    p_casa_slug: dados.casa_slug || null,
    p_termos_versao: dados.termos_versao
  })
  if (error) throw new Error(mensagemErroCadastro(error.message))
  const r = (data ?? {}) as { organizacao_id?: string; slug?: string; ja_existente?: boolean }
  return {
    organizacaoId: String(r.organizacao_id ?? ''),
    slug: r.slug ?? null,
    jaExistente: Boolean(r.ja_existente)
  }
}

export { lerMetadadosCadastro }
