import { formatDataHoraCompleta, formatDataNumerica } from './format.ts'

/** Dono de uma casa, como o super admin ve em Plataforma > Donos das casas. */
export interface DonoPlataforma {
  usuarioId: string
  nome: string
  email: string
  ativo: boolean
  cadastradoEm: string | null
  ultimoAcessoEm: string | null
  emailConfirmado: boolean
  termosVersao: string | null
  termosAceitosEm: string | null
  outrasCasas: number
}

export interface CasaComDono {
  organizacaoId: string
  organizacaoNome: string
  organizacaoSlug: string
  ativo: boolean
  aprovada: boolean
  criadoEm: string
  dono: DonoPlataforma | null
  outrosAdministradores: Array<{ nome: string; email: string }>
  equipe: number
  eventos: number
  ingressosVendidos: number
  mercadoPagoConectado: boolean
  mercadoPagoConectadoEm: string | null
}

export type SituacaoCasa = 'TODAS' | 'AGUARDANDO' | 'APROVADAS' | 'SEM_MERCADO_PAGO'

const n = (v: unknown) => Number(v ?? 0) || 0
const textoOuNulo = (v: unknown) => (v == null || v === '' ? null : String(v))

export function mapearCasaComDono(row: Record<string, unknown>): CasaComDono {
  const d = row.dono as Record<string, unknown> | null | undefined
  const outros = Array.isArray(row.outros_administradores) ? (row.outros_administradores as Array<Record<string, unknown>>) : []
  return {
    organizacaoId: String(row.organizacao_id ?? ''),
    organizacaoNome: String(row.organizacao_nome ?? ''),
    organizacaoSlug: String(row.organizacao_slug ?? ''),
    ativo: row.ativo !== false,
    aprovada: row.aprovada === true,
    criadoEm: String(row.criado_em ?? ''),
    dono: d
      ? {
          usuarioId: String(d.usuario_id ?? ''),
          nome: String(d.nome ?? ''),
          email: String(d.email ?? ''),
          ativo: d.ativo !== false,
          cadastradoEm: textoOuNulo(d.cadastrado_em),
          ultimoAcessoEm: textoOuNulo(d.ultimo_acesso_em),
          emailConfirmado: d.email_confirmado === true,
          termosVersao: textoOuNulo(d.termos_versao),
          termosAceitosEm: textoOuNulo(d.termos_aceitos_em),
          outrasCasas: n(d.outras_casas)
        }
      : null,
    outrosAdministradores: outros.map((a) => ({ nome: String(a.nome ?? ''), email: String(a.email ?? '') })),
    equipe: n(row.equipe),
    eventos: n(row.eventos),
    ingressosVendidos: n(row.ingressos_vendidos),
    mercadoPagoConectado: row.mercado_pago_conectado === true,
    mercadoPagoConectadoEm: textoOuNulo(row.mercado_pago_conectado_em)
  }
}

function normalizar(texto: string): string {
  return texto.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim()
}

/** Filtra por situacao e busca (casa, endereco da casa, nome ou e-mail do dono). */
export function filtrarCasasComDono(casas: CasaComDono[], busca: string, situacao: SituacaoCasa): CasaComDono[] {
  const termo = normalizar(busca)
  return casas.filter((c) => {
    if (situacao === 'AGUARDANDO' && c.aprovada) return false
    if (situacao === 'APROVADAS' && !c.aprovada) return false
    if (situacao === 'SEM_MERCADO_PAGO' && c.mercadoPagoConectado) return false
    if (!termo) return true
    const alvo = `${c.organizacaoNome} ${c.organizacaoSlug} ${c.dono?.nome ?? ''} ${c.dono?.email ?? ''}`
    return normalizar(alvo).includes(termo)
  })
}

function celulaCsv(valor: unknown): string {
  const texto = valor == null ? '' : String(valor)
  // Evita que planilhas executem formulas vindas de texto digitado pelo usuario.
  const seguro = /^[=+\-@\t\r]/.test(texto) ? `'${texto}` : texto
  return /[";\n\r]/.test(seguro) ? `"${seguro.replace(/"/g, '""')}"` : seguro
}

/** CSV (separado por ;, como o Excel em portugues abre) com uma linha por casa. */
export function gerarCsvDonos(casas: CasaComDono[]): string {
  const cabecalho = [
    'Casa', 'Endereco da casa', 'Situacao', 'Casa criada em', 'Dono', 'E-mail do dono', 'E-mail confirmado',
    'Ultimo acesso', 'Termos (versao)', 'Termos aceitos em', 'Outros administradores', 'Equipe', 'Eventos',
    'Ingressos vendidos', 'Mercado Pago'
  ]
  const linhas = casas.map((c) => [
    c.organizacaoNome,
    c.organizacaoSlug,
    !c.ativo ? 'Desativada' : c.aprovada ? 'Aprovada' : 'Aguardando aprovacao',
    formatDataNumerica(c.criadoEm),
    c.dono?.nome ?? '',
    c.dono?.email ?? '',
    c.dono ? (c.dono.emailConfirmado ? 'Sim' : 'Nao') : '',
    c.dono?.ultimoAcessoEm ? formatDataHoraCompleta(c.dono.ultimoAcessoEm) : '',
    c.dono?.termosVersao ?? '',
    c.dono?.termosAceitosEm ? formatDataHoraCompleta(c.dono.termosAceitosEm) : '',
    c.outrosAdministradores.map((a) => a.email).join(', '),
    c.equipe,
    c.eventos,
    c.ingressosVendidos,
    c.mercadoPagoConectado ? 'Conectado' : 'Nao conectado'
  ])
  return [cabecalho, ...linhas].map((l) => l.map(celulaCsv).join(';')).join('\r\n')
}
