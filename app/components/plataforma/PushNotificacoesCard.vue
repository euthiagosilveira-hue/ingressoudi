<script setup lang="ts">
import { BellAlertIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import { usePushSuperAdmin } from '~/composables/usePushSuperAdmin'

const { situacao, texto, processando, erro, ativar, desativar } = usePushSuperAdmin()
</script>

<template>
  <BaseCard>
    <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
      <div class="flex items-start gap-3">
        <BellAlertIcon class="mt-0.5 h-5 w-5 shrink-0 text-amber-400" />
        <div>
          <h2 class="text-sm font-semibold text-white">Notificações neste aparelho</h2>
          <p class="mt-1 text-xs text-zinc-400">{{ texto }}</p>
          <p v-if="erro" class="mt-1 text-xs text-red-300">{{ erro }}</p>
        </div>
      </div>
      <AppButton
        v-if="situacao === 'desativado'"
        variant="primary"
        size="sm"
        :disabled="processando"
        @click="ativar"
      >
        Ativar notificações
      </AppButton>
      <AppButton
        v-else-if="situacao === 'ativado'"
        variant="ghost"
        size="sm"
        :disabled="processando"
        @click="desativar"
      >
        Desativar neste aparelho
      </AppButton>
    </div>
  </BaseCard>
</template>
