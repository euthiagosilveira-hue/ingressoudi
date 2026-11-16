/**
 * CPF, CNPJ e telefone do organizador. Regras puras (testaveis); o banco
 * confere de novo (private.documento_valido).
 */

export type TipoDocumento = 'CPF' | 'CNPJ'

export function soDigitos(texto: string | null | undefined): string {
  return String(texto ?? '').replace(/\D/g, '')
}

export function cpfValido(cpf: string | null | undefined): boolean {
  const v = soDigitos(cpf)
  if (v.length !== 11 || /^(\d)\1{10}$/.test(v)) return false
  const dv = (base: string, pesoInicial: number) => {
    let soma = 0
    for (let i = 0; i < base.length; i += 1) soma += Number(base[i]) * (pesoInicial - i)
    const r = (soma * 10) % 11
    return r === 10 ? 0 : r
  }
  return dv(v.slice(0, 9), 10) === Number(v[9]) && dv(v.slice(0, 10), 11) === Number(v[10])
}

export function cnpjValido(cnpj: string | null | undefined): boolean {
  const v = soDigitos(cnpj)
  if (v.length !== 14 || /^(\d)\1{13}$/.test(v)) return false
  const dv = (base: string, pesos: number[]) => {
    let soma = 0
    for (let i = 0; i < base.length; i += 1) soma += Number(base[i]) * pesos[i]!
    const r = soma % 11
    return r < 2 ? 0 : 11 - r
  }
  const p1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
  const p2 = [6, ...p1]
  return dv(v.slice(0, 12), p1) === Number(v[12]) && dv(v.slice(0, 13), p2) === Number(v[13])
}

export function documentoValido(tipo: TipoDocumento | string | null | undefined, documento: string): boolean {
  if (tipo === 'CPF') return cpfValido(documento)
  if (tipo === 'CNPJ') return cnpjValido(documento)
  return false
}

/** Mascara enquanto digita: 000.000.000-00 ou 00.000.000/0000-00. */
export function formatarDocumento(tipo: TipoDocumento | string | null | undefined, texto: string): string {
  if (tipo === 'CNPJ') {
    const v = soDigitos(texto).slice(0, 14)
    return v
      .replace(/^(\d{2})(\d)/, '$1.$2')
      .replace(/^(\d{2})\.(\d{3})(\d)/, '$1.$2.$3')
      .replace(/\.(\d{3})(\d)/, '.$1/$2')
      .replace(/(\d{4})(\d)/, '$1-$2')
  }
  const v = soDigitos(texto).slice(0, 11)
  return v
    .replace(/^(\d{3})(\d)/, '$1.$2')
    .replace(/^(\d{3})\.(\d{3})(\d)/, '$1.$2.$3')
    .replace(/\.(\d{3})(\d)/, '.$1-$2')
}

/** Telefone com DDD: (00) 0000-0000 ou (00) 00000-0000. */
export function formatarTelefone(texto: string): string {
  const v = soDigitos(texto).slice(0, 11)
  if (v.length <= 2) return v.length ? `(${v}` : ''
  if (v.length <= 6) return `(${v.slice(0, 2)}) ${v.slice(2)}`
  if (v.length <= 10) return `(${v.slice(0, 2)}) ${v.slice(2, 6)}-${v.slice(6)}`
  return `(${v.slice(0, 2)}) ${v.slice(2, 7)}-${v.slice(7)}`
}

export function telefoneValido(texto: string | null | undefined): boolean {
  return /^\d{10,11}$/.test(soDigitos(texto))
}

export interface DadosOrganizador {
  tipoDocumento: TipoDocumento
  documento: string
  responsavelNome: string
  telefone: string
}

export type ErrosOrganizador = Partial<Record<keyof DadosOrganizador, string>>

export function validarDadosOrganizador(d: DadosOrganizador): ErrosOrganizador {
  const erros: ErrosOrganizador = {}
  if (!documentoValido(d.tipoDocumento, d.documento)) erros.documento = `${d.tipoDocumento} inválido: confira os números.`
  if (!d.responsavelNome.trim())
    erros.responsavelNome = d.tipoDocumento === 'CNPJ' ? 'Informe a razão social.' : 'Informe o nome completo.'
  if (!telefoneValido(d.telefone)) erros.telefone = 'Informe o telefone com DDD.'
  return erros
}

/** Rotulo do campo de nome conforme o tipo de documento. */
export function rotuloResponsavel(tipo: TipoDocumento): string {
  return tipo === 'CNPJ' ? 'Razão social (como no CNPJ)' : 'Nome completo (como no CPF)'
}
