<script setup lang="ts">
import UserList from '~/components/usuarios/UserList.vue'

definePageMeta({
  title: 'Usuários',
  description: 'Gerencie quem pode acessar o administrativo e a portaria.',
  layout: 'admin-layout',
  sidebarActive: 'Configurações',
  middleware: ['admin-auth']
})
</script>

<template>
  <UserList />
</template>
