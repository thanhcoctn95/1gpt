<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { toast } from 'vue-sonner'
import {
  IconPackage,
  IconCoin,
  IconLink,
  IconRefresh,
  IconActivity,
  IconTrophy,
  IconCopy,
  IconTrendingUp,
} from '@tabler/icons-vue'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip'
import { useAuth } from '@/composables/useAuth'
import {
  getDashboardMe,
  getPortalConfig,
  getDashboardLogs,
  getPublicPlans,
  ApiError,
  type DashboardMe,
  type SubscriptionRow,
  type LogRow,
  type PublicPlanRow,
} from '@/services/api'
import {
  formatVnd,
  formatNumber,
  formatCredit,
  formatDate,
  computeRefund,
  computeUpgradeCost,
} from '@/lib/format'

const { t } = useI18n()
const { userApiKey } = useAuth()

const loading = ref(true)
const me = ref<DashboardMe | null>(null)
const connectionUrl = ref('')
const logs = ref<LogRow[]>([])
const plans = ref<PublicPlanRow[]>([])

const activeMonthlySub = computed<SubscriptionRow | null>(() =>
  (me.value?.subscriptions ?? []).find(
    (s) => s.status === 'active' && s.quota_reset_period !== 'never',
  ) ?? null,
)

const activeTokenPacks = computed(() =>
  (me.value?.subscriptions ?? []).filter(
    (s) => s.status === 'active' && s.quota_reset_period === 'never',
  ),
)

const hasPaygWallet = computed(() => activeTokenPacks.value.length > 0)
const isPaygOnly = computed(() => !activeMonthlySub.value && hasPaygWallet.value)

const activeSub = computed<SubscriptionRow | null>(() =>
  activeMonthlySub.value
    ?? activeTokenPacks.value[0]
    ?? (me.value?.subscriptions ?? [])[0]
    ?? null,
)

const tokenPackTotals = computed(() =>
  activeTokenPacks.value.reduce(
    (totals, sub) => ({
      used: totals.used + Number(sub.amount_used ?? 0),
      left: totals.left + Number(sub.amount_left ?? 0),
    }),
    { used: 0, left: 0 },
  ),
)

const displayedPlanTitle = computed(() =>
  isPaygOnly.value ? t('user.overview.paygWallet') : activeSub.value?.plan_title,
)

const displayedCredit = computed(() => {
  if (activeMonthlySub.value) {
    return {
      used: Number(activeMonthlySub.value.amount_used ?? 0),
      left: Number(activeMonthlySub.value.amount_left ?? 0),
    }
  }
  return tokenPackTotals.value
})

const requests24h = computed(() => Number(me.value?.stats24h?.request_24h ?? 0))

const refund = computed(() =>
  computeRefund(Number(activeSub.value?.price_amount ?? 0), activeSub.value?.end_time),
)

// Upgrade quotes: every monthly plan priced above the active monthly plan, with the
// unused value of the current plan already deducted. Without an active monthly plan
// the current price is 0, so each plan is quoted at full price.
const currentPlanPrice = computed(() => Number(activeMonthlySub.value?.price_amount ?? 0))

const upgradeOptions = computed(() =>
  plans.value
    .filter(
      (p) => p.quota_reset_period === 'daily' && Number(p.price_amount ?? 0) > currentPlanPrice.value,
    )
    .sort((a, b) => Number(a.price_amount ?? 0) - Number(b.price_amount ?? 0))
    .map((plan) => ({
      plan,
      ...computeUpgradeCost(
        Number(plan.price_amount ?? 0),
        currentPlanPrice.value,
        activeMonthlySub.value?.end_time,
      ),
    })),
)

// Requests grouped by hour bucket (0-23) over the last 24h.
const hourlyBuckets = computed(() => {
  const buckets = new Array(24).fill(0)
  for (const row of logs.value) {
    const created = row.created_at ? new Date(String(row.created_at)) : null
    if (!created || Number.isNaN(created.getTime())) continue
    buckets[created.getHours()] += 1
  }
  return buckets
})

