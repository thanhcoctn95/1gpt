<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import { IconDotsVertical, IconLogout, IconLanguage } from '@tabler/icons-vue'
import { setLocale } from '@/i18n'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import {
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar,
} from '@/components/ui/sidebar'

const props = defineProps<{
  label: string
  sub?: string
  onLogout: () => void
}>()

const { isMobile } = useSidebar()
const { locale } = useI18n()

function initials(name: string) {
  return name.slice(0, 2).toUpperCase()
}

function switchLocale() {
  setLocale(locale.value === 'vi' ? 'en' : 'vi')
}
</script>

<template>
  <SidebarMenu>
    <SidebarMenuItem>
      <DropdownMenu>
        <DropdownMenuTrigger as-child>
          <SidebarMenuButton
            size="lg"
            class="data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
          >
            <Avatar class="size-8 rounded-lg">
              <AvatarFallback class="rounded-lg">{{ initials(label) }}</AvatarFallback>
            </Avatar>
            <div class="grid flex-1 text-left text-sm leading-tight">
              <span class="truncate font-medium">{{ label }}</span>
              <span v-if="sub" class="truncate text-xs text-muted-foreground">{{ sub }}</span>
            </div>
            <IconDotsVertical class="ml-auto size-4" />
          </SidebarMenuButton>
        </DropdownMenuTrigger>
        <DropdownMenuContent
          class="w-(--reka-dropdown-menu-trigger-width) min-w-56 rounded-lg"
          :side="isMobile ? 'bottom' : 'right'"
          align="end"
          :side-offset="4"
        >
          <DropdownMenuLabel class="p-0 font-normal">
            <div class="flex items-center gap-2 px-1 py-1.5 text-left text-sm">
              <Avatar class="size-8 rounded-lg">
                <AvatarFallback class="rounded-lg">{{ initials(label) }}</AvatarFallback>
              </Avatar>
              <div class="grid flex-1 text-left text-sm leading-tight">
                <span class="truncate font-medium">{{ label }}</span>
                <span v-if="sub" class="truncate text-xs text-muted-foreground">{{ sub }}</span>
              </div>
            </div>
          </DropdownMenuLabel>
          <DropdownMenuSeparator />
          <DropdownMenuGroup>
            <DropdownMenuItem @click="switchLocale">
              <IconLanguage />
              {{ locale === 'vi' ? 'English' : 'Tiếng Việt' }}
            </DropdownMenuItem>
          </DropdownMenuGroup>
          <DropdownMenuSeparator />
          <DropdownMenuItem @click="props.onLogout">
            <IconLogout />
            {{ $t('common.logout') }}
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </SidebarMenuItem>
  </SidebarMenu>
</template>
