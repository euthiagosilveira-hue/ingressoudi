/**
 * Contrato do Organizador. A versao precisa ser igual a
 * private.contrato_organizador_versao() no banco. Ao mudar o texto da pagina
 * /contrato-organizador: troque a versao aqui e no banco (nova migration);
 * todas as casas aceitam de novo no proximo acesso ao painel.
 */
export const CONTRATO_ORGANIZADOR_VERSAO = 'v1-2026-11'
export const CONTRATO_ORGANIZADOR_DATA = '16/11/2026'
export const CONTRATO_ORGANIZADOR_URL = '/contrato-organizador'

/** Rota da tela de dados do organizador e aceite do contrato. */
export const TELA_DADOS_ORGANIZADOR = '/configuracoes/organizador'

/** Paginas do painel liberadas enquanto o contrato esta pendente. */
export function rotaLiberadaComContratoPendente(caminho: string): boolean {
  const p = caminho.split('?')[0]!.replace(/\/+$/, '') || '/'
  return p === TELA_DADOS_ORGANIZADOR || p === '/ajuda' || p.startsWith('/ajuda/')
}

/** Mensagem amigavel para os erros da rota /api/contrato/aceitar e dos RPCs. */
export function mensagemErroContrato(codigoOuMensagem: string | null | undefined): string {
  const m = String(codigoOuMensagem ?? '').toLowerCase()
  if (m.includes('desatualizada') || m.includes('versao_desatualizada'))
    return 'O contrato foi atualizado. Recarregue a página e leia a versão nova.'
  if (m.includes('complete os dados') || m.includes('dados_incompletos'))
    return 'Preencha e salve os dados do organizador antes de aceitar.'
  if (m.includes('cpf invalido')) return 'CPF inválido: confira os números.'
  if (m.includes('cnpj invalido')) return 'CNPJ inválido: confira os números.'
  if (m.includes('telefone')) return 'Telefone inválido: informe DDD e número.'
  if (m.includes('razao social') || m.includes('nome completo')) return 'Informe o nome completo ou a razão social.'
  if (m.includes('administrador') || m.includes('sem_permissao') || m.includes('permiss'))
    return 'Apenas um administrador da casa pode aceitar o contrato.'
  if (m.includes('muitas_tentativas')) return 'Muitas tentativas seguidas. Aguarde um minuto.'
  return 'Não foi possível salvar agora. Tente novamente.'
}
