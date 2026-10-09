<script setup lang="ts">
import { ref } from 'vue'
import { toast } from 'vue3-toastify'

import AppButton from '~/components/AppButton.vue'
import PageHeader from '~/components/PageHeader.vue'
import UserEditModal from '~/components/usuarios/UserEditModal.vue'
import UserEmptyState from '~/components/usuarios/UserEmptyState.vue'
import UserFilters from '~/components/usuarios/UserFilters.vue'
import UserInviteModal from '~/components/usuarios/UserInviteModal.vue'
import UserMobileList from '~/components/usuarios/UserMobileList.vue'
import UserTable from '~/components/usuarios/UserTable.vue'
import { useAdminUsers } from '~/composables/useAdminUsers'
import type { ConviteUsuarioInput, EdicaoUsuarioInput, UsuarioListItem } from '~/types/usuario'

const {
  filtros,
  itens,
  total,
  carregando,
  erro,
  temFiltros,
  limparFiltros,
  refresh,
  atualizar,
  convidar
} = useAdminUsers()

const conviteAberto = ref(false)
const usuarioEdicao = ref<UsuarioListItem | null>(null)
const salvando = ref(false)

const edicaoAberta = ref(false)

function abrirConvite() {
  conviteAberto.value = true
}

function abrirEdicao(usuario: UsuarioListItem) {
  usuarioEdicao.value = usuario
  edicaoAberta.value = true
}

function fecharEdicao() {
  edicaoAberta.value = false
  usuarioEdicao.value = null
}

async function aoConvidar(input: ConviteUsuarioInput) {
  salvando.value = true
  try {
    await convidar(input)
    toast.success('Convite enviado com sucesso.')
    conviteAberto.value = false
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível enviar o convite.')
  } finally {
    salvando.value = false
  }
}

async function aoSalvar(input: EdicaoUsuarioInput) {
  salvando.value = true
  try {
    await atualizar(input)
    toast.success('Usuário atualizado com sucesso.')
    fecharEdicao()
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível atualizar o usuário.')
  } finally {
    salvando.value = false
  }
}
</script>

<template>
  <div class="space-y-6">
    <div>
      <NuxtLink
        to="/configuracoes"
        class="text-xs font-medium uppercase tracking-wide text-zinc-500 transition-colors hover:text-zinc-300"
      >
        Configurações
      </NuxtLink>
    </div>

    <PageHeader
      title="Usuários"
      subtitle="Gerencie quem pode acessar o administrativo e a portaria."
    >
      <template #actions>
        <AppButton variant="primary" @click="abrirConvite">Convidar usuário</AppButton>
      </template>
    </PageHeader>

    <UserFilters v-model="filtros.busca" />

    <div v-if="carregando" class="space-y-3" aria-busy="true">
      <div
        v-for="n in 4"
        :key="n"
        class="h-16 animate-pulse rounded-2xl border border-zinc-800 bg-zinc-900"
      />
    </div>

    <div
      v-else-if="erro"
      role="alert"
      class="space-y-3 rounded-2xl border border-red-500/40 bg-red-500/5 p-6 text-center"
    >
      <p class="text-sm font-semibold text-red-300">{{ erro }}</p>
      <button
        type="button"
        class="inline-flex items-center justify-center rounded-xl border border-amber-400/60 px-5 py-2.5 text-xs font-bold uppercase tracking-wide text-amber-400 transition-colors hover:bg-amber-400 hover:text-zinc-950"
        @click="refresh"
      >
        Tentar novamente
      </button>
    </div>

    <template v-else>
      <p class="text-sm text-zinc-500">
        {{ total }} {{ total === 1 ? 'usuário' : 'usuários' }}
      </p>

      <UserEmptyState v-if="total === 0" :tem-filtros="temFiltros" @limpar="limparFiltros" />

      <template v-else>
        <div class="hidden lg:block">
          <UserTable :usuarios="itens" @edit="abrirEdicao" />
        </div>

        <div class="lg:hidden">
          <UserMobileList :usuarios="itens" @edit="abrirEdicao" />
        </div>
      </template>
    </template>

    <UserInviteModal
      :open="conviteAberto"
      :enviando="salvando"
      @close="conviteAberto = false"
      @submit="aoConvidar"
    />

    <UserEditModal
      :open="edicaoAberta"
      :usuario="usuarioEdicao"
      :salvando="salvando"
      @close="fecharEdicao"
      @submit="aoSalvar"
    />
  </div>
</template>
