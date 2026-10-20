import { computed, onMounted, ref } from 'vue'

import { registrarAssinaturaPush, removerAssinaturaPush } from '~/services/admin/push'
import { chaveVapidParaBytes, precisaInstalarNoIphone, textoSituacaoPush, type SituacaoPush } from '~/utils/push'

/** Estado e acoes do aviso push do super admin neste aparelho. */
export function usePushSuperAdmin() {
  const config = useRuntimeConfig()
  const situacao = ref<SituacaoPush>('sem-suporte')
  const processando = ref(false)
  const erro = ref('')

  const texto = computed(() => textoSituacaoPush(situacao.value))

  function suportado(): boolean {
    return (
      typeof window !== 'undefined' &&
      'serviceWorker' in navigator &&
      'PushManager' in window &&
      'Notification' in window &&
      Boolean(config.public.vapidPublicKey)
    )
  }

  async function atualizar() {
    const standalone =
      typeof window !== 'undefined' &&
      (window.matchMedia?.('(display-mode: standalone)').matches || (navigator as { standalone?: boolean }).standalone === true)
    if (typeof navigator !== 'undefined' && precisaInstalarNoIphone(navigator.userAgent, Boolean(standalone)) && !suportado()) {
      situacao.value = 'instalar-iphone'
      return
    }
    if (!suportado()) {
      situacao.value = 'sem-suporte'
      return
    }
    if (Notification.permission === 'denied') {
      situacao.value = 'bloqueado'
      return
    }
    const registro = await navigator.serviceWorker.getRegistration()
    const assinatura = await registro?.pushManager.getSubscription()
    situacao.value = assinatura ? 'ativado' : 'desativado'
  }

  async function ativar() {
    erro.value = ''
    processando.value = true
    try {
      const permissao = await Notification.requestPermission()
      if (permissao !== 'granted') {
        situacao.value = permissao === 'denied' ? 'bloqueado' : 'desativado'
        return
      }
      const registro = await navigator.serviceWorker.register('/sw.js', { scope: '/' })
      await navigator.serviceWorker.ready
      const assinatura =
        (await registro.pushManager.getSubscription()) ??
        (await registro.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: chaveVapidParaBytes(String(config.public.vapidPublicKey))
        }))
      await registrarAssinaturaPush(assinatura)
      situacao.value = 'ativado'
    } catch (e) {
      erro.value = e instanceof Error ? e.message : 'Não foi possível ativar as notificações.'
    } finally {
      processando.value = false
    }
  }

  async function desativar() {
    erro.value = ''
    processando.value = true
    try {
      const registro = await navigator.serviceWorker.getRegistration()
      const assinatura = await registro?.pushManager.getSubscription()
      if (assinatura) {
        await removerAssinaturaPush(assinatura.endpoint)
        await assinatura.unsubscribe()
      }
      situacao.value = 'desativado'
    } catch (e) {
      erro.value = e instanceof Error ? e.message : 'Não foi possível desativar as notificações.'
    } finally {
      processando.value = false
    }
  }

  onMounted(() => {
    void atualizar().catch(() => {
      situacao.value = 'sem-suporte'
    })
  })

  return { situacao, texto, processando, erro, ativar, desativar }
}
