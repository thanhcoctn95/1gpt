<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { toast } from 'vue-sonner'
import { IconCheck, IconInfinity } from '@tabler/icons-vue'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Skeleton } from '@/components/ui/skeleton'
import { useAuth } from '@/composables/useAuth'
import { ApiError, getAdminPlans, type AdminPlanRow } from '@/services/api'
import { formatVnd, formatCredit } from '@/lib/format'

const { t } = useI18n()
const { adminToken } = useAuth()

const loading = ref(true)
const plans = ref<AdminPlanRow[]>([])

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

async function load() {
  loading.value = true
  try {
    plans.value = await getAdminPlans(adminToken.value)
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
