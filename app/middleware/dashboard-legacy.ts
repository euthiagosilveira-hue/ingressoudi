export default defineNuxtRouteMiddleware(() => {
  return navigateTo('/painel', { redirectCode: 301 })
})
