/**
 * Regras puras do fluxo automatico de leitura por QR da portaria.
 * Sem DOM/Vue: facilita testes e mantem o composable enxuto.
 */

/** Tempo de exibicao do resultado antes de reabrir a camera automaticamente. */
export const AUTO_RESUME_DELAY_MS = 1800

/** Janela em que o MESMO token recem-lido e ignorado (evita reler o mesmo QR). */
export const SAME_QR_COOLDOWN_MS = 4000

/** Considera sucesso apenas LIBERADO. */
export function sucessoResultado(resultado: string | null | undefined): boolean {
  return resultado === 'LIBERADO'
}

/**
 * Decide se o token detectado deve ser ignorado por ser o MESMO do ultimo
 * processado e estar dentro da janela de cooldown. Token diferente nunca e
 * bloqueado (pode ser lido imediatamente no proximo ciclo).
 */
export function deveIgnorarPorCooldown(
  ultimoToken: string,
  tokenAtual: string,
  lidoEm: number,
  agora: number,
  cooldown: number = SAME_QR_COOLDOWN_MS
): boolean {
  if (!ultimoToken || ultimoToken !== tokenAtual) return false
  const delta = agora - lidoEm
  return delta >= 0 && delta < cooldown
}

/**
 * Auto-resume somente para resultado de negocio (LIBERADO/JA_UTILIZADO/
 * INVALIDO/...). Falha tecnica (erro de transporte) NAO entra em loop
 * automatico, para o operador nao perder a informacao.
 */
export function deveAutoRetomar(input: {
  autoHabilitado: boolean
  temResultado: boolean
  erroTecnico: boolean
}): boolean {
  if (!input.autoHabilitado) return false
  if (input.erroTecnico) return false
  return input.temResultado
}

/** iniciar() e idempotente: nao reabre se a camera ja esta ativa/solicitando. */
export function podeIniciarCamera(status: string): boolean {
  return status !== 'ATIVA' && status !== 'SOLICITANDO'
}

export interface AgendadorUnico {
  agendar: (fn: () => void, ms: number) => void
  cancelar: () => void
  ativo: () => boolean
}

/**
 * Agendador com garantia de UM unico timer pendente: agendar um novo cancela o
 * anterior. Evita multiplos timers de auto-resume concorrentes.
 */
export function criarAgendadorUnico(): AgendadorUnico {
  let timer: ReturnType<typeof setTimeout> | null = null
  return {
    agendar(fn: () => void, ms: number) {
      if (timer !== null) {
        clearTimeout(timer)
        timer = null
      }
      timer = setTimeout(() => {
        timer = null
        fn()
      }, ms)
    },
    cancelar() {
      if (timer !== null) {
        clearTimeout(timer)
        timer = null
      }
    },
    ativo() {
      return timer !== null
    }
  }
}
