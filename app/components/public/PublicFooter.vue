<script setup lang="ts">
const ano = new Date().getFullYear()
</script>

<template>
  <footer class="border-t border-zinc-800 bg-black">
    <div
      class="mx-auto flex max-w-6xl flex-col gap-2 px-4 py-8 text-sm text-zinc-500 sm:flex-row sm:items-center sm:justify-between sm:px-6"
    >
      <p class="font-semibold text-zinc-300">Galeria Zero 1</p>
      <p>© {{ ano }} Galeria Zero 1. Todos os direitos reservados.</p>
    </div>
  </footer>
</template>
