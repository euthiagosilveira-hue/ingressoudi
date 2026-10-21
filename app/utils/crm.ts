/**
 * CRM comercial da plataforma (super admin): etapas do funil, mapeamento do
 * banco e indicadores. Helpers puros (testaveis). Datas YYYY-MM-DD.
 */

export type EtapaCrm =
  | 'MAPEADO'
  | 'CONTATADO'
  | 'INTERESSADO'
  | 'DEMO_AGENDADA'
  | 'DEMO_REALIZADA'
  | 'CADASTRO_INICIADO'
  | 'EVENTO_PUBLICADO'
  | 'PRIMEIRA_VENDA'
  | 'CLIENTE_RECORRENTE'

export const ETAPAS_CRM: Array<{ value: EtapaCrm; label: string; descricao: string }> = [
  { value: 'MAPEADO', label: 'Mapeado', descricao: 'Produtor identificado.' },
  { value: 'CONTATADO', label: 'Contatado', descricao: 'Primeira abordagem realizada.' },
  { value: 'INTERESSADO', label: 'Interessado', descricao: 'Respondeu e demonstrou interesse.' },
  { value: 'DEMO_AGENDADA', label: 'Demonstração agendada', descricao: 'Reunião marcada.' },
  { value: 'DEMO_REALIZADA', label: 'Demonstração realizada', descricao: 'Plataforma apresentada.' },
  { value: 'CADASTRO_INICIADO', label: 'Cadastro iniciado', descricao: 'Produtor começou a configuração.' },
  { value: 'EVENTO_PUBLICADO', label: 'Evento publicado', descricao: 'Primeiro evento disponibilizado.' },
  { value: 'PRIMEIRA_VENDA', label: 'Primeira venda', descricao: 'Venda realizada com sucesso.' },
  { value: 'CLIENTE_RECORRENTE', label: 'Cliente recorrente', descricao: 'Publicou outro evento.' }
]

export function rotuloEtapa(etapa: string): string {
  return ETAPAS_CRM.find((e) => e.value === etapa)?.label ?? etapa
}

/** Posicao no funil: 1 (Mapeado) a 9 (Cliente recorrente); 0 se desconhecida. */
export function ordemEtapa(etapa: string): number {
  return ETAPAS_CRM.findIndex((e) => e.value === etapa) + 1
}

export interface ProdutorCrm {
  id: string
  nomeProdutor: string
  empresaEvento: string
  instagram: string
  whatsapp: string
  cidade: string
  tipoEvento: string
  ultimoContato: string
  etapa: EtapaCrm
  /** Quando entrou na etapa atual (ISO). */
  etapaDesde: string
  totalContatos: number
  proximaAcao: string
  proximaAcaoEm: string
  observacoes: string
  organizacaoId: string
  organizacaoNome: string
  organizacaoSlug: string
  eventosPublicados: number
  ingressosVendidos: number
  receitaGerada: number
  atualizadoEm: string
}

/** Campos editaveis no formulario (texto, como os inputs devolvem). */
export type FormProdutorCrm = Pick<
  ProdutorCrm,
  | 'nomeProdutor'
  | 'empresaEvento'
  | 'instagram'
  | 'whatsapp'
  | 'cidade'
  | 'tipoEvento'
  | 'ultimoContato'
  | 'etapa'
  | 'proximaAcao'
  | 'proximaAcaoEm'
  | 'observacoes'
  | 'organizacaoId'
>

type Linha = Record<string, unknown>
const n = (v: unknown) => Number(v ?? 0) || 0
const s = (v: unknown) => (v == null ? '' : String(v))

