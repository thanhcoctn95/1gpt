<script setup lang="ts">
import { computed } from "vue";
import { useRouter, useRoute, RouterView } from "vue-router";
import { useI18n } from "vue-i18n";
import {
	IconLayoutDashboard,
	IconCpu,
	IconListDetails,
	IconPackage,
	IconBook2,
} from "@tabler/icons-vue";
import { SidebarInset, SidebarProvider } from "@/components/ui/sidebar";
import PortalSidebar, {
	type NavItem,
} from "@/components/portal/PortalSidebar.vue";
import PortalHeader from "@/components/portal/PortalHeader.vue";
import { useAuth } from "@/composables/useAuth";
import { maskKey } from "@/lib/format";

const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const { userApiKey, logoutUser } = useAuth();

const items = computed<NavItem[]>(() => [
	{
		title: t("user.nav.overview"),
		to: "/user/overview",
		icon: IconLayoutDashboard,
	},
	{ title: t("user.nav.models"), to: "/user/models", icon: IconCpu },
	{ title: t("user.nav.plans"), to: "/user/plans", icon: IconPackage },
	{ title: t("user.nav.guide"), to: "/user/guide", icon: IconBook2 },
	{ title: t("user.nav.logs"), to: "/user/logs", icon: IconListDetails },
]);

const pageTitle = computed(() => {
	const active = items.value.find((i) => route.path.startsWith(i.to));
	return active?.title ?? t("common.appName");
});

function handleLogout() {
	logoutUser();
	router.push({ name: "user-login" });
}
</script>

<template>
  <SidebarProvider>
    <PortalSidebar
      :title="t('common.appName')"
      :subtitle="t('common.user')"
      :items="items"
      :account-label="maskKey(userApiKey)"
      :account-sub="t('common.user')"
      :on-logout="handleLogout"
    />
    <SidebarInset>
      <PortalHeader :title="pageTitle" />
      <div class="flex flex-1 flex-col gap-4 p-4 md:gap-6 md:p-6">
        <RouterView />
      </div>
    </SidebarInset>
  </SidebarProvider>
</template>
