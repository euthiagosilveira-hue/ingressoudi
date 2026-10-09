import type {
  AdminVipRow,
  VipConvidado,
  VipFormValue,
  VipPayload,
  VipResumo,
  VipStatus
} from '~/types/vip'

function normalizar(valor: string): string {
  return valor
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim()
}

/** Status derivado: nao ha estado duplicado no banco. */
export function statusVip(vip: Pick<VipConvidado, 'entrou'>): VipStatus {
  return vip.entrou ? 'ENTROU' : 'AGUARDANDO'
}

export function rotuloStatusVip(status: VipStatus): string {
  return status === 'ENTROU' ? 'Entrou' : 'Aguardando'
}

/** Converte a linha bruta da RPC no view-model. */
export function mapearVipAdmin(row: AdminVipRow): VipConvidado {
  return {
    vipId: row.vip_id,
    nome: row.nome,
    telefone: row.telefone,
    observacao: row.observacao,
    entrou: Boolean(row.entrou),
    entradaEm: row.entrada_em,
    criadoEm: row.criado_em,
    criadoPor: row.criado_por
  }
}

export function validarVip(form: VipFormValue): { nome?: string } {
  const erros: { nome?: string } = {}
  if (!form.nome.trim()) erros.nome = 'Informe o nome do convidado.'
  return erros
}

/** Normaliza telefone/observacao vazios para null. */
export function montarPayloadVip(form: VipFormValue): VipPayload {
  const telefone = form.telefone.trim()
  const observacao = form.observacao.trim()
  return {
    nome: form.nome.trim(),
    telefone: telefone ? telefone : null,
    observacao: observacao ? observacao : null
  }
}

export function filtrarVips(vips: VipConvidado[], busca: string): VipConvidado[] {
  const termo = normalizar(busca)
  if (!termo) return vips
  return vips.filter(
    (vip) => normalizar(vip.nome).includes(termo) || normalizar(vip.telefone ?? '').includes(termo)
  )
}

export function resumoVips(vips: VipConvidado[]): VipResumo {
  return vips.reduce<VipResumo>(
    (acumulado, vip) => {
      acumulado.total += 1
      if (vip.entrou) acumulado.entraram += 1
      else acumulado.aguardando += 1
      return acumulado
    },
    { total: 0, aguardando: 0, entraram: 0 }
  )
}

export const LIMITE_VIP_LOTE = 100
export const NOME_VIP_MAX = 120

/**
 * Parser do cadastro em lote: uma linha por convidado.
 * Trim em cada linha, remove vazias, preserva acentos e duplicados.
 */
export function parseNomesVip(texto: string): string[] {
  if (typeof texto !== 'string') return []
  return texto
    .split(/\r?\n/)
    .map((linha) => linha.trim())
    .filter((linha) => linha.length > 0)
}

/** Retorna mensagem de erro do lote (ou null se valido). */
export function validarLoteVip(nomes: string[]): string | null {
  if (nomes.length === 0) return 'Informe pelo menos um nome.'
  if (nomes.length > LIMITE_VIP_LOTE) {
    return `Você pode adicionar até ${LIMITE_VIP_LOTE} convidados por vez.`
  }
  if (nomes.some((nome) => nome.trim().length === 0 || nome.trim().length > NOME_VIP_MAX)) {
    return 'Há um nome inválido na lista.'
  }
  return null
}

/** Traduz erros da RPC de cadastro em lote para mensagens amigaveis. */
export function mensagemLoteVip(error: RpcErrorLike | null): string {
  const e = error ?? {}
  const mensagem = (e.message ?? '').toLowerCase()

  if (e.code === '42501' || mensagem.includes('permiss')) {
    return 'Você não tem permissão para gerenciar a lista VIP.'
  }
  if (mensagem.includes('pelo menos um nome')) {
    return 'Informe pelo menos um nome.'
  }
  if (mensagem.includes('100')) {
    return `Você pode adicionar até ${LIMITE_VIP_LOTE} convidados por vez.`
  }
  if (mensagem.includes('nome invalido') || mensagem.includes('nome de convidado muito longo')) {
    return 'Há um nome inválido na lista.'
  }
  if (mensagem.includes('nao permite alterar a lista vip')) {
    return 'Este evento não permite alterar a lista VIP.'
  }
  if (mensagem.includes('nao encontrado')) {
    return 'Evento não encontrado.'
  }
  return 'Não foi possível adicionar os convidados.'
}

interface RpcErrorLike {
  code?: string | null
  message?: string | null
}

/** Traduz erros das RPCs de Lista VIP para mensagens ao operador. */
export function mensagemErroVip(error: RpcErrorLike | null): string {
  const e = error ?? {}
  const mensagem = (e.message ?? '').toLowerCase()

  if (e.code === '42501' || mensagem.includes('permiss')) {
    return 'Você não tem permissão para gerenciar a lista VIP.'
  }
  if (mensagem.includes('ja registrou entrada')) {
    return 'O convidado já registrou entrada e não pode ser alterado.'
  }
  if (mensagem.includes('nao permite alterar a lista vip')) {
    return 'Este evento não permite alterar a lista VIP.'
  }
  if (mensagem.includes('informe o nome')) {
    return 'Informe o nome do convidado.'
  }
  if (mensagem.includes('nao encontrado')) {
    return 'Evento ou convidado não encontrado.'
  }
  if (e.code === '23514') {
    return 'Verifique os dados informados.'
  }
  return 'Não foi possível concluir a operação.'
}
