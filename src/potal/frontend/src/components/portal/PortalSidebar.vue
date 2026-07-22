<script setup lang="ts">
import type { Component } from 'vue'
import { useRoute } from 'vue-router'
import { IconInnerShadowTop } from '@tabler/icons-vue'
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar,
} from '@/components/ui/sidebar'
import PortalUserMenu from './PortalUserMenu.vue'

export interface NavItem {
  title: string
  to: string
  icon?: Component
}

defineProps<{
  title: string
  subtitle?: string
  items: NavItem[]
  accountLabel: string
  accountSub?: string
  onLogout: () => void
}>()

const route = useRoute()
const { isMobile, setOpenMobile } = useSidebar()

function closeMobileNavigation() {
  if (isMobile.value) setOpenMobile(false)
}
</script>

<template>
  <Sidebar collapsible="icon" variant="inset">
    <SidebarHeader>
      <SidebarMenu>
        <SidebarMenuItem>
          <SidebarMenuButton size="lg" as-child class="data-[slot=sidebar-menu-button]:!p-1.5">
            <RouterLink :to="items[0]?.to || '/'" @click="closeMobileNavigation">
              <IconInnerShadowTop class="!size-5" />
              <span class="flex flex-col leading-tight">
                <span class="text-base font-semibold">{{ title }}</span>
                <span v-if="subtitle" class="truncate text-xs text-muted-foreground">{{ subtitle }}</span>
              </span>
            </RouterLink>
          </SidebarMenuButton>
        </SidebarMenuItem>
      </SidebarMenu>
    </SidebarHeader>

    <SidebarContent>
      <SidebarGroup>
        <SidebarGroupContent class="flex flex-col gap-2">
          <SidebarMenu>
            <SidebarMenuItem v-for="item in items" :key="item.to">
              <SidebarMenuButton
                as-child
                :tooltip="item.title"
                :is-active="route.path.startsWith(item.to)"
              >
                <RouterLink :to="item.to" @click="closeMobileNavigation">
                  <component :is="item.icon" v-if="item.icon" />
                  <span>{{ item.title }}</span>
                </RouterLink>
              </SidebarMenuButton>
            </SidebarMenuItem>
          </SidebarMenu>
        </SidebarGroupContent>
      </SidebarGroup>
    </SidebarContent>

    <SidebarFooter>
      <PortalUserMenu :label="accountLabel" :sub="accountSub" :on-logout="onLogout" />
    </SidebarFooter>
  </Sidebar>
</template>
