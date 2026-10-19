import { onMounted, ref } from 'vue'

import {
  lerPedidosSalvos,
  ordenarPedidosSalvos,
  removerPedidoSalvo,
  type PedidoSalvo
} from '~/utils/ingressosSalvos'

/** Lista reativa dos pedidos salvos neste aparelho (le so no navegador). */
export function useIngressosSalvos() {
  const pedidos = ref<PedidoSalvo[]>([])

  function recarregar() {
    pedidos.value = ordenarPedidosSalvos(lerPedidosSalvos())
  }

  function remover(pedidoId: string) {
    removerPedidoSalvo(pedidoId)
    recarregar()
  }

  onMounted(recarregar)

  return { pedidos, recarregar, remover }
}
