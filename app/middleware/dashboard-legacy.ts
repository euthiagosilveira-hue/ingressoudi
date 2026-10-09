export default defineNuxtRouteMiddleware(() => {
  return navigateTo('/', { redirectCode: 301 })
})
