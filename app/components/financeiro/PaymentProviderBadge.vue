<script setup lang="ts">
import { computed } from 'vue'
import { BanknotesIcon, CreditCardIcon } from '@heroicons/vue/24/outline'

import type { PaymentProvider } from '~/types/pagamento'
import { rotuloProvider } from '~/utils/pagamentos'

const props = defineProps<{
  provider: PaymentProvider
}>()

const rotulo = computed(() => rotuloProvider(props.provider))
const Icone = computed(() => (props.provider === 'DINHEIRO' ? BanknotesIcon : CreditCardIcon))
</script>

<template>
  <span
    class="inline-flex items-center gap-1.5 rounded-full border border-zinc-700 bg-zinc-800/70 px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-zinc-300"
  >
    <Icone class="h-3.5 w-3.5" />
    {{ rotulo }}
  </span>
</template>
