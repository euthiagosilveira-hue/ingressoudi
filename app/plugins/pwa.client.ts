import { ouvirConviteInstalacao } from '~/composables/useInstalarApp'

/**
 * App instalavel (PWA): guarda o convite de instalacao do navegador e registra
 * o service worker (somente em producao), que serve uma tela "sem conexao"
 * quando a internet cai. Nada e guardado em cache alem dessa tela.
 */
export default defineNuxtPlugin(() => {
  ouvirConviteInstalacao()

  if (import.meta.dev || !('serviceWorker' in navigator)) return
  const registrar = () => {
    navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch(() => {})
  }
  if (document.readyState === 'complete') registrar()
  else window.addEventListener('load', registrar, { once: true })
})
