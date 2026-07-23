<script setup lang="ts">
import { computed } from 'vue'
import { useRouter, useRoute, RouterView } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { IconLayoutDashboard, IconUsers, IconCpu, IconListDetails, IconPackage } from '@tabler/icons-vue'
import { SidebarInset, SidebarProvider } from '@/components/ui/sidebar'
import PortalSidebar, { type NavItem } from '@/components/portal/PortalSidebar.vue'
import PortalHeader from '@/components/portal/PortalHeader.vue'
import { useAuth } from '@/composables/useAuth'

const { t } = useI18n()
const router = useRouter()
const route = useRoute()
const { adminUser, logoutAdmin } = useAuth()

const items = computed<NavItem[]>(() => [
  { title: t('admin.nav.overview'), to: '/admin/overview', icon: IconLayoutDashboard },
  { title: t('admin.nav.users'), to: '/admin/users', icon: IconUsers },
  { title: t('admin.nav.models'), to: '/admin/models', icon: IconCpu },
  { title: t('admin.nav.plans'), to: '/admin/plans', icon: IconPackage },
  { title: t('admin.nav.logs'), to: '/admin/logs', icon: IconListDetails },
])

const pageTitle = computed(() => {
  const active = items.value.find((i) => route.path.startsWith(i.to))
  return active?.title ?? t('common.appName')
})

function handleLogout() {
  logoutAdmin()
  router.push({ name: 'admin-login' })
}
</script>

<template>
  <SidebarProvider>
    <PortalSidebar
      :title="t('common.appName')"
      :subtitle="t('common.admin')"
      :items="items"
      :account-label="adminUser?.username ?? t('common.admin')"
      :account-sub="t('common.admin')"
      :on-logout="handleLogout"
    />
    <SidebarInset class="min-w-0 md:w-auto">
      <PortalHeader :title="pageTitle" />
      <div class="flex flex-1 scroll-mt-[calc(3rem+env(safe-area-inset-top))] flex-col gap-4 p-4 md:gap-6 md:p-6">
        <RouterView />
      </div>
    </SidebarInset>
  </SidebarProvider>
</template>