const maxHourly = computed(() => Math.max(1, ...hourlyBuckets.value))

// Top models aggregated from 24h logs.
const topModels = computed(() => {
  const map = new Map<string, { count: number; quota: number }>()
  for (const row of logs.value) {
    const name = String(row.model_name ?? '—')
    const entry = map.get(name) ?? { count: 0, quota: 0 }
    entry.count += 1
    entry.quota += Number(row.quota ?? 0)
    map.set(name, entry)
  }
  return [...map.entries()]
    .map(([model, v]) => ({ model, ...v }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 5)
})

const maxModelCount = computed(() => Math.max(1, ...topModels.value.map((m) => m.count)))

function hourLabel(hour: number): string {
  return `${String(hour).padStart(2, '0')}:00`
}

function hourlyTooltip(hour: number, count: number): string {
  return `${hourLabel(hour)} · ${formatNumber(count)} ${t('user.overview.requests')}`
}

function openAiConnectionUrl(config: Awaited<ReturnType<typeof getPortalConfig>> | null): string {
  const baseUrl = config?.newApiPublicBaseUrl || config?.openAiBaseUrl || config?.newApiBaseUrl || ''
  const normalized = baseUrl.trim().replace(/\/+$/, '')
  return normalized ? (normalized.endsWith('/v1') ? normalized : `${normalized}/v1`) : ''
}

let loadingRequest = false
let refreshTimer: number | undefined

async function load(showSkeleton = true) {
  if (loadingRequest) return
  loadingRequest = true
  if (showSkeleton) loading.value = true
  try {
    const [meRes, configRes, logsRes, plansRes] = await Promise.all([
      getDashboardMe(userApiKey.value),
      getPortalConfig().catch(() => null),
      getDashboardLogs(userApiKey.value, { page: 1, size: 1000 }).catch(() => null),
      getPublicPlans().catch(() => null),
    ])
    me.value = meRes
    connectionUrl.value = openAiConnectionUrl(configRes)
    logs.value = logsRes?.items ?? []
    plans.value = plansRes ?? []
  } catch (err) {
    const msg = err instanceof ApiError ? err.message : String(err)
    toast.error(t('common.error'), { description: msg })
  } finally {
    loading.value = false
    loadingRequest = false
  }
}

async function copy(text: string) {
  if (!text) return
  try {
    await navigator.clipboard.writeText(text)
    toast.success(t('common.copied'))
  } catch {
    toast.error(t('common.error'))
  }
}

onMounted(() => {
  void load(true)
  refreshTimer = window.setInterval(() => void load(false), 10_000)
})

onBeforeUnmount(() => {
  if (refreshTimer) window.clearInterval(refreshTimer)
})
</script>

<template>
  <div class="flex flex-col gap-4 md:gap-6">
    <!-- Stat cards -->
    <div class="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
      <!-- Current plan -->
      <Card>
        <CardHeader>
          <CardDescription class="flex items-center gap-2">
            <IconPackage class="size-4" /> {{ t('user.overview.currentPlan') }}
          </CardDescription>
          <CardTitle class="text-2xl">
            <template v-if="loading"><Skeleton class="h-7 w-32" /></template>
            <template v-else>{{ displayedPlanTitle ?? t('user.overview.noPlan') }}</template>
          </CardTitle>
        </CardHeader>
        <CardContent>
          <Badge v-if="activeSub" variant="secondary">
            {{ activeSub.status === 'active' ? t('common.active') : t('common.inactive') }}
          </Badge>
          <div v-if="activeMonthlySub && hasPaygWallet" class="mt-2 text-xs text-muted-foreground">
            + {{ formatCredit(tokenPackTotals.left) }} {{ t('user.overview.paygWallet') }}
          </div>
        </CardContent>
      </Card>

      <!-- Remaining credit today -->
      <Card>
        <CardHeader>
          <CardDescription class="flex items-center gap-2">
            <IconCoin class="size-4" />
            {{ isPaygOnly ? t('user.overview.paygWallet') : t('user.overview.tokenCreditToday') }}
          </CardDescription>
          <CardTitle class="text-2xl tabular-nums">
            <template v-if="loading"><Skeleton class="h-7 w-24" /></template>
            <template v-else>{{ activeSub ? formatCredit(displayedCredit.left) : '—' }}</template>
          </CardTitle>
        </CardHeader>
        <CardContent class="text-sm text-muted-foreground">
          <template v-if="activeSub">
            <span v-if="isPaygOnly">{{ t('user.overview.paygNoExpiry') }}</span>
            <template v-else>
              {{ formatCredit(displayedCredit.used) }} {{ t('user.overview.quotaUsed') }}
            </template>
          </template>
        </CardContent>
      </Card>

      <!-- Connection URL -->
      <Card>
        <CardHeader>
          <CardDescription class="flex items-center gap-2">
            <IconLink class="size-4" /> {{ t('user.overview.connectionUrl') }}
          </CardDescription>
          <CardTitle class="truncate text-base font-mono">
            <template v-if="loading"><Skeleton class="h-6 w-40" /></template>
            <template v-else>{{ connectionUrl || '—' }}</template>
          </CardTitle>
        </CardHeader>
        <CardContent class="flex flex-wrap gap-2">
          <Button variant="outline" size="sm" :disabled="!connectionUrl" @click="copy(connectionUrl)">
            <IconCopy class="size-4" /> {{ t('common.copy') }}
          </Button>
          <Button variant="outline" size="sm" :disabled="!userApiKey" @click="copy(userApiKey)">
            <IconCopy class="size-4" /> {{ t('user.overview.copyApiKey') }}
          </Button>
        </CardContent>
      </Card>

      <!-- Refund -->
      <Card>
        <CardHeader>
          <CardDescription class="flex items-center gap-2">
            <IconRefresh class="size-4" /> {{ t('user.overview.refund') }}
          </CardDescription>
          <CardTitle class="text-2xl tabular-nums">
            <template v-if="loading"><Skeleton class="h-7 w-28" /></template>
            <template v-else>{{ formatVnd(refund.refund) }}</template>
          </CardTitle>
        </CardHeader>
        <CardContent class="text-sm text-muted-foreground">
          <div>{{ refund.daysLeft }} {{ t('user.overview.daysLeft') }}</div>
          <div>{{ t('user.overview.expireAt') }}: {{ formatDate(activeSub?.end_time) }}</div>
          <div class="text-xs">{{ t('user.overview.refundHint') }}</div>
        </CardContent>
      </Card>
    </div>

    <!-- Upgrade cost -->
    <Card>
      <CardHeader>
        <CardDescription class="flex items-center gap-2">
          <IconTrendingUp class="size-4" /> {{ t('user.overview.upgrade') }}
        </CardDescription>
        <CardTitle class="text-sm font-normal text-muted-foreground">
          {{ activeMonthlySub ? t('user.overview.upgradeHint') : t('user.overview.upgradeNoPlan') }}
        </CardTitle>
      </CardHeader>
      <CardContent>
        <div v-if="loading" class="flex flex-col gap-2">
          <Skeleton v-for="i in 3" :key="i" class="h-10 w-full" />
        </div>
        <div v-else-if="!upgradeOptions.length" class="py-2 text-sm text-muted-foreground">
          {{ t('user.overview.upgradeNone') }}
        </div>
        <template v-else>
          <ul class="flex flex-col divide-y">
            <li
              v-for="option in upgradeOptions"
              :key="option.plan.id"
              class="flex flex-wrap items-center justify-between gap-2 py-2"
            >
              <div class="flex flex-col">
                <span class="font-medium">{{ option.plan.title }}</span>
                <span class="text-xs tabular-nums text-muted-foreground">
                  {{ formatCredit(option.plan.total_amount) }} {{ t('user.plans.creditPerDay') }}
                </span>
              </div>
              <div class="flex flex-col items-end">
                <span class="text-lg font-semibold tabular-nums">+{{ formatVnd(option.cost) }}</span>
                <span v-if="option.credit > 0" class="text-xs tabular-nums text-muted-foreground">
                  {{ t('user.overview.upgradeCredited', { amount: formatVnd(option.credit) }) }}
                </span>
              </div>
            </li>
          </ul>
          <p class="mt-3 text-xs text-muted-foreground">{{ t('user.overview.upgradeContact') }}</p>
        </template>
      </CardContent>
    </Card>

    <!-- Requests 24h + Top models -->
    <div class="grid grid-cols-1 gap-4 md:gap-6 lg:grid-cols-3">
      <Card class="lg:col-span-2">
        <CardHeader>
          <CardDescription class="flex items-center gap-2">
            <IconActivity class="size-4" /> {{ t('user.overview.requestsByHour') }}
          </CardDescription>
          <CardTitle class="text-3xl tabular-nums">
            <template v-if="loading"><Skeleton class="h-8 w-20" /></template>
            <template v-else>{{ formatNumber(requests24h) }}</template>
            <span class="ml-2 text-sm font-normal text-muted-foreground">
              {{ t('user.overview.requests24h') }}
            </span>
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div v-if="loading" class="flex h-40 items-end gap-1">
            <Skeleton v-for="i in 24" :key="i" class="flex-1" :style="{ height: `${20 + (i % 6) * 12}%` }" />
          </div>
          <TooltipProvider v-else :delay-duration="0">
            <div class="flex h-40 items-end gap-1">
              <Tooltip v-for="(count, hour) in hourlyBuckets" :key="hour">
                <TooltipTrigger as-child>
                  <div
                    class="flex-1 rounded-t bg-primary/70 outline-none transition-colors hover:bg-primary focus-visible:ring-2 focus-visible:ring-ring"
                    :style="{ height: `${Math.max(2, (count / maxHourly) * 100)}%` }"
                    :aria-label="hourlyTooltip(hour, count)"
                    tabindex="0"
                  />
                </TooltipTrigger>
                <TooltipContent side="top" class="text-xs">
                  <div class="font-medium">{{ hourLabel(hour) }}</div>
                  <div class="tabular-nums">{{ formatNumber(count) }} {{ t('user.overview.requests') }}</div>
                </TooltipContent>
              </Tooltip>
            </div>
          </TooltipProvider>
          <div class="mt-2 flex justify-between text-xs text-muted-foreground">
            <span>0h</span><span>6h</span><span>12h</span><span>18h</span><span>23h</span>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardDescription class="flex items-center gap-2">
            <IconTrophy class="size-4" /> {{ t('user.overview.topModels') }}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div v-if="loading" class="flex flex-col gap-3">
            <Skeleton v-for="i in 5" :key="i" class="h-8 w-full" />
          </div>
          <div v-else-if="!topModels.length" class="py-6 text-center text-sm text-muted-foreground">
            {{ t('user.overview.noModelUsage') }}
          </div>
          <ul v-else class="flex flex-col gap-3">
            <li v-for="m in topModels" :key="m.model" class="flex flex-col gap-1">
              <div class="flex items-center justify-between gap-3 text-sm">
                <span class="truncate font-medium">{{ m.model }}</span>
                <span class="whitespace-nowrap tabular-nums text-muted-foreground">
                  {{ formatNumber(m.count) }} {{ t('user.overview.requests') }}
                  <span class="mx-1">·</span>
                  {{ formatCredit(m.quota) }} {{ t('user.logs.creditLabel') }}
                </span>
              </div>
              <div class="h-2 w-full overflow-hidden rounded-full bg-muted">
                <div
                  class="h-full rounded-full bg-primary"
                  :style="{ width: `${(m.count / maxModelCount) * 100}%` }"
                />
              </div>
            </li>
          </ul>
        </CardContent>
      </Card>
    </div>
  </div>
</template>
