import { nextTick, onBeforeUnmount, onMounted, ref } from 'vue'

import { calcularPosicaoMenu } from '~/utils/menuFlutuante'

/**
 * Menu de acoes renderizado no <body> (Teleport) com position: fixed, para
 * nao ser cortado por containers com overflow (ex.: tabelas com rolagem).
 */
export function useMenuFlutuante() {
  const aberto = ref(false)
  const raiz = ref<HTMLElement | null>(null)
  const botao = ref<HTMLElement | null>(null)
  const menu = ref<HTMLElement | null>(null)
  const estilo = ref<Record<string, string>>({ top: '0px', left: '0px', visibility: 'hidden' })

  function posicionar() {
    if (!botao.value || !menu.value) return
    const r = botao.value.getBoundingClientRect()
    const { top, left } = calcularPosicaoMenu(
      { top: r.top, bottom: r.bottom, left: r.left, right: r.right },
      { largura: menu.value.offsetWidth, altura: menu.value.offsetHeight },
      { largura: window.innerWidth, altura: window.innerHeight }
    )
    estilo.value = { top: `${top}px`, left: `${left}px`, visibility: 'visible' }
  }

  async function abrir() {
    estilo.value = { top: '0px', left: '0px', visibility: 'hidden' }
    aberto.value = true
    await nextTick()
    posicionar()
  }

  function fechar() {
    aberto.value = false
  }

  function alternar() {
    if (aberto.value) fechar()
    else void abrir()
  }

  function aoClicarFora(evento: MouseEvent) {
    if (!aberto.value) return
    const alvo = evento.target as Node
    if (raiz.value?.contains(alvo) || menu.value?.contains(alvo)) return
    fechar()
  }

  function aoRolarOuRedimensionar(evento: Event) {
    if (!aberto.value) return
    // Rolagem dentro do proprio menu nao fecha.
    if (evento.type === 'scroll' && menu.value?.contains(evento.target as Node)) return
    fechar()
  }

  function aoTeclar(evento: KeyboardEvent) {
    if (aberto.value && evento.key === 'Escape') fechar()
  }

  onMounted(() => {
    document.addEventListener('click', aoClicarFora)
    document.addEventListener('keydown', aoTeclar)
    window.addEventListener('scroll', aoRolarOuRedimensionar, true)
    window.addEventListener('resize', aoRolarOuRedimensionar)
  })

  onBeforeUnmount(() => {
    document.removeEventListener('click', aoClicarFora)
    document.removeEventListener('keydown', aoTeclar)
    window.removeEventListener('scroll', aoRolarOuRedimensionar, true)
    window.removeEventListener('resize', aoRolarOuRedimensionar)
  })

  return { aberto, raiz, botao, menu, estilo, alternar, fechar }
}
