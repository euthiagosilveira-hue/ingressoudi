/**
 * Cadastro self-service do produtor (casa de eventos).
 * Regras puras (testaveis). A validacao real fica no backend
 * (public.concluir_cadastro_produtor / public.slug_organizacao_disponivel).
 */

/** Versao dos Termos de uso e da Politica de privacidade aceita no cadastro. */
export const TERMOS_VERSAO = 'v1-2026-10'

export const SENHA_MINIMA = 8

/** Endereco da casa a partir de um texto: "Bar do Zé!" -> "bar-do-ze". */
export function gerarSlug(texto: string | null | undefined): string {
  return String(texto ?? '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60)
    .replace(/-+$/g, '')
}

/** Formato aceito pelo banco: letras minusculas, numeros e hifens simples. */
export function slugValido(slug: string | null | undefined): boolean {
  return /^[a-z0-9]+(-[a-z0-9]+)*$/.test(String(slug ?? '').trim())
}

export interface DadosCadastro {
  nome: string
  email: string
  senha: string
  confirmacao: string
  casaNome: string
  casaSlug: string
  termos: boolean
}

export type ErrosCadastro = Partial<Record<keyof DadosCadastro, string>>

export function validarCadastro(d: DadosCadastro): ErrosCadastro {
  const erros: ErrosCadastro = {}
  if (!d.nome.trim()) erros.nome = 'Informe seu nome.'
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(d.email.trim())) erros.email = 'Informe um e-mail válido.'
  if (d.senha.length < SENHA_MINIMA) erros.senha = `A senha deve ter pelo menos ${SENHA_MINIMA} caracteres.`
  else if (d.senha !== d.confirmacao) erros.confirmacao = 'As senhas não conferem.'
  if (!d.casaNome.trim()) erros.casaNome = 'Informe o nome da casa ou produtora.'
  if (!slugValido(d.casaSlug)) erros.casaSlug = 'Use apenas letras minúsculas, números e hífens.'
  if (!d.termos) erros.termos = 'Aceite os termos de uso e a política de privacidade.'
  return erros
}

export function temErros(erros: ErrosCadastro): boolean {
  return Object.values(erros).some(Boolean)
}

/** Metadados gravados no usuario do Supabase Auth no signUp. */
export interface MetadadosCadastro {
  nome: string
  casa_nome: string
  casa_slug: string
  termos_versao: string
}

export function metadadosCadastro(d: DadosCadastro): MetadadosCadastro {
  return {
    nome: d.nome.trim(),
    casa_nome: d.casaNome.trim(),
    casa_slug: d.casaSlug.trim(),
    termos_versao: TERMOS_VERSAO
  }
}

/** Le os metadados do usuario (podem faltar se a conta nao veio do cadastro). */
export function lerMetadadosCadastro(meta: unknown): MetadadosCadastro | null {
  if (!meta || typeof meta !== 'object') return null
  const m = meta as Record<string, unknown>
  const texto = (v: unknown) => (typeof v === 'string' ? v.trim() : '')
  const dados = {
    nome: texto(m.nome),
    casa_nome: texto(m.casa_nome),
    casa_slug: texto(m.casa_slug),
    termos_versao: texto(m.termos_versao)
  }
  return dados.nome && dados.casa_nome && dados.termos_versao ? dados : null
}

/** Traduz erros do Supabase Auth / RPC de cadastro. */
export function mensagemErroCadastro(mensagem: string | null | undefined): string {
  const m = String(mensagem ?? '').toLowerCase()
  if (m.includes('already registered') || m.includes('already been registered') || m.includes('user already'))
    return 'Este e-mail já tem conta. Entre com ele para concluir o cadastro.'
  if (m.includes('endereco') || m.includes('endereço')) return 'Esse endereço já está em uso. Escolha outro.'
  if (m.includes('termos')) return 'Aceite os termos de uso para continuar.'
  if (m.includes('password') && (m.includes('least') || m.includes('weak') || m.includes('short')))
    return `Senha fraca: use pelo menos ${SENHA_MINIMA} caracteres, com letras e números.`
  if (m.includes('rate limit') || m.includes('too many') || m.includes('security purposes'))
    return 'Muitas tentativas seguidas. Aguarde alguns minutos e tente novamente.'
  if (m.includes('invalid login') || m.includes('invalid credentials')) return 'E-mail ou senha inválidos.'
  if (m.includes('email not confirmed')) return 'Confirme seu e-mail pelo link que enviamos antes de entrar.'
  if (m.includes('faca login') || m.includes('faça login')) return 'Entre com seu e-mail e senha para concluir.'
  if (m.includes('inativo')) return 'Este usuário está inativo.'
  return 'Não foi possível concluir o cadastro. Tente novamente.'
}
