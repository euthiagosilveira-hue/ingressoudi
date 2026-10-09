<script setup lang="ts">
import AppButton from '~/components/AppButton.vue'
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
  <div class="overflow-x-auto rounded-2xl border border-zinc-800 bg-zinc-900">
    <table class="w-full min-w-[760px] border-collapse text-left">
      <thead>
        <tr class="text-[11px] uppercase tracking-wide text-zinc-500">
          <th scope="col" class="px-4 py-3 font-medium">Nome</th>
          <th scope="col" class="px-4 py-3 font-medium">E-mail</th>
          <th scope="col" class="px-4 py-3 font-medium">Perfil</th>
          <th scope="col" class="px-4 py-3 font-medium">Status</th>
          <th scope="col" class="px-4 py-3 font-medium">Último acesso</th>
          <th scope="col" class="px-4 py-3 text-right font-medium">Ações</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="usuario in props.usuarios"
          :key="usuario.id"
          class="border-t border-zinc-800 transition-colors duration-150 hover:bg-zinc-800/40"
        >
          <td class="px-4 py-3">
            <p class="text-sm font-semibold text-white">{{ usuario.nome }}</p>
          </td>
          <td class="px-4 py-3 text-sm text-zinc-300">{{ usuario.email }}</td>
          <td class="px-4 py-3"><UserRoleBadge :perfil="usuario.perfil" /></td>
          <td class="px-4 py-3"><UserStatusBadge :ativo="usuario.ativo" /></td>
          <td class="px-4 py-3 text-sm text-zinc-400">{{ usuario.ultimoAcesso }}</td>
          <td class="px-4 py-3 text-right">
            <AppButton variant="outline" size="sm" @click="emit('edit', usuario)">Editar</AppButton>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
