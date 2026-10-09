import { onMounted, onUnmounted, ref } from 'vue'

/**
 * Conectividade da portaria: observa online/offline apenas para indicador
 * visual. NUNCA dispara retry automatico ao voltar online — o operador decide.
 */
export function useGateConectividade() {
  const online = ref(true)

  function atualizar() {
    online.value = typeof navigator === 'undefined' ? true : navigator.onLine !== false
  }

  function aoMudar() {
    atualizar()
  }

  onMounted(() => {
    atualizar()
    if (typeof window === 'undefined') return
    window.addEventListener('online', aoMudar)
    window.addEventListener('offline', aoMudar)
  })

  onUnmounted(() => {
    if (typeof window === 'undefined') return
    window.removeEventListener('online', aoMudar)
    window.removeEventListener('offline', aoMudar)
  })

  return { online, atualizar }
}
