import { computed, ref } from 'vue'

import { useGateSession } from '~/composables/useGateSession'
import {
  GateError,
  buscarIngressosPorNome,
  registrarEntradaNome,
  registrarEntradaVip
} from '~/services/gate/ingressos'
import type { GateScanErroCode, IngressoBuscaNome, RegistrarEntradaQrResult } from '~/types/gate'
import { nomeBuscaValido, uuidValido } from '~/utils/gate'

type ContextoErro = 'BUSCA' | 'REGISTRO'

/**
 * Busca por nome na portaria: consulta e registro por RPC real, sempre dentro
 * do evento selecionado. Nenhuma regra de negocio no frontend.
 *
 * Em erro TECNICO preserva o contexto (nome digitado / item selecionado) para
 * permitir "Tentar novamente" sem refazer o fluxo.
 */
export function useGateNameSearch(eventoId: () => string) {
  const nome = ref('')
  const buscando = ref(false)
  const registrando = ref(false)
  const resultados = ref<IngressoBuscaNome[]>([])
  const resultado = ref<RegistrarEntradaQrResult | null>(null)
  const erro = ref<GateScanErroCode | null>(null)
  const contextoErro = ref<ContextoErro | null>(null)
  const itemParaRetry = ref<IngressoBuscaNome | null>(null)
  const jaBuscou = ref(false)

  const { registrar: registrarSessao } = useGateSession()

  const nomeValido = computed(() => nomeBuscaValido(nome.value))
  const podeBuscar = computed(() => uuidValido(eventoId()) && nomeValido.value)

  async function buscar() {
    erro.value = null
    contextoErro.value = null
    if (!uuidValido(eventoId())) {
      erro.value = 'SEM_EVENTO'
      return
    }
    if (!nomeValido.value) return

    buscando.value = true
    try {
      resultados.value = await buscarIngressosPorNome({
        eventoId: eventoId(),
        nome: nome.value.trim()
      })
      jaBuscou.value = true
    } catch (e) {
      // Preserva o texto digitado; erro tecnico (nao "nenhum encontrado").
      erro.value = e instanceof GateError ? e.code : 'DESCONHECIDO'
      contextoErro.value = 'BUSCA'
      resultados.value = []
    } finally {
      buscando.value = false
    }
  }

  async function registrar(ingresso: IngressoBuscaNome) {
    erro.value = null
    contextoErro.value = null
    if (!uuidValido(eventoId())) {
      erro.value = 'SEM_EVENTO'
      return
    }
    registrando.value = true
    try {
      if (ingresso.origem === 'VIP') {
        if (!ingresso.vipId) {
          erro.value = 'DESCONHECIDO'
          contextoErro.value = 'REGISTRO'
          itemParaRetry.value = ingresso
          return
        }
        resultado.value = await registrarEntradaVip({
          eventoId: eventoId(),
          vipId: ingresso.vipId
        })
      } else {
        if (!ingresso.ingressoId) {
          erro.value = 'DESCONHECIDO'
          contextoErro.value = 'REGISTRO'
          itemParaRetry.value = ingresso
          return
        }
        resultado.value = await registrarEntradaNome({
          eventoId: eventoId(),
          ingressoId: ingresso.ingressoId
        })
      }

      itemParaRetry.value = null
      // Contabiliza a sessao apenas se LIBERADO (regra no reducer).
      registrarSessao(resultado.value.resultado, {
        nome: resultado.value.participanteNome ?? ingresso.participanteNome,
        tipo: ingresso.origem === 'VIP' ? 'VIP' : 'INGRESSO',
        codigo: ingresso.origem === 'VIP' ? null : ingresso.codigo
      })
    } catch (e) {
      // Preserva o item selecionado para retry; nao incrementa sessao.
      resultado.value = null
      erro.value = e instanceof GateError ? e.code : 'DESCONHECIDO'
      contextoErro.value = 'REGISTRO'
      itemParaRetry.value = ingresso
    } finally {
      registrando.value = false
    }
  }

  /** Retry da ultima busca (mesmo nome), sem limpar o input. */
  function tentarBuscarNovamente() {
    if (buscando.value) return
    void buscar()
  }

  /** Retry do ultimo registro (mesmo item), sem nova busca. */
  function tentarRegistrarNovamente() {
    const item = itemParaRetry.value
    if (!item || registrando.value) return
    void registrar(item)
  }

  function reset() {
    nome.value = ''
    resultados.value = []
    resultado.value = null
    erro.value = null
    contextoErro.value = null
    itemParaRetry.value = null
    jaBuscou.value = false
  }

  return {
    nome,
    buscando,
    registrando,
    resultados,
    resultado,
    erro,
    contextoErro,
    itemParaRetry,
    jaBuscou,
    nomeValido,
    podeBuscar,
    buscar,
    registrar,
    tentarBuscarNovamente,
    tentarRegistrarNovamente,
    reset
  }
}