export function mapearProdutorCrm(row: Linha): ProdutorCrm {
  const etapa = ordemEtapa(s(row.etapa)) > 0 ? (s(row.etapa) as EtapaCrm) : 'MAPEADO'
  return {
    id: s(row.id),
    nomeProdutor: s(row.nome_produtor),
    empresaEvento: s(row.empresa_evento),
    instagram: s(row.instagram),
    whatsapp: s(row.whatsapp),
    cidade: s(row.cidade),
    tipoEvento: s(row.tipo_evento),
    ultimoContato: s(row.ultimo_contato).slice(0, 10),
    etapa,
    etapaDesde: s(row.etapa_desde),
    totalContatos: n(row.contatos),
    proximaAcao: s(row.proxima_acao),
    proximaAcaoEm: s(row.proxima_acao_em).slice(0, 10),
    observacoes: s(row.observacoes),
    organizacaoId: s(row.organizacao_id),
    organizacaoNome: s(row.organizacao_nome),
    organizacaoSlug: s(row.organizacao_slug),
    eventosPublicados: n(row.eventos_publicados),
    ingressosVendidos: n(row.ingressos_vendidos),
    receitaGerada: n(row.receita_gerada),
    atualizadoEm: s(row.atualizado_em)
  }
}

export function formVazio(): FormProdutorCrm {
  return {
    nomeProdutor: '',
    empresaEvento: '',
    instagram: '',
    whatsapp: '',
    cidade: '',
    tipoEvento: '',
    ultimoContato: '',
    etapa: 'MAPEADO',
    proximaAcao: '',
    proximaAcaoEm: '',
    observacoes: '',
    organizacaoId: ''
  }
}

export function formDoProdutor(p: ProdutorCrm): FormProdutorCrm {
  const { nomeProdutor, empresaEvento, instagram, whatsapp, cidade, tipoEvento, ultimoContato, etapa,
    proximaAcao, proximaAcaoEm, observacoes, organizacaoId } = p
  return { nomeProdutor, empresaEvento, instagram, whatsapp, cidade, tipoEvento, ultimoContato, etapa,
    proximaAcao, proximaAcaoEm, observacoes, organizacaoId }
}

/** Payload da RPC crm_salvar_produtor (snake_case). */
export function dadosParaBanco(f: FormProdutorCrm): Record<string, string> {
  return {
    nome_produtor: f.nomeProdutor.trim(),
    empresa_evento: f.empresaEvento.trim(),
    instagram: f.instagram.trim(),
    whatsapp: f.whatsapp.trim(),
    cidade: f.cidade.trim(),
    tipo_evento: f.tipoEvento.trim(),
    ultimo_contato: f.ultimoContato,
    etapa: f.etapa,
    proxima_acao: f.proximaAcao.trim(),
    proxima_acao_em: f.proximaAcaoEm,
    observacoes: f.observacoes.trim(),
    organizacao_id: f.organizacaoId
  }
}

export function validarFormCrm(f: FormProdutorCrm): string {
  if (!f.nomeProdutor.trim()) return 'Informe o nome do produtor.'
  const re = /^\d{4}-\d{2}-\d{2}$/
  if (f.ultimoContato && !re.test(f.ultimoContato)) return 'Data do último contato inválida.'
  if (f.proximaAcaoEm && !re.test(f.proximaAcaoEm)) return 'Data da próxima ação inválida.'
  return ''
}

/** Link do WhatsApp (assume Brasil quando vier sem o 55). */
export function linkWhatsapp(numero: string): string {
  let d = numero.replace(/\D/g, '')
  if (!d) return ''
  if (d.length <= 11) d = `55${d}`
  return `https://wa.me/${d}`
}

