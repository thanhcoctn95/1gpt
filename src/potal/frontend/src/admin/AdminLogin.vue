<script setup lang="ts">
import type { AdminLoginForm } from './types'

defineProps<{
  form: AdminLoginForm
  status: string
  kind: 'ok' | 'err' | ''
}>()

const emit = defineEmits<{
  login: []
}>()
</script>

<template>
  <main id="admin-content" class="admin-login-screen" aria-labelledby="admin-login-title" tabindex="-1">
    <section class="admin-login-hero" aria-label="Admin login">
      <div class="admin-login-copy">
        <span class="admin-page-kicker">Admin Access</span>
        <h1 id="admin-login-title">1API Admin Portal</h1>
        <p>Secure login is required before the AppShell workspace, navigation, and operational data are shown.</p>
      </div>

      <section class="admin-login-card" aria-labelledby="admin-login-card-title">
        <div class="admin-login-brand">
          <span class="admin-brand-mark">1</span>
          <span>1API Admin</span>
        </div>
        <div class="section-title">
          <h2 id="admin-login-card-title">Sign in to continue</h2>
          <p>Enter the admin credentials to open the protected AppShell workspace.</p>
        </div>
        <div class="stack">
          <label>Admin username<input v-model="form.username" placeholder="admin" autocomplete="username" @keyup.enter="emit('login')" /></label>
          <label>Password<input v-model="form.password" type="password" placeholder="Admin password" autocomplete="current-password" @keyup.enter="emit('login')" /></label>
        </div>
        <div class="admin-login-meta"><span>Protected area</span><span>Masked secrets</span></div>
        <div class="actions"><button class="primary" type="button" @click="emit('login')">Đăng nhập admin</button></div>
        <p v-if="status" class="admin-banner" :class="kind" role="status">{{ status }}</p>
      </section>
    </section>
  </main>
</template>
