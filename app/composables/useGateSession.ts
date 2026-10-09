import { computed } from 'vue'

import type { SessaoPortaria, TipoEntradaGate } from '~/types/gate'
import { formatarHorarioSessao, registrarNaSessao } from '~/utils/portariaSessao'

const CHAVE = 'gate-sessao-v1'

/**
 * Sessao local da portaria (somente memoria / por aba):
 *   * contador de entradas LIBERADAS;
 *   * ultima entrada liberada.
 * Nao persiste em banco/localStorage; reset ao recarregar a pagina.
 * Estado compartilhado (useState) entre QR e busca por nome.
 */
export function useGateSession() {
  const sessao = useState<SessaoPortaria>(CHAVE, () => ({ total: 0, ultima: null }))

  const total = computed(() => sessao.value.total)
  const ultima = computed(() => sessao.value.ultima)

  function registrar(
    resultado: string | null | undefined,
    dados: { nome: string; tipo: TipoEntradaGate; codigo?: string | null }
  ): void {
    sessao.value = registrarNaSessao(sessao.value, {
      resultado,
      nome: dados.nome,
      tipo: dados.tipo,
      codigo: dados.codigo ?? null,
      horario: formatarHorarioSessao()
    })
  }

  function resetar(): void {
    sessao.value = { total: 0, ultima: null }
  }

  return { total, ultima, registrar, resetar }
}
