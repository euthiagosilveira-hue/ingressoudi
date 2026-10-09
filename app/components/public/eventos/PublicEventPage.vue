<script setup lang="ts">
import PublicEventDescription from '~/components/public/eventos/PublicEventDescription.vue'
import PublicEventHero from '~/components/public/eventos/PublicEventHero.vue'
import PublicEventInfo from '~/components/public/eventos/PublicEventInfo.vue'
import PublicEventPurchaseCard from '~/components/public/eventos/PublicEventPurchaseCard.vue'
import type { PublicEventDetail } from '~/types/publicEvento'

const props = defineProps<{
  evento: PublicEventDetail
}>()
</script>

<template>
  <div class="mx-auto w-full max-w-6xl px-4 py-6 sm:px-6 sm:py-10">
    <div class="grid grid-cols-1 gap-6 lg:grid-cols-3">
      <div class="space-y-6 lg:col-span-2">
        <PublicEventHero :evento="props.evento" />

        <div class="lg:hidden">
          <PublicEventPurchaseCard :evento="props.evento" />
        </div>

        <PublicEventInfo :evento="props.evento" />
        <PublicEventDescription :descricao="props.evento.descricao" />
      </div>

      <div class="hidden lg:block">
        <PublicEventPurchaseCard :evento="props.evento" />
      </div>
    </div>
  </div>
</template>
