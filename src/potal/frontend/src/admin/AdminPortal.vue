<script setup lang="ts">
import AdminLogin from './AdminLogin.vue'
import AdminShell from './AdminShell.vue'
import type { AdminLoginForm, AdminMenuItem, AdminMenuKey, AdminShellHealth } from './types'

defineProps<{
  adminLoggedIn: boolean
  loginForm: AdminLoginForm
  loginStatus: string
  loginKind: 'ok' | 'err' | ''
  adminMenu: AdminMenuKey
  menuItems: readonly AdminMenuItem[]
  currentItem: AdminMenuItem
  maskedAdminToken: string
  shellHealth: AdminShellHealth
  healthChecking: boolean
  adminReloading: boolean
}>()

const emit = defineEmits<{
  login: []
  'update:adminMenu': [value: AdminMenuKey]
  refreshHealth: []
  reloadAdmin: []
  logout: []
}>()
</script>

<template>
  <section class="admin-shell admin-appshell" data-admin-ui="appshell-banner" aria-label="1API admin portal">
    <a v-if="adminLoggedIn" class="admin-skip-link" href="#admin-content">Bỏ qua menu</a>

    <AdminLogin
      v-if="!adminLoggedIn"
      :form="loginForm"
      :status="loginStatus"
      :kind="loginKind"
      @login="emit('login')"
    />

    <AdminShell
      v-else
      :admin-menu="adminMenu"
      :menu-items="menuItems"
      :current-item="currentItem"
      :masked-admin-token="maskedAdminToken"
      :shell-health="shellHealth"
      :health-checking="healthChecking"
      :admin-reloading="adminReloading"
      @update:admin-menu="emit('update:adminMenu', $event)"
      @refresh-health="emit('refreshHealth')"
      @reload-admin="emit('reloadAdmin')"
      @logout="emit('logout')"
    >
      <slot />
    </AdminShell>

    <slot name="modals" />
  </section>
</template>