/** Link do Instagram a partir de @perfil, perfil ou URL. */
export function linkInstagram(perfil: string): string {
  const t = perfil.trim()
  if (!t) return ''
  if (/^https?:\/\//i.test(t)) return t
  const user = t.replace(/^@/, '').replace(/^(www\.)?instagram\.com\//i, '').replace(/\/+$/, '')
  return user ? `https://instagram.com/${user}` : ''
}

export type SituacaoAcao = 'ATRASADA' | 'HOJE' | 'FUTURA' | 'SEM_DATA'

export function situacaoAcao(dataIso: string, hojeIso: string): SituacaoAcao {
  if (!dataIso) return 'SEM_DATA'
  if (dataIso < hojeIso) return 'ATRASADA'
  if (dataIso === hojeIso) return 'HOJE'
  return 'FUTURA'
}

/**
 * Etapa que os numeros reais da casa ja comprovam (ou null sem casa ligada).
 * Mais de um evento publicado e com venda = cliente recorrente.
 */
export function etapaComprovada(p: Pick<ProdutorCrm, 'organizacaoId' | 'eventosPublicados' | 'ingressosVendidos'>): EtapaCrm | null {
  if (!p.organizacaoId) return null
  if (p.eventosPublicados >= 2 && p.ingressosVendidos > 0) return 'CLIENTE_RECORRENTE'
  if (p.ingressosVendidos > 0) return 'PRIMEIRA_VENDA'
  if (p.eventosPublicados > 0) return 'EVENTO_PUBLICADO'
  return 'CADASTRO_INICIADO'
}

/** Etapa para a qual vale avancar, quando a casa ja esta a frente do CRM. */
export function sugestaoAvanco(p: ProdutorCrm): EtapaCrm | null {
  const e = etapaComprovada(p)
  return e && ordemEtapa(e) > ordemEtapa(p.etapa) ? e : null
}

export type FiltroCrm = 'TODOS' | 'ACOES' | EtapaCrm

export function filtrarProdutores(lista: ProdutorCrm[], filtro: FiltroCrm, busca: string, hojeIso: string): ProdutorCrm[] {
  const termo = busca
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
  return lista.filter((p) => {
    if (filtro === 'ACOES') {
      const sit = situacaoAcao(p.proximaAcaoEm, hojeIso)
      if (sit !== 'ATRASADA' && sit !== 'HOJE') return false
    } else if (filtro !== 'TODOS' && p.etapa !== filtro) {
      return false
    }
    if (!termo) return true
    const alvo = [p.nomeProdutor, p.empresaEvento, p.instagram, p.cidade, p.tipoEvento, p.whatsapp, p.organizacaoNome]
      .join(' ')
      .toLowerCase()
      .normalize('NFD')
      .replace(/[̀-ͯ]/g, '')
    return alvo.includes(termo)
  })
}

export interface IndicadoresCrm {
  funil: Array<{ etapa: EtapaCrm; atual: number; alcancaram: number }>
  negocio: { eventosPublicados: number; ingressosVendidos: number; valorVendido: number; receitaLiquida: number }
  acoes: { atrasadas: number; hoje: number; totalProdutores: number }
}

export function mapearIndicadoresCrm(row: Linha): IndicadoresCrm {
  const funil = Array.isArray(row.funil) ? (row.funil as Linha[]) : []
  const neg = (row.negocio ?? {}) as Linha
  const ac = (row.acoes ?? {}) as Linha
  return {
    funil: ETAPAS_CRM.map(({ value }) => {
      const f = funil.find((x) => x.etapa === value)
      return { etapa: value, atual: n(f?.atual), alcancaram: n(f?.alcancaram) }
    }),
    negocio: {
      eventosPublicados: n(neg.eventos_publicados),
      ingressosVendidos: n(neg.ingressos_vendidos),
      valorVendido: n(neg.valor_vendido),
      receitaLiquida: n(neg.receita_liquida)
    },
    acoes: { atrasadas: n(ac.atrasadas), hoje: n(ac.hoje), totalProdutores: n(ac.total_produtores) }
  }
}

function pct(parte: number, total: number): number | null {
  return total > 0 ? Math.round((parte / total) * 100) : null
}

/** Os sete indicadores do plano comercial, a partir do funil do periodo. */
export function resumoIndicadores(ind: IndicadoresCrm) {
  const alc = (e: EtapaCrm) => ind.funil.find((f) => f.etapa === e)?.alcancaram ?? 0
  const contatados = alc('CONTATADO')
  const responderam = alc('INTERESSADO')
  const demos = alc('DEMO_REALIZADA')
  const ativos = alc('EVENTO_PUBLICADO')
  return {
    contatados,
    responderam,
    taxaResposta: pct(responderam, contatados),
    demonstracoes: demos,
    produtoresAtivos: ativos,
    conversaoAtivos: pct(ativos, demos),
    eventosPublicados: ind.negocio.eventosPublicados,
    ingressosVendidos: ind.negocio.ingressosVendidos,
    receitaLiquida: ind.negocio.receitaLiquida
  }
}

/** Conversao de cada etapa para a seguinte (quantos dos que chegaram em X chegaram em X+1). */
export function conversaoEntreEtapas(ind: IndicadoresCrm): Array<{ de: EtapaCrm; para: EtapaCrm; percentual: number | null }> {
  return ind.funil.slice(1).map((f, i) => ({
    de: ind.funil[i]!.etapa,
    para: f.etapa,
    percentual: pct(f.alcancaram, ind.funil[i]!.alcancaram)
  }))
}

function celulaCsv(v: string | number): string {
  const t = String(v)
  return /[";\n\r]/.test(t) ? `"${t.replace(/"/g, '""')}"` : t
}

function diaBr(iso: string): string {
  const [a, m, d] = iso.split('-')
  return a && m && d ? `${d}/${m}/${a}` : ''
}

/** Planilha do CRM (CSV com ; para abrir direto no Excel em portugues). */
export function csvProdutores(lista: ProdutorCrm[]): string {
  const cab = [
    'Nome do produtor', 'Empresa ou evento', 'Instagram', 'WhatsApp', 'Cidade', 'Tipo de evento',
    'Último contato', 'Etapa comercial', 'Próxima ação', 'Data da próxima ação', 'Eventos publicados',
    'Ingressos vendidos', 'Receita gerada', 'Casa na plataforma', 'Observações'
  ]
  const linhas = lista.map((p) =>
    [
      p.nomeProdutor, p.empresaEvento, p.instagram, p.whatsapp, p.cidade, p.tipoEvento,
      diaBr(p.ultimoContato), rotuloEtapa(p.etapa), p.proximaAcao, diaBr(p.proximaAcaoEm),
      p.eventosPublicados, p.ingressosVendidos, p.receitaGerada.toFixed(2).replace('.', ','),
      p.organizacaoNome, p.observacoes
    ].map(celulaCsv).join(';')
  )
  return `﻿${[cab.join(';'), ...linhas].join('\r\n')}`
}

/** Dias inteiros desde que o lead entrou na etapa atual (0 = hoje). */
export function diasNaEtapa(etapaDesdeIso: string, agora: Date = new Date()): number | null {
  const desde = Date.parse(etapaDesdeIso)
  if (Number.isNaN(desde)) return null
  return Math.max(0, Math.floor((agora.getTime() - desde) / 86_400_000))
}

/** Lead parado ha muito tempo na mesma etapa (antes de virar cliente). */
export function leadEsfriando(p: Pick<ProdutorCrm, 'etapa' | 'etapaDesde'>, agora: Date = new Date(), limiteDias = 7): boolean {
  if (ordemEtapa(p.etapa) >= ordemEtapa('PRIMEIRA_VENDA')) return false
  const dias = diasNaEtapa(p.etapaDesde, agora)
  return dias !== null && dias >= limiteDias
}

/** Colunas do kanban: uma por etapa, na ordem do funil. */
export function colunasKanban(lista: ProdutorCrm[]): Array<{ etapa: EtapaCrm; label: string; produtores: ProdutorCrm[] }> {
  return ETAPAS_CRM.map((e) => ({
    etapa: e.value,
    label: e.label,
    produtores: lista.filter((p) => p.etapa === e.value)
  }))
}

export type CanalContato = 'WHATSAPP' | 'INSTAGRAM' | 'LIGACAO' | 'REUNIAO' | 'EMAIL' | 'OUTRO'

export const CANAIS_CONTATO: Array<{ value: CanalContato; label: string }> = [
  { value: 'WHATSAPP', label: 'WhatsApp' },
  { value: 'INSTAGRAM', label: 'Instagram' },
  { value: 'LIGACAO', label: 'Ligação' },
  { value: 'REUNIAO', label: 'Reunião' },
  { value: 'EMAIL', label: 'E-mail' },
  { value: 'OUTRO', label: 'Outro' }
]

export function rotuloCanal(canal: string): string {
  return CANAIS_CONTATO.find((c) => c.value === canal)?.label ?? canal
}

export interface EventoLeadCrm {
  tipo: 'ETAPA' | 'CONTATO'
  id: string
  /** Data para ordenar (ISO ou YYYY-MM-DD). */
  quando: string
  titulo: string
  detalhe: string
  por: string
}

export interface DetalheLeadCrm {
  historico: Array<{ id: string; etapaAnterior: string; etapaNova: EtapaCrm; em: string; por: string }>
  contatos: Array<{ id: string; data: string; canal: CanalContato; resumo: string; criadoEm: string; por: string }>
}

export function mapearDetalheLeadCrm(row: Linha): DetalheLeadCrm {
  const hist = Array.isArray(row.historico) ? (row.historico as Linha[]) : []
  const cont = Array.isArray(row.contatos) ? (row.contatos as Linha[]) : []
  return {
    historico: hist.map((h) => ({
      id: s(h.id),
      etapaAnterior: s(h.etapa_anterior),
      etapaNova: s(h.etapa_nova) as EtapaCrm,
      em: s(h.em),
      por: s(h.por)
    })),
    contatos: cont.map((k) => ({
      id: s(k.id),
      data: s(k.data).slice(0, 10),
      canal: s(k.canal) as CanalContato,
      resumo: s(k.resumo),
      criadoEm: s(k.criado_em),
      por: s(k.por)
    }))
  }
}

/**
 * Linha do tempo do lead: mudancas de etapa e contatos juntos, do mais recente
 * para o mais antigo. Contato usa a data informada (meio-dia, para cair no dia certo).
 */
export function linhaDoTempo(d: DetalheLeadCrm): EventoLeadCrm[] {
  const etapas: EventoLeadCrm[] = d.historico.map((h) => ({
    tipo: 'ETAPA',
    id: h.id,
    quando: h.em,
    titulo: h.etapaAnterior ? `${rotuloEtapa(h.etapaAnterior)} → ${rotuloEtapa(h.etapaNova)}` : `Entrou no CRM em ${rotuloEtapa(h.etapaNova)}`,
    detalhe: '',
    por: h.por
  }))
  const contatos: EventoLeadCrm[] = d.contatos.map((k) => ({
    tipo: 'CONTATO',
    id: k.id,
    quando: k.data ? `${k.data}T12:00:00-03:00` : k.criadoEm,
    titulo: `Contato por ${rotuloCanal(k.canal)}`,
    detalhe: k.resumo,
    por: k.por
  }))
  return [...etapas, ...contatos].sort((a, b) => Date.parse(b.quando) - Date.parse(a.quando))
}

export function validarContato(c: { data: string; canal: string; resumo: string }): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(c.data)) return 'Informe a data do contato.'
  if (!CANAIS_CONTATO.some((x) => x.value === c.canal)) return 'Escolha o canal.'
  if (!c.resumo.trim()) return 'Escreva o que foi conversado.'
  return ''
}

/**
 * Ordem dos cartoes dentro da coluna: acoes atrasadas, depois as de hoje, depois
 * as futuras (pela data) e por fim os leads sem proxima acao.
 */
export function ordenarCartoes(lista: ProdutorCrm[], hojeIso: string): ProdutorCrm[] {
  const peso: Record<SituacaoAcao, number> = { ATRASADA: 0, HOJE: 1, FUTURA: 2, SEM_DATA: 3 }
  return [...lista].sort((a, b) => {
    const pa = peso[situacaoAcao(a.proximaAcaoEm, hojeIso)]
    const pb = peso[situacaoAcao(b.proximaAcaoEm, hojeIso)]
    if (pa !== pb) return pa - pb
    if (a.proximaAcaoEm !== b.proximaAcaoEm) return a.proximaAcaoEm < b.proximaAcaoEm ? -1 : 1
    return a.nomeProdutor.localeCompare(b.nomeProdutor, 'pt-BR')
  })
}
