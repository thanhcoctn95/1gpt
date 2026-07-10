<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { toast } from 'vue-sonner'
import { IconPackage, IconCheck, IconShieldCheck } from '@tabler/icons-vue'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Skeleton } from '@/components/ui/skeleton'
import { useAuth } from '@/composables/useAuth'
import { ApiError, getPublicPlans, getDashboardMe, type PublicPlanRow, type SubscriptionRow } from '@/services/api'
import { formatVnd, formatCredit } from '@/lib/format'

const { t } = useI18n()
const { userApiKey } = useAuth()

const loading = ref(true)
const plans = ref<PublicPlanRow[]>([])
const activePlanTitle = ref('')

const monthlyPlans = computed(() =>
  plans.value
    .filter((p) => p.quota_reset_period === 'daily')
    .sort((a, b) => Number(a.sort_order ?? 0) - Number(b.sort_order ?? 0)),
)
const onetimePlans = computed(() =>
  plans.value
    .filter((p) => p.quota_reset_period !== 'daily')
    .sort((a, b) => Number(a.sort_order ?? 0) - Number(b.sort_order ?? 0)),
)

function isCurrent(plan: PublicPlanRow): boolean {
  return !!activePlanTitle.value && plan.title.trim().toLowerCase() === activePlanTitle.value
}

async function load() {
  loading.value = true
  try {
    const [plansRes, meRes] = await Promise.all([
      getPublicPlans(),
      getDashboardMe(userApiKey.value).catch(() => null),
    ])
    plans.value = plansRes
    const subs = (meRes?.subscriptions ?? []) as SubscriptionRow[]
    const active = subs.find((s) => s.status === 'active') ?? subs[0] ?? null
    activePlanTitle.value = String(active?.plan_title ?? '').trim().toLowerCase()
  } catch (err) {
    toast.error(err instanceof ApiError ? err.message : t('common.error'))
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex flex-col gap-1">
      <h1 class="flex items-center gap-2 text-xl font-semibold tracking-tight sm:text-2xl">
        <IconPackage class="size-5" /> {{ t('user.plans.title') }}
      </h1>
    </div>

    <!-- Monthly plans -->
    <div class="flex flex-col gap-3">
      <div>
        <h2 class="text-base font-semibold">{{ t('user.plans.monthlyTitle') }}</h2>
        <p class="text-sm text-muted-foreground">{{ t('user.plans.monthlySub') }}</p>
      </div>
      <div v-if="loading" class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Skeleton v-for="i in 4" :key="i" class="h-56 w-full" />
      </div>
      <div v-else-if="!monthlyPlans.length" class="py-6 text-center text-sm text-muted-foreground">
        {{ t('user.plans.empty') }}
      </div>
      <div v-else class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Card
          v-for="(plan, idx) in monthlyPlans"
          :key="plan.id"
          :class="['relative flex flex-col', idx === 1 ? 'border-primary shadow-sm' : '']"
        >
          <CardHeader>
            <div class="flex items-center gap-2">
              <Badge v-if="idx === 1" variant="default">{{ t('user.plans.recommended') }}</Badge>
              <Badge v-if="isCurrent(plan)" variant="secondary">{{ t('user.plans.current') }}</Badge>
            </div>
            <CardTitle class="text-lg">{{ plan.title }}</CardTitle>
            <CardDescription>
              <span class="text-2xl font-semibold text-foreground tabular-nums">
                {{ formatVnd(plan.price_amount) }}
              </span>
              <span class="ml-1 text-sm">{{ t('user.plans.perMonth') }}</span>
            </CardDescription>
          </CardHeader>
          <CardContent class="flex flex-1 flex-col gap-3">
            <p class="text-lg font-medium tabular-nums">
              {{ formatCredit(plan.total_amount) }} {{ t('user.plans.creditPerDay') }}
            </p>
            <ul class="flex flex-col gap-2 text-sm text-muted-foreground">
              <li class="flex items-start gap-2">
                <IconCheck class="mt-0.5 size-4 shrink-0 text-primary" />
                {{ t('user.plans.resetDaily') }}
              </li>
              <li v-if="plan.subtitle" class="flex items-start gap-2">
                <IconCheck class="mt-0.5 size-4 shrink-0 text-primary" />
                {{ plan.subtitle }}
              </li>
            </ul>
          </CardContent>
        </Card>
      </div>
    </div>

    <!-- One-time credit packs -->
    <div v-if="loading || onetimePlans.length" class="flex flex-col gap-3">
      <div>
        <h2 class="text-base font-semibold">{{ t('user.plans.onetimeTitle') }}</h2>
        <p class="text-sm text-muted-foreground">{{ t('user.plans.onetimeSub') }}</p>
      </div>
      <div v-if="loading" class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Skeleton v-for="i in 4" :key="i" class="h-52 w-full" />
      </div>
      <div v-else class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Card
          v-for="(plan, idx) in onetimePlans"
          :key="plan.id"
          :class="['flex flex-col', idx === 1 ? 'border-primary shadow-sm' : '']"
        >
          <CardHeader>
            <Badge v-if="idx === 1" variant="default" class="w-fit">{{ t('user.plans.popular') }}</Badge>
            <CardTitle class="text-lg">{{ plan.title }}</CardTitle>
            <CardDescription>
              <span class="text-2xl font-semibold text-foreground tabular-nums">
                {{ formatVnd(plan.price_amount) }}
              </span>
              <span class="ml-1 text-sm">{{ t('user.plans.oneTime') }}</span>
            </CardDescription>
          </CardHeader>
          <CardContent class="flex flex-1 flex-col gap-3">
            <p class="text-lg font-medium tabular-nums">
              {{ formatCredit(plan.total_amount) }} {{ t('user.plans.credit') }}
            </p>
            <ul class="flex flex-col gap-2 text-sm text-muted-foreground">
              <li class="flex items-start gap-2">
                <IconCheck class="mt-0.5 size-4 shrink-0 text-primary" /> {{ t('user.plans.useUntilEmpty') }}
              </li>
              <li class="flex items-start gap-2">
                <IconCheck class="mt-0.5 size-4 shrink-0 text-primary" /> {{ t('user.plans.noExpiry') }}
              </li>
              <li class="flex items-start gap-2">
                <IconCheck class="mt-0.5 size-4 shrink-0 text-primary" /> {{ t('user.plans.stackable') }}
              </li>
            </ul>
          </CardContent>
        </Card>
      </div>
    </div>

    <Card>
      <CardContent class="flex items-start gap-3 py-4 text-sm text-muted-foreground">
        <IconShieldCheck class="mt-0.5 size-5 shrink-0 text-primary" />
        <span>{{ t('user.plans.contactNote') }}</span>
      </CardContent>
    </Card>
  </div>
</template>
