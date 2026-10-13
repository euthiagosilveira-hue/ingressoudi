<script setup lang="ts">
import { computed, ref } from 'vue'
import { BuildingOffice2Icon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import BaseInput from '~/components/BaseInput.vue'
import PageHeader from '~/components/PageHeader.vue'
import { useOperatorAuth } from '~/composables/useOperatorAuth'
import { criarOrganizacao } from '~/services/admin/organizacoes'

definePageMeta({
  title: 'Organizações',
  description: 'Crie e acesse as organizações (produtores e casas) da plataforma.',
  layout: 'admin-layout',
  sidebarActive: 'Organizações',
  middleware: ['operator-auth']
})

const { operador, trocarOrganizacao } = useOperatorAuth()

const ehSuperAdmin = computed(() => Boolean(operador.value?.superAdmin))
const nome = ref('')
const slug = ref('')
const enviando = ref(false)
const erro = ref('')

async function criar() {
  if (!nome.value.trim()) {
    erro.value = 'Informe o nome da organização.'
    return
  }
  enviando.value = true
  erro.value = ''
  try {
    await criarOrganizacao(nome.value.trim(), slug.value)
    // a nova organizacao ja e a ativa: recarrega a aplicacao nela
    window.location.assign('/')
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível criar a organização.'
    enviando.value = false
  }
}

async function acessar(id: string) {
  erro.value = ''
  try {
    const perfil = await trocarOrganizacao(id)
    window.location.assign(perfil?.perfil === 'PORTARIA' ? '/portaria' : '/')
  } catch {
    erro.value = 'Não foi possível acessar a organização.'
  }
}
</script>

<template>
  <div class="space-y-6">
    <PageHeader
      title="Organizações"
      subtitle="Cada produtor ou casa de eventos é uma organização com dados separados."
    />

    <BaseCard v-if="!ehSuperAdmin">
      <p class="text-sm text-zinc-400">Apenas o super administrador da plataforma acessa esta área.</p>
    </BaseCard>

    <template v-else>
      <BaseCard>
        <h2 class="text-sm font-semibold text-white">Nova organização</h2>
        <p class="mt-1 text-xs text-zinc-500">
          Você será administrador da nova organização e poderá convidar a equipe do produtor em
          Configurações → Usuários.
        </p>
        <form class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2" @submit.prevent="criar">
          <BaseInput v-model="nome" label="Nome" placeholder="Ex.: Casa do Pagode" required />
          <BaseInput
            v-model="slug"
            label="Endereço (opcional)"
            placeholder="gerado a partir do nome"
          />
          <div class="sm:col-span-2 flex items-center gap-3">
            <AppButton type="submit" variant="primary" :disabled="enviando">
              {{ enviando ? 'Criando...' : 'Criar organização' }}
            </AppButton>
            <p v-if="erro" class="text-xs text-red-400">{{ erro }}</p>
          </div>
        </form>
      </BaseCard>

      <BaseCard>
        <h2 class="text-sm font-semibold text-white">Minhas organizações</h2>
        <ul class="mt-4 divide-y divide-zinc-800">
          <li
            v-for="org in operador?.organizacoes ?? []"
            :key="org.id"
            class="flex items-center justify-between gap-3 py-3"
          >
            <div class="flex min-w-0 items-center gap-3">
              <BuildingOffice2Icon class="h-5 w-5 shrink-0 text-amber-400" />
              <div class="min-w-0">
                <p class="truncate text-sm font-semibold text-white">{{ org.nome }}</p>
                <p class="truncate text-xs text-zinc-500">{{ org.slug }} · {{ org.perfil }}</p>
              </div>
            </div>
            <span
              v-if="org.id === operador?.organizacao?.id"
              class="rounded-full border border-amber-400/30 bg-amber-400/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-amber-300"
            >
              Ativa
            </span>
            <AppButton v-else size="sm" @click="acessar(org.id)">Acessar</AppButton>
          </li>
        </ul>
      </BaseCard>
    </template>
  </div>
</template>
