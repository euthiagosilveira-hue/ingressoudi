import type { SessaoPortaria, TipoEntradaGate, UltimaEntradaGate } from '~/types/gate'

export const SESSAO_VAZIA: SessaoPortaria = { total: 0, ultima: null }

/** Somente LIBERADO conta entrada na sessao. */
export function deveContarEntrada(resultado: string | null | undefined): boolean {
  return resultado === 'LIBERADO'
}

/** Horario local simples HH:mm (nao depende do banco). */
export function formatarHorarioSessao(data: Date = new Date()): string {
  const hh = String(data.getHours()).padStart(2, '0')
  const mm = String(data.getMinutes()).padStart(2, '0')
  return `${hh}:${mm}`
}

export function montarUltimaEntrada(input: {
  nome: string
  tipo: TipoEntradaGate
  codigo?: string | null
  horario: string
}): UltimaEntradaGate {
  const nome = input.nome && input.nome.trim() ? input.nome.trim() : 'Entrada liberada'
  return { nome, tipo: input.tipo, codigo: input.codigo ?? null, horario: input.horario }
}

/**
 * Reducer puro da sessao: incrementa APENAS quando o resultado e LIBERADO.
 * Qualquer outro resultado (inclusive erro) devolve o MESMO estado (sem
 * contagem dupla).
 */
export function registrarNaSessao(
  sessao: SessaoPortaria,
  entrada: {
    resultado: string | null | undefined
    nome: string
    tipo: TipoEntradaGate
    codigo?: string | null
    horario: string
  }
): SessaoPortaria {
  if (!deveContarEntrada(entrada.resultado)) return sessao
  return {
    total: sessao.total + 1,
    ultima: montarUltimaEntrada(entrada)
  }
}

export function resetarSessao(): SessaoPortaria {
  return { total: 0, ultima: null }
}
