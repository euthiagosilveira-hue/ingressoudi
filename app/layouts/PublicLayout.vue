<template>
  <div class="flex min-h-screen flex-col bg-zinc-950 text-white">
    <PublicHeader />
    <main class="flex-1">
      <slot />
    </main>
    <PublicFooter />
  </div>
</template>
