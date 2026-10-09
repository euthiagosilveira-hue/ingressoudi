<script setup lang="ts">
const props = defineProps<{
  eventoSlug: string
}>()
</script>

<template>
  <section class="space-y-4 rounded-2xl border-2 border-zinc-700 bg-zinc-900 p-5 text-center sm:p-6">
    <p class="text-lg font-bold uppercase tracking-wide text-zinc-200">Reserva expirada</p>
    <p class="text-sm text-zinc-400">
      O prazo para pagamento terminou. Para comprar os ingressos, inicie uma nova compra.
    </p>

    <NuxtLink
      :to="`/eventos/${props.eventoSlug}/comprar`"
      class="mt-2 inline-flex w-full items-center justify-center rounded-xl bg-amber-400 px-6 py-4 text-sm font-bold uppercase tracking-wide text-zinc-950 transition-colors duration-150 hover:bg-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/60"
    >
      Fazer nova compra
    </NuxtLink>
  </section>
</template>
