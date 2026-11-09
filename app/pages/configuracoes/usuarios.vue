<script setup lang="ts">
import UserList from '~/components/usuarios/UserList.vue'

definePageMeta({
  title: 'Usuários',
  description: 'Gerencie quem pode acessar o administrativo, a portaria e as vendas dos sócios.',
  layout: 'admin-layout',
  sidebarActive: 'Configurações',
  middleware: ['admin-auth', 'sem-modo-suporte']
})
</script>

<template>
  <UserList />
</template>
