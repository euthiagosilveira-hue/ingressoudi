export const CONVITE_EXPIRADO_MSG =
  'Este convite expirou ou já foi utilizado. Solicite um novo convite ao administrador.'

export const SENHA_MINIMA = 8

export interface ErroLinkConvite {
  error: string
  errorCode: string
}

/**
 * Extrai erro de link de convite a partir de query e/ou hash
 * (ex.: #error=access_denied&error_code=otp_expired).
 */
export function extrairErroConvite(
  search: string | null | undefined,
  hash: string | null | undefined
): ErroLinkConvite | null {
  const query = new URLSearchParams((search ?? '').replace(/^\?/, ''))
  const fragmento = new URLSearchParams((hash ?? '').replace(/^#/, ''))
  const error = fragmento.get('error') || query.get('error') || ''
  const errorCode = fragmento.get('error_code') || query.get('error_code') || ''
  if (!error && !errorCode) return null
  return { error, errorCode }
}

/** Mensagem amigavel unica para qualquer falha de link de convite. */
export function mensagemErroConviteLink(erro: ErroLinkConvite | null): string {
  void erro
  return CONVITE_EXPIRADO_MSG
}

/** Destino pos-setup conforme o perfil (ADMIN -> '/painel', PORTARIA -> '/portaria'). */
export function destinoAposConvite(perfil: string | null | undefined): string {
  return perfil === 'PORTARIA' ? '/portaria' : '/painel'
}

export interface ErrosSenhaConvite {
  senha?: string
  confirmacao?: string
}

export function validarSenhaConvite(
  senha: string,
  confirmacao: string
): ErrosSenhaConvite {
  const erros: ErrosSenhaConvite = {}
  if (!senha) erros.senha = 'Informe uma senha.'
  else if (senha.length < SENHA_MINIMA) {
    erros.senha = `A senha deve ter pelo menos ${SENHA_MINIMA} caracteres.`
  }
  if (!confirmacao) erros.confirmacao = 'Confirme a senha.'
  else if (confirmacao !== senha) erros.confirmacao = 'As senhas não conferem.'
  return erros
}

export type TipoTokenConvite = 'invite' | 'recovery'

export interface TokenConvite {
  tokenHash: string
  tipo: TipoTokenConvite
}

/**
 * Le o token do link de convite gerado pelo painel
 * (/auth/convite?token_hash=...&tipo=invite|recovery).
 */
export function lerTokenConvite(search: string | null | undefined): TokenConvite | null {
  const query = new URLSearchParams((search ?? '').replace(/^\?/, ''))
  const tokenHash = (query.get('token_hash') ?? '').trim()
  const tipo = query.get('tipo') === 'recovery' ? 'recovery' : 'invite'
  if (!tokenHash) return null
  return { tokenHash, tipo }
}

/** Texto pronto para enviar o convite (WhatsApp ou qualquer mensageiro). */
export function mensagemConvite(nome: string | null | undefined, link: string): string {
  const primeiroNome = (nome ?? '').trim().split(/\s+/)[0]
  const saudacao = primeiroNome ? `Olá, ${primeiroNome}!` : 'Olá!'
  return `${saudacao} Você foi convidado(a) para acessar o painel do Ingressoudi. Abra o link para criar sua senha: ${link}`
}

/** Link do WhatsApp com a mensagem do convite (a pessoa escolhe o contato). */
export function linkWhatsappConvite(nome: string | null | undefined, link: string): string {
  return `https://wa.me/?text=${encodeURIComponent(mensagemConvite(nome, link))}`
}
