import { computed, onMounted, ref, shallowRef } from 'vue'

import {
  abertoComoApp,
  detectarPlataforma,
  deveMostrarInstalar,
  type PlataformaInstalacao
} from '~/utils/instalarApp'

interface EventoConviteInstalacao extends Event {
  prompt: () => Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

// Estado compartilhado (somente no navegador): o convite nativo chega uma vez
// por carregamento e pode ser usado por qualquer botao da tela.
const conviteNativo = shallowRef<EventoConviteInstalacao | null>(null)
const instalado = ref(false)
let ouvindo = false

/** Chamado pelo plugin pwa.client: guarda o convite nativo de instalacao. */
export function ouvirConviteInstalacao() {
  if (ouvindo || typeof window === 'undefined') return
  ouvindo = true
  window.addEventListener('beforeinstallprompt', (evento) => {
    evento.preventDefault()
    conviteNativo.value = evento as EventoConviteInstalacao
  })
  window.addEventListener('appinstalled', () => {
    conviteNativo.value = null
    instalado.value = true
  })
}

export function useInstalarApp() {
  const plataforma = ref<PlataformaInstalacao>('outra')
  const montado = ref(false)
  const instrucoesAbertas = ref(false)

  onMounted(() => {
    plataforma.value = detectarPlataforma(navigator)
    instalado.value = instalado.value || abertoComoApp(navigator, window.matchMedia?.bind(window))
    montado.value = true
  })

  const visivel = computed(
    () =>
      montado.value &&
      deveMostrarInstalar({
        instalado: instalado.value,
        conviteNativo: conviteNativo.value !== null,
        plataforma: plataforma.value
      })
  )

  async function instalar() {
    const convite = conviteNativo.value
    if (!convite) {
      instrucoesAbertas.value = true
      return
    }
    try {
      await convite.prompt()
      const escolha = await convite.userChoice
      if (escolha.outcome === 'accepted') instalado.value = true
    } catch {
      instrucoesAbertas.value = true
    } finally {
      // o convite nativo so pode ser usado uma vez
      conviteNativo.value = null
    }
  }

  return { plataforma, visivel, instalar, instrucoesAbertas }
}
