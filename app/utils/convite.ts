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

/** Destino pos-setup conforme o perfil (ADMIN -> '/', PORTARIA -> '/portaria'). */
export function destinoAposConvite(perfil: string | null | undefined): string {
  return perfil === 'PORTARIA' ? '/portaria' : '/'
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
