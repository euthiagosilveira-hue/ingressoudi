import { computed, onMounted, onUnmounted, reactive, ref, watch } from 'vue'

import {
  atualizarUsuarioAdmin,
  convidarUsuarioAdmin,
  listarUsuariosAdmin
} from '~/services/admin/usuarios'
import type { AdminUsuarioRow, ConviteUsuarioInput, EdicaoUsuarioInput } from '~/types/usuario'
import { contarAdminsAtivos, mapearUsuariosAdmin } from '~/utils/usuarios'

const DEBOUNCE_FILTROS_MS = 300

/** Gerenciamento administrativo de usuarios (lista + busca + update + convite). */
export function useAdminUsers() {
  const filtros = reactive({ busca: '' })
  const rows = ref<AdminUsuarioRow[]>([])
  const carregando = ref(false)
  const erro = ref('')
  let debounce: ReturnType<typeof setTimeout> | null = null

  const itens = computed(() => mapearUsuariosAdmin(rows.value))
  const total = computed(() => itens.value.length)
  const adminsAtivos = computed(() => contarAdminsAtivos(rows.value))
  const temFiltros = computed(() => filtros.busca.trim() !== '')

  async function carregar() {
    carregando.value = true
    erro.value = ''
    try {
      rows.value = await listarUsuariosAdmin(filtros.busca)
    } catch (e) {
      erro.value = e instanceof Error ? e.message : 'Não foi possível carregar os usuários.'
      rows.value = []
    } finally {
      carregando.value = false
    }
  }

  async function atualizar(input: EdicaoUsuarioInput) {
    await atualizarUsuarioAdmin(input)
    await carregar()
  }

  async function convidar(input: ConviteUsuarioInput) {
    await convidarUsuarioAdmin(input)
    await carregar()
  }

  watch(
    filtros,
    () => {
      if (debounce) clearTimeout(debounce)
      debounce = setTimeout(() => {
        void carregar()
      }, DEBOUNCE_FILTROS_MS)
    },
    { deep: true }
  )

  onMounted(() => {
    void carregar()
  })

  onUnmounted(() => {
    if (debounce) clearTimeout(debounce)
  })

  function limparFiltros() {
    filtros.busca = ''
  }

  return {
    filtros,
    itens,
    total,
    adminsAtivos,
    carregando,
    erro,
    temFiltros,
    limparFiltros,
    carregar,
    refresh: carregar,
    atualizar,
    convidar
  }
}
