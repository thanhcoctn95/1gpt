<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { toast } from 'vue-sonner'
import { IconCheck, IconChevronDown, IconInfinity } from '@tabler/icons-vue'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { useAuth } from '@/composables/useAuth'
import { ApiError, getAdminPlans, getModelRatios, type AdminPlanRow, type ModelRatioRow } from '@/services/api'
import { formatVnd, formatCredit, quotaToCredit } from '@/lib/format'

const { t, locale } = useI18n()
const { adminToken } = useAuth()

const loading = ref(true)
const plans = ref<AdminPlanRow[]>([])
const modelRatios = ref<ModelRatioRow[]>([])
const expandedPlans = ref<number[]>([])

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

function modelLabel(plan: AdminPlanRow): string {
  const list = typeof plan.model_list === 'string' ? plan.model_list.trim() : ''
  if (!list) return t('admin.plans.fullModels')
  const count = list.split(',').filter((s) => s.trim()).length
  return count > 0 ? t('admin.plans.limitedModels', { count }) : t('admin.plans.fullModels')
}

function formatMillionTokens(value: number): string {
  return new Intl.NumberFormat(locale.value === 'vi' ? 'vi-VN' : 'en-US', { maximumFractionDigits: 1 }).format(value)
}

function modelTokenEquivalents(plan: AdminPlanRow): string[] {
  const credits = quotaToCredit(Number(plan.total_amount ?? 0))
  return modelRatios.value
    .filter(({ model_ratio }) => Number(model_ratio) > 0)
    .map(({ model_name, model_ratio }) =>
      `${model_name}: ${formatMillionTokens(credits / Number(model_ratio))}M token`,
    )
}

function isExpanded(planId: number): boolean {
  return expandedPlans.value.includes(planId)
}

function toggleConversion(planId: number) {
  expandedPlans.value = isExpanded(planId)
    ? expandedPlans.value.filter((id) => id !== planId)
    : [...expandedPlans.value, planId]
}

async function load() {
  loading.value = true
  try {
    const [planRows, ratioResponse] = await Promise.all([
      getAdminPlans(adminToken.value),
      getModelRatios(adminToken.value),
    ])
    plans.value = planRows
    modelRatios.value = ratioResponse.models
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
      <h1 class="text-xl font-semibold tracking-tight sm:text-2xl">{{ t('admin.plans.title') }}</h1>
      <p class="text-sm text-muted-foreground">{{ t('admin.plans.hint') }}</p>
    </div>

    <!-- Monthly plans -->
    <div class="flex flex-col gap-3">
      <h2 class="text-base font-semibold">{{ t('admin.plans.monthlyTitle') }}</h2>
      <div v-if="loading" class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Skeleton v-for="i in 4" :key="i" class="h-48 w-full" />
      </div>
      <div v-else-if="!monthlyPlans.length" class="py-6 text-center text-sm text-muted-foreground">
        {{ t('admin.plans.empty') }}
      </div>
      <div v-else class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Card v-for="plan in monthlyPlans" :key="plan.id" class="flex flex-col">
          <CardHeader>
            <CardTitle class="text-lg">{{ plan.title }}</CardTitle>
            <CardDescription>
              <span class="text-2xl font-semibold text-foreground tabular-nums">
                {{ formatVnd(plan.price_amount) }}
              </span>
            </CardDescription>
          </CardHeader>
          <CardContent class="flex flex-1 flex-col gap-3">
            <p class="text-lg font-medium tabular-nums">
              {{ formatCredit(plan.total_amount) }} {{ t('admin.plans.creditPerDayLabel') }}
            </p>
            <p v-if="plan.subtitle" class="text-sm text-muted-foreground">{{ plan.subtitle }}</p>
            <Button variant="outline" size="sm" class="w-fit" @click="toggleConversion(plan.id)">
              {{ t('admin.plans.convert') }}
              <IconChevronDown class="size-4 transition-transform" :class="{ 'rotate-180': isExpanded(plan.id) }" />
            </Button>
            <div v-if="isExpanded(plan.id)" class="rounded-md border bg-muted/40 p-3">
              <p class="mb-2 text-xs font-medium text-foreground">{{ t('admin.plans.inputTokenEquivalent') }}</p>
              <ul class="grid max-h-52 gap-1 overflow-y-auto text-xs text-muted-foreground">
                <li v-for="item in modelTokenEquivalents(plan)" :key="item" class="tabular-nums">{{ item }}</li>
              </ul>
            </div>
            <ul class="flex flex-col gap-2 text-sm text-muted-foreground">
              <li class="flex items-start gap-2">
                <IconCheck class="mt-0.5 size-4 shrink-0 text-primary" /> {{ modelLabel(plan) }}
              </li>
            </ul>
            <Badge v-if="plan.upgrade_group" variant="secondary" class="mt-auto w-fit">
              {{ t('admin.plans.upgradeGroup') }}: {{ plan.upgrade_group }}
            </Badge>
          </CardContent>
        </Card>
      </div>
    </div>

    <!-- One-time credit packs -->
    <div v-if="loading || onetimePlans.length" class="flex flex-col gap-3">
      <h2 class="text-base font-semibold">{{ t('admin.plans.onetimeTitle') }}</h2>
      <div v-if="loading" class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Skeleton v-for="i in 4" :key="i" class="h-44 w-full" />
      </div>
      <div v-else class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Card v-for="plan in onetimePlans" :key="plan.id" class="flex flex-col">
          <CardHeader>
            <CardTitle class="text-lg">{{ plan.title }}</CardTitle>
            <CardDescription>
              <span class="text-2xl font-semibold text-foreground tabular-nums">
                {{ formatVnd(plan.price_amount) }}
              </span>
            </CardDescription>
          </CardHeader>
          <CardContent class="flex flex-1 flex-col gap-3">
            <p class="text-lg font-medium tabular-nums">
              {{ formatCredit(plan.total_amount) }} {{ t('admin.plans.creditLabel') }}
            </p>
            <p v-if="plan.subtitle" class="text-sm text-muted-foreground">{{ plan.subtitle }}</p>
            <Button variant="outline" size="sm" class="w-fit" @click="toggleConversion(plan.id)">
              {{ t('admin.plans.convert') }}
              <IconChevronDown class="size-4 transition-transform" :class="{ 'rotate-180': isExpanded(plan.id) }" />
            </Button>
            <div v-if="isExpanded(plan.id)" class="rounded-md border bg-muted/40 p-3">
              <p class="mb-2 text-xs font-medium text-foreground">{{ t('admin.plans.inputTokenEquivalent') }}</p>
              <ul class="grid max-h-52 gap-1 overflow-y-auto text-xs text-muted-foreground">
                <li v-for="item in modelTokenEquivalents(plan)" :key="item" class="tabular-nums">{{ item }}</li>
              </ul>
            </div>
            <ul class="flex flex-col gap-2 text-sm text-muted-foreground">
              <li class="flex items-start gap-2">
                <IconCheck class="mt-0.5 size-4 shrink-0 text-primary" /> {{ modelLabel(plan) }}
              </li>
              <li class="flex items-start gap-2">
                <IconInfinity class="mt-0.5 size-4 shrink-0 text-primary" /> {{ t('admin.plans.never') }}
              </li>
            </ul>
          </CardContent>
        </Card>
      </div>
    </div>
  </div>
</template>
