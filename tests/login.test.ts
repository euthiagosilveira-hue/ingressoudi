import { test } from 'node:test'
import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

const page = ler('../app/pages/login.vue')

test('login preserva a logica real de autenticacao', () => {
  assert.ok(page.includes('useOperatorAuth'))
  assert.ok(page.includes('login(form.email, form.senha)'))
  assert.ok(page.includes('sanitizarRedirect'))
  assert.ok(page.includes('mensagemLoginErro'))
  assert.ok(page.includes('logout'))
  assert.ok(page.includes("perfil.perfil === 'ADMINISTRADOR'"))
  assert.ok(page.includes("perfil.perfil === 'PORTARIA' ? '/portaria' : '/painel'"))
})

test('login nao usa alert nativo e exibe erro no card', () => {
  assert.ok(!page.includes('alert('))
  assert.ok(page.includes('role="alert"'))
})

test('acessibilidade: labels, autocomplete e toggle de senha', () => {
  assert.ok(page.includes('for="email"'))
  assert.ok(page.includes('for="senha"'))
  assert.ok(page.includes('autocomplete="email"'))
  assert.ok(page.includes('autocomplete="current-password"'))
  assert.ok(page.includes('type="submit"'))
  assert.ok(page.includes(':aria-label="mostrarSenha ?'))
  assert.ok(page.includes(':aria-pressed="mostrarSenha"'))
})

test('nao inventa recursos de autenticacao inexistentes', () => {
  assert.ok(!page.includes('Lembrar de mim'))
  assert.ok(!page.includes('Esqueci minha senha'))
})

test('Voltar ao site aponta para a rota publica', () => {
  assert.ok(page.includes('to="/eventos-publicos"'))
})

test('login tem visual da plataforma, sem foto de casa especifica', () => {
  assert.ok(!page.includes('galeria-fachada'))
  assert.ok(!page.includes('Galeria'))
  assert.ok(!page.includes('<img'))
  assert.ok(page.includes('absolute inset-0'))
  assert.ok(page.includes('Ingressoudi'))
})

test('painel de marca so no desktop e link de cadastro', () => {
  assert.ok(page.includes('hidden flex-col justify-center'))
  assert.ok(page.includes('lg:flex'))
  assert.ok(page.includes('to="/cadastro"'))
})

test('asset antigo login-fachada.jpg foi removido', () => {
  const caminho = fileURLToPath(new URL('../public/login-fachada.jpg', import.meta.url))
  assert.ok(!existsSync(caminho), 'public/login-fachada.jpg nao deve existir')
})

test('loading bloqueia multiplos submits', () => {
  assert.ok(page.includes(':disabled="carregando"'))
  assert.ok(page.includes("carregando ? 'Entrando...' : 'Entrar'"))
})
