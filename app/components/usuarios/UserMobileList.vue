<script setup lang="ts">
import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import UserRoleBadge from '~/components/usuarios/UserRoleBadge.vue'
import UserStatusBadge from '~/components/usuarios/UserStatusBadge.vue'
import type { UsuarioListItem } from '~/types/usuario'

const props = defineProps<{
  usuarios: UsuarioListItem[]
}>()

const emit = defineEmits<{
  edit: [usuario: UsuarioListItem]
}>()
</script>

<template>
  <div class="flex flex-col gap-4">
    <BaseCard v-for="usuario in props.usuarios" :key="usuario.id" class="flex flex-col gap-3">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <p class="truncate text-sm font-semibold text-white">{{ usuario.nome }}</p>
          <p class="truncate text-xs text-zinc-500">{{ usuario.email }}</p>
        </div>
        <UserStatusBadge :ativo="usuario.ativo" />
      </div>

      <div class="flex items-center justify-between gap-3 border-t border-zinc-800 pt-3">
        <UserRoleBadge :perfil="usuario.perfil" />
        <p class="text-xs text-zinc-500">Último acesso: {{ usuario.ultimoAcesso }}</p>
      </div>

      <div class="border-t border-zinc-800 pt-3">
        <AppButton variant="outline" size="sm" class="w-full" @click="emit('edit', usuario)">
          Editar
        </AppButton>
      </div>
    </BaseCard>
  </div>
</template>
