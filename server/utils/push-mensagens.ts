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

/** Tipos de erro de pagamento (iguais ao check da tabela erros_pagamento). */
export type TipoErroPagamento =
  | 'PIX_CRIACAO'
  | 'CONTA_MP_DESCONECTADA'
  | 'TOKEN_MP'
  | 'OAUTH_MP'
  | 'WEBHOOK'
  | 'CONFIRMACAO'
  | 'VALOR_DIVERGENTE'
  | 'REEMBOLSO'
  | 'CONFIGURACAO'

export const TITULOS_ERRO_PAGAMENTO: Record<TipoErroPagamento, string> = {
  PIX_CRIACAO: 'Falha ao gerar Pix',
  CONTA_MP_DESCONECTADA: 'Casa sem Mercado Pago conectado',
  TOKEN_MP: 'Problema no token do Mercado Pago',
  OAUTH_MP: 'Falha ao conectar o Mercado Pago',
  WEBHOOK: 'Falha no aviso do Mercado Pago',
  CONFIRMACAO: 'Falha ao confirmar pagamento',
  VALOR_DIVERGENTE: 'Pagamento com valor diferente',
  REEMBOLSO: 'Reembolso falhou',
  CONFIGURACAO: 'Pagamentos sem configuração'
}

export function avisoErroPagamento(tipo: TipoErroPagamento, casa: string | null, mensagem: string): AvisoPush {
  const nome = (casa ?? '').trim()
  const texto = mensagem.trim() || 'Erro sem descrição.'
  const corpo = nome ? `${nome}: ${texto}` : texto
  return {
    title: TITULOS_ERRO_PAGAMENTO[tipo] ?? 'Erro em pagamento',
    body: corpo.length > 180 ? `${corpo.slice(0, 177)}...` : corpo,
    url: '/plataforma/erros-pagamento',
    tag: `erro-pagamento-${tipo.toLowerCase()}`
  }
}
