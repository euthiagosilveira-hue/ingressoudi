import type { GateRpcResultado, IngressoBuscaNome, RegistrarEntradaQrResult } from '~/types/gate'

/**
 * Validacao apenas de FORMATO (nao decide negocio).
 * O conteudo esperado e um token opaco (UUID). Nada de URL/JSON.
 */
export function qrTokenPlausivel(valor: string): boolean {
  const v = (valor ?? '').trim()
  if (v.length < 8 || v.length > 512) return false
  if (/\s/.test(v)) return false
  return true
}

export function uuidValido(valor: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(valor)
}

/** Validacao apenas de formato do nome para busca (nao e regra de negocio). */
export function nomeBuscaValido(nome: string): boolean {
  return typeof nome === 'string' && nome.trim().length >= 2
}

/** Somente ingresso VALIDO pode ser registrado (decisao final e da RPC). */
export function ingressoRegistravel(status: string): boolean {
  return status === 'VALIDO'
}

/** Mascara o token para exibicao/log (nunca expor cru). */
export function mascararToken(valor: string): string {
  if (!valor) return ''
  if (valor.length <= 8) return '****'
  return `${valor.slice(0, 4)}****${valor.slice(-2)}`
}

/** Trava de leitura: evita processar o mesmo QR varias vezes. */
export class LeituraLock {
  private bloqueado = false

  podeProcessar(): boolean {
    return !this.bloqueado
  }

  bloquear(): void {
    this.bloqueado = true
  }

  liberar(): void {
    this.bloqueado = false
  }
}

/** Normaliza o jsonb da RPC para tipo forte. */
export function mapearResultadoEntradaRpc(raw: Record<string, unknown>): RegistrarEntradaQrResult {
  return {
    resultado: (raw?.resultado as GateRpcResultado) ?? 'INVALIDO',
    ingressoId: (raw?.ingresso_id as string) ?? null,
    vipId: (raw?.vip_id as string) ?? null,
    codigo: (raw?.codigo as string) ?? null,
    participanteNome: (raw?.participante_nome as string) ?? null,
    entradaId: (raw?.entrada_id as string) ?? null,
    entradaEm: (raw?.entrada_em as string) ?? null,
    mensagem: (raw?.mensagem as string) ?? ''
  }
}

/** Chave estavel de um resultado de busca (ingresso ou VIP). */
export function chaveBuscaPortaria(item: IngressoBuscaNome): string {
  return item.origem === 'VIP'
    ? `VIP-${item.vipId ?? ''}`
    : `INGRESSO-${item.ingressoId ?? ''}`
}

export interface ResultadoEntradaRotulo {
  titulo: string
  descricao: string
  sucesso: boolean
}

export function rotuloResultadoEntrada(resultado: GateRpcResultado): ResultadoEntradaRotulo {
  const mapa: Record<GateRpcResultado, ResultadoEntradaRotulo> = {
    LIBERADO: {
      titulo: 'Entrada liberada',
      descricao: 'Entrada registrada com sucesso.',
      sucesso: true
    },
    JA_UTILIZADO: {
      titulo: 'Ingresso já utilizado',
      descricao: 'Este ingresso já registrou entrada.',
      sucesso: false
    },
    NAO_ENCONTRADO: {
      titulo: 'Ingresso não encontrado',
      descricao: 'Nenhum ingresso corresponde a este QR Code.',
      sucesso: false
    },
    EVENTO_INCORRETO: {
      titulo: 'Evento incorreto',
      descricao: 'Este ingresso pertence a outro evento.',
      sucesso: false
    },
    CANCELADO: {
      titulo: 'Ingresso cancelado',
      descricao: 'Este ingresso foi cancelado e não pode ser utilizado.',
      sucesso: false
    },
    INVALIDO: {
      titulo: 'Ingresso inválido',
      descricao: 'Este ingresso não pode ser utilizado.',
      sucesso: false
    }
  }
  return mapa[resultado]
}

/** Mensagens de dominio conhecidas (a RPC retorna texto sem acento historico). */
const MENSAGENS_CONHECIDAS: Record<string, string> = {
  'evento ainda nao iniciado': 'Evento ainda não iniciado.',
  'evento ja realizado': 'Evento já realizado.',
  'evento cancelado': 'Evento cancelado.',
  'ingresso nao esta valido': 'Ingresso não está válido.',
  'ingresso ainda nao pago': 'Ingresso ainda não pago.',
  'ingresso cancelado': 'Ingresso cancelado.',
  'ingresso expirado': 'Ingresso expirado.',
  'ingresso ja utilizado': 'Ingresso já utilizado.',
  'ingresso nao encontrado': 'Ingresso não encontrado.',
  'ingresso pertence a outro evento': 'Ingresso pertence a outro evento.',
  'entrada liberada': 'Entrada liberada.',
  'qr nao informado': 'QR Code não informado.',
  'qr nao encontrado': 'QR Code não encontrado.'
}

/**
 * Só aceita mensagem de dominio segura da RPC.
 * Nunca exibe stack/SQLSTATE/exception/ids/qr_token.
 */
export function mensagemDominioSegura(mensagem?: string | null): boolean {
  if (typeof mensagem !== 'string') return false
  const m = mensagem.trim()
  if (m.length === 0 || m.length > 120) return false
  if (/[\u0000-\u001f]/.test(m)) return false
  if (/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}/i.test(m)) return false
  if (/sqlstate|exception|duplicate|constraint|violat|select |insert |update /i.test(m)) return false
  return true
}

/** Normaliza acentuacao/pontuacao das mensagens conhecidas. */
export function normalizarMensagemEntrada(mensagem: string): string {
  const chave = mensagem.trim().toLowerCase().replace(/\s+/g, ' ')
  if (MENSAGENS_CONHECIDAS[chave]) return MENSAGENS_CONHECIDAS[chave]
  const base = mensagem.trim()
  return /[.!?]$/.test(base) ? base : `${base}.`
}

/**
 * Descricao exibida: preserva o titulo por resultado e usa a mensagem real da
 * RPC quando for segura; caso contrario, cai no texto generico atual.
 */
export function descricaoResultadoEntrada(
  resultado: GateRpcResultado,
  mensagem?: string | null
): string {
  const rotulo = rotuloResultadoEntrada(resultado)
  if (resultado === 'LIBERADO') return rotulo.descricao
  if (mensagemDominioSegura(mensagem)) return normalizarMensagemEntrada(mensagem as string)
  return rotulo.descricao
}
