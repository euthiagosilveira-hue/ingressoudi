import type { PublicVendaSituacao } from '../types/publicEvento.ts'
import { rotaOrganizacao, urlPublicaAbsoluta } from './rotasPublicas.ts'

/** Link completo da vitrine da casa (ex.: https://www.ingressoudi.com.br/casa). */
export function urlVitrine(origem: string | null | undefined, organizacaoSlug: string | null | undefined): string {
  const slug = String(organizacaoSlug ?? '').trim()
  if (!slug) return ''
  return urlPublicaAbsoluta(origem, rotaOrganizacao(slug))
}

export interface GrupoMes<T> {
  /** AAAA-MM no fuso de Sao Paulo. */
  chave: string
  /** Ex.: "Novembro de 2026". */
  rotulo: string
  eventos: T[]
}

const fusoSP = 'America/Sao_Paulo'

function chaveMes(data: Date): string {
  const partes = new Intl.DateTimeFormat('en-CA', { year: 'numeric', month: '2-digit', timeZone: fusoSP })
    .formatToParts(data)
  const ano = partes.find((p) => p.type === 'year')?.value ?? ''
  const mes = partes.find((p) => p.type === 'month')?.value ?? ''
  return `${ano}-${mes}`
}

function rotuloMes(data: Date): string {
  const texto = new Intl.DateTimeFormat('pt-BR', { month: 'long', year: 'numeric', timeZone: fusoSP }).format(data)
  return texto.charAt(0).toUpperCase() + texto.slice(1)
}

/**
 * Agrupa a agenda por mes (fuso de Sao Paulo), em ordem cronologica.
 * Datas invalidas vao para o fim, no grupo "Outras datas".
 */
export function agruparEventosPorMes<T extends { inicioEm: string }>(eventos: T[]): GrupoMes<T>[] {
  const ordenados = [...eventos].sort((a, b) => {
    const ta = new Date(a.inicioEm).getTime()
    const tb = new Date(b.inicioEm).getTime()
    if (Number.isNaN(ta)) return 1
    if (Number.isNaN(tb)) return -1
    return ta - tb
  })

  const grupos: GrupoMes<T>[] = []
  for (const evento of ordenados) {
    const data = new Date(evento.inicioEm)
    const valida = !Number.isNaN(data.getTime())
    const chave = valida ? chaveMes(data) : 'sem-data'
    let grupo = grupos.find((g) => g.chave === chave)
    if (!grupo) {
      grupo = { chave, rotulo: valida ? rotuloMes(data) : 'Outras datas', eventos: [] }
      grupos.push(grupo)
    }
    grupo.eventos.push(evento)
  }
  return grupos
}

/** Selo do card na vitrine; null quando as vendas estao abertas. */
export function seloSituacaoVitrine(situacao: PublicVendaSituacao | null | undefined): string | null {
  const mapa: Partial<Record<PublicVendaSituacao, string>> = {
    ESGOTADO: 'Esgotado',
    SEM_LOTE: 'Em breve',
    VENDAS_ENCERRADAS: 'Vendas encerradas'
  }
  return situacao ? (mapa[situacao] ?? null) : null
}

/** Texto do contador da agenda (ex.: "3 eventos na agenda"). */
export function textoQuantidadeEventos(total: number): string {
  if (total <= 0) return 'Nenhum evento na agenda'
  return total === 1 ? '1 evento na agenda' : `${total} eventos na agenda`
}
