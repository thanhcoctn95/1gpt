<script setup lang="ts">
import type { AdminMenuItem, AdminMenuKey, AdminShellHealth } from './types'

defineProps<{
  adminMenu: AdminMenuKey
  menuItems: readonly AdminMenuItem[]
  currentItem: AdminMenuItem
  maskedAdminToken: string
  shellHealth: AdminShellHealth
  healthChecking: boolean
  adminReloading: boolean
}>()

const emit = defineEmits<{
  'update:adminMenu': [value: AdminMenuKey]
  refreshHealth: []
  reloadAdmin: []
  logout: []
}>()
</script>

<template>
  <div class="admin-app-root">
    <div class="admin-app-workspace">
      <aside class="admin-app-nav-rail" aria-label="Admin sections">
        <div class="admin-app-nav-head">
          <span class="admin-page-kicker">DASHBOARD</span>
          <strong>1API</strong>
          <small>Modern AppShell with a persistent navigation rail, banner workspace, and operational cards.</small>
        </div>
        <nav class="admin-app-section-nav" aria-label="Admin navigation">
          <button
            v-for="item in menuItems"
            :key="item.key"
            class="admin-app-nav-item"
            :class="{ active: adminMenu === item.key }"
            :aria-current="adminMenu === item.key ? 'page' : undefined"
            @click="emit('update:adminMenu', item.key)"
          >
            <span class="admin-nav-icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path v-for="(d, i) in item.icon" :key="i" :d="d" /></svg></span>
            <span class="admin-nav-text"><strong>{{ item.label }}</strong><small>{{ item.desc }}</small></span>
          </button>
        </nav>
        <div class="admin-app-nav-foot">
          <div class="admin-token-chip" :title="maskedAdminToken">
            <span class="admin-dot" aria-hidden="true"></span>
            <span class="admin-token-text">Admin token<code>{{ maskedAdminToken }}</code></span>
          </div>
          <button class="small admin-menu-logout" type="button" @click="emit('logout')">Đăng xuất</button>
        </div>
      </aside>

      <main id="admin-content" class="admin-app-main" :aria-labelledby="'admin-page-heading-' + currentItem.key" tabindex="-1">
        <div class="admin-app-page-shell">
          <header class="admin-app-page-header">
            <div class="admin-page-title">
              <span class="admin-page-kicker">{{ currentItem.label }}</span>
              <h2 :id="'admin-page-heading-' + currentItem.key">{{ currentItem.label }}</h2>
              <p>Manage the operational workspace from a persistent AppShell navigation rail.</p>
            </div>
            <div class="admin-page-actions">
              <div class="admin-health-chip" :class="shellHealth.tone" :title="shellHealth.text">
                <span aria-hidden="true"></span>
                <strong>{{ shellHealth.label }}</strong>
              </div>
              <button class="small" @click="emit('refreshHealth')" :disabled="healthChecking">{{ healthChecking ? 'Checking…' : 'Check API' }}</button>
            </div>
          </header>
          <section class="admin-app-banner" role="status" aria-live="polite" aria-label="Admin AppShell banner">
            <div class="admin-app-banner-copy">
              <span class="admin-page-kicker">AppShell · With Banner</span>
              <h3>Operations Command Center</h3>
              <p>{{ shellHealth.text }}</p>
            </div>
            <div class="admin-app-banner-meta">
              <span>Admin session</span>
              <strong>{{ shellHealth.label }}</strong>
              <code>{{ maskedAdminToken }}</code>
            </div>
          </section>
          <section class="admin-app-page-region" :aria-labelledby="'admin-page-heading-' + currentItem.key">
            <slot />
          </section>
        </div>
      </main>
    </div>
  </div>
</template>
