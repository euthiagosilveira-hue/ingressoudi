<script setup lang="ts">
import AppButton from '~/components/AppButton.vue'
import BaseModal from '~/components/BaseModal.vue'
import UserInviteLinkPanel from '~/components/usuarios/UserInviteLinkPanel.vue'

const props = defineProps<{
  open: boolean
  nome: string
  link: string
  carregando?: boolean
  erro?: string
}>()

const emit = defineEmits<{
  close: []
}>()
</script>

<template>
  <BaseModal
    :open="props.open"
    title="Novo link de convite"
    subtitle="O link anterior deixa de funcionar."
    @close="emit('close')"
  >
    <div v-if="props.carregando" class="flex items-center gap-3 text-sm text-zinc-400" role="status">
      <span class="h-5 w-5 animate-spin rounded-full border-2 border-amber-400/30 border-t-amber-400"></span>
      Gerando link…
    </div>
    <p v-else-if="props.erro" class="text-sm text-red-300" role="alert">{{ props.erro }}</p>
    <UserInviteLinkPanel v-else-if="props.link" :nome="props.nome" :link="props.link" />

    <template #footer>
      <div class="flex justify-end">
        <AppButton variant="ghost" @click="emit('close')">Fechar</AppButton>
      </div>
    </template>
  </BaseModal>
</template>
