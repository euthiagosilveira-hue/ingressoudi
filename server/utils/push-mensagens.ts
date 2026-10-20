/** Conteudo das notificacoes push (sem dependencias, para testes). */
export interface AvisoPush {
  title: string
  body: string
  url: string
  tag: string
}

export function avisoNovaOrganizacao(nome: string, aprovada: boolean): AvisoPush {
  const casa = nome.trim() || 'Nova casa'
  return {
    title: 'Nova casa cadastrada',
    body: aprovada ? `${casa} acabou de se cadastrar.` : `${casa} se cadastrou e aguarda sua aprovação.`,
    url: '/plataforma/organizacoes',
    tag: 'nova-organizacao'
  }
}

/** Codigos do servico de push que indicam aparelho que nao existe mais. */
export function assinaturaExpirada(statusCode: number | undefined): boolean {
  return statusCode === 404 || statusCode === 410
}
