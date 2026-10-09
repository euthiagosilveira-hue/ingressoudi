<script setup lang="ts">
import BaseCard from '~/components/BaseCard.vue'
import type { OrderDetail } from '~/types/pedido'

const props = defineProps<{
  pedido: OrderDetail
}>()
</script>

<template>
  <BaseCard class="space-y-4">
    <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">Comprador</h2>

    <dl class="space-y-3">
      <div>
        <dt class="text-xs text-zinc-500">Nome</dt>
        <dd class="text-sm text-zinc-200">{{ props.pedido.compradorNome }}</dd>
      </div>
      <div>
        <dt class="text-xs text-zinc-500">Telefone</dt>
        <dd class="break-words text-sm text-zinc-200">{{ props.pedido.telefone }}</dd>
      </div>
      <div>
        <dt class="text-xs text-zinc-500">Email</dt>
        <dd class="break-all text-sm text-zinc-200">
          {{ props.pedido.email ?? 'Não informado' }}
        </dd>
      </div>
    </dl>
  </BaseCard>
</template>
