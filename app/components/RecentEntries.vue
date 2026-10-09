<script setup lang="ts">
import { CheckIcon, XMarkIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import type { RecentEntry } from '~/types/dashboard'

const props = defineProps<{
  entries: RecentEntry[]
}>()
</script>

<template>
  <BaseCard :padded="false" class="flex h-full flex-col p-5 sm:p-6">
    <div class="flex items-center justify-between gap-3">
      <h3 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">
        Acessos recentes (portaria)
      </h3>
      <button
        type="button"
        class="cursor-pointer text-xs font-medium text-amber-400 transition-colors duration-150 hover:text-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
      >
        Ver todos
      </button>
    </div>

    <div class="mt-5 flex-1 space-y-4">
      <div v-for="entry in props.entries" :key="entry.id" class="flex items-center gap-3">
        <span
          class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border"
          :class="entry.ok
            ? 'border-green-500/70 bg-green-500/5 text-green-400'
            : 'border-red-500/50 bg-red-500/10 text-red-400'"
        >
          <CheckIcon v-if="entry.ok" class="h-4 w-4" />
          <XMarkIcon v-else class="h-4 w-4" />
        </span>

        <div class="min-w-0 flex-1">
          <p class="truncate text-sm font-semibold text-white">{{ entry.name }}</p>
          <p class="text-xs text-zinc-500">{{ entry.ticket }}</p>
        </div>

        <div class="shrink-0 text-right">
          <p class="text-sm text-zinc-300">{{ entry.time }}</p>
          <p
            class="text-xs"
            :class="entry.ok ? 'text-zinc-500' : 'font-medium text-red-400'"
          >
            {{ entry.statusLabel }}
          </p>
        </div>
      </div>
    </div>

    <div class="mt-6 flex justify-center pt-1">
      <AppButton variant="outline">Ver todas as entradas</AppButton>
    </div>
  </BaseCard>
</template>
