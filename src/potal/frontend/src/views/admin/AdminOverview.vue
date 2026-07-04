<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { toast } from 'vue-sonner'
import { IconAlertTriangle, IconBug, IconCoins, IconDatabase, IconRefresh, IconSearch, IconUsers } from '@tabler/icons-vue'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TableBody, TableCell, TableEmpty, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { useAuth } from '@/composables/useAuth'
import { formatNumber, formatTokens } from '@/lib/format'
import { ApiError, getAdminLogsStats } from '@/services/api'
import type { AdminLogStatsResponse } from '@/services/api'

const { t } = useI18n()
const { adminToken } = useAuth()

function todayIso(): string {
  const now = new Date()
  const y = now.getFullYear()
  const m = String(now.getMonth() + 1).padStart(2, '0')
  const d = String(now.getDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

const loading = ref(false)
const stats = ref<AdminLogStatsResponse | null>(null)
const fromDate = ref(todayIso())
const toDate = ref(todayIso())

function dateToUnixSeconds(value: string, endOfDay: boolean): number | undefined {
  if (!value) return undefined
  const suffix = endOfDay ? 'T23:59:59' : 'T00:00:00'
  const time = new Date(`${value}${suffix}`).getTime()
  return Number.isNaN(time) ? undefined : Math.floor(time / 1000)
}

const totals = computed(() => stats.value?.totals)
const totalRequests = computed(() => totals.value?.req_count ?? 0)
const totalErrors = computed(() => totals.value?.error_count ?? 0)
const errorRate = computed(() => {
  if (!totalRequests.value) return '0%'
  return `${((totalErrors.value / totalRequests.value) * 100).toFixed(1)}%`
})
const topModels = computed(() => stats.value?.byModel.slice(0, 8) ?? [])
const topUsers = computed(() => stats.value?.byUser.slice(0, 8) ?? [])
const errorTypes = computed(() => stats.value?.byErrorType ?? [])
const errorUsers = computed(() =>
  (stats.value?.byUser ?? []).filter((u) => u.error_count > 0).slice(0, 8),
)

function errorTypeShare(count: number): string {
  if (!totalErrors.value) return '0%'
  return `${((count / totalErrors.value) * 100).toFixed(1)}%`
}

function userErrorRate(reqCount: number, errorCount: number): string {
  if (!reqCount) return '0%'
  return `${((errorCount / reqCount) * 100).toFixed(1)}%`
}

function errorTypeLabel(type: string): string {
  return type === 'other' ? t('common.error') : type
}

function errorMessage(err: unknown): string {
  return err instanceof ApiError ? err.message : t('common.error')
}

async function fetchStats() {
  loading.value = true
  try {
    stats.value = await getAdminLogsStats(adminToken.value, {
      startTime: dateToUnixSeconds(fromDate.value, false),
      endTime: dateToUnixSeconds(toDate.value, true),
    })
  } catch (err) {
    toast.error(errorMessage(err))
  } finally {
    loading.value = false
  }
}

function resetFilters() {
  fromDate.value = todayIso()
  toDate.value = todayIso()
  fetchStats()
}

onMounted(fetchStats)
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex flex-col gap-1">
      <h1 class="text-xl font-semibold tracking-tight sm:text-2xl">{{ t('admin.overview.title') }}</h1>
      <p class="text-sm text-muted-foreground">{{ t('admin.overview.requestsByModel') }}</p>
    </div>

    <Card>
      <CardContent class="pt-6">
        <form class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4" @submit.prevent="fetchStats">
          <div class="grid gap-1.5">
            <label class="text-xs text-muted-foreground">{{ t('common.from') }}</label>
            <Input v-model="fromDate" type="date" :aria-label="t('common.from')" />
          </div>
          <div class="grid gap-1.5">
            <label class="text-xs text-muted-foreground">{{ t('common.to') }}</label>
            <Input v-model="toDate" type="date" :aria-label="t('common.to')" />
          </div>
          <div class="flex items-end gap-2 sm:col-span-2 xl:col-span-2">
            <Button type="submit" class="flex-1" :disabled="loading">
              <IconSearch class="size-4" />
              {{ t('common.apply') }}
            </Button>
            <Button type="button" variant="outline" :disabled="loading" @click="resetFilters">
              <IconRefresh class="size-4" />
              {{ t('common.reset') }}
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>

    <div class="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-6">
      <Card>
        <CardHeader class="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardDescription>{{ t('admin.overview.totalRequests') }}</CardDescription>
          <IconDatabase class="size-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <Skeleton v-if="loading" class="h-8 w-28" />
          <div v-else class="text-2xl font-semibold tabular-nums">{{ formatNumber(totalRequests) }}</div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader class="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardDescription>{{ t('admin.overview.totalCost') }}</CardDescription>
          <IconCoins class="size-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <Skeleton v-if="loading" class="h-8 w-24" />
          <div v-else class="text-2xl font-semibold tabular-nums">{{ formatTokens(totals?.total_quota) }}</div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader class="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardDescription>{{ t('admin.overview.totalErrors') }}</CardDescription>
          <IconBug class="size-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <Skeleton v-if="loading" class="h-8 w-20" />
          <div v-else class="text-2xl font-semibold tabular-nums">{{ formatNumber(totalErrors) }}</div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader class="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardDescription>{{ t('admin.overview.errorRate') }}</CardDescription>
          <IconAlertTriangle class="size-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <Skeleton v-if="loading" class="h-8 w-20" />
          <div v-else class="text-2xl font-semibold tabular-nums" :class="totalErrors > 0 ? 'text-destructive' : ''">
            {{ errorRate }}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader class="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardDescription>{{ t('admin.overview.tokensIn') }}</CardDescription>
          <IconUsers class="size-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <Skeleton v-if="loading" class="h-8 w-28" />
          <div v-else class="text-2xl font-semibold tabular-nums">{{ formatNumber(totals?.tokens_in) }}</div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader class="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardDescription>{{ t('admin.overview.tokensOut') }}</CardDescription>
          <IconUsers class="size-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <Skeleton v-if="loading" class="h-8 w-28" />
          <div v-else class="text-2xl font-semibold tabular-nums">{{ formatNumber(totals?.tokens_out) }}</div>
        </CardContent>
      </Card>
    </div>

    <div class="grid grid-cols-1 gap-6 xl:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle>{{ t('admin.overview.errorTypes') }}</CardTitle>
          <CardDescription>{{ t('admin.overview.totalErrors') }}: {{ formatNumber(totalErrors) }}</CardDescription>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{{ t('admin.overview.errorType') }}</TableHead>
                <TableHead class="text-right">{{ t('admin.overview.errorCount') }}</TableHead>
                <TableHead class="text-right">{{ t('admin.overview.errorShare') }}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              <template v-if="loading">
                <TableRow v-for="index in 5" :key="`errtype-skeleton-${index}`">
                  <TableCell><Skeleton class="h-4 w-24" /></TableCell>
                  <TableCell><Skeleton class="ml-auto h-4 w-12" /></TableCell>
                  <TableCell><Skeleton class="ml-auto h-4 w-12" /></TableCell>
                </TableRow>
              </template>
              <TableEmpty v-else-if="errorTypes.length === 0" :colspan="3" class="text-muted-foreground">
                {{ t('admin.overview.noErrors') }}
              </TableEmpty>
              <TableRow v-for="row in errorTypes" v-else :key="row.error_type">
                <TableCell>
                  <Badge variant="destructive">{{ errorTypeLabel(row.error_type) }}</Badge>
                </TableCell>
                <TableCell class="text-right tabular-nums">{{ formatNumber(row.error_count) }}</TableCell>
                <TableCell class="text-right tabular-nums">{{ errorTypeShare(row.error_count) }}</TableCell>
              </TableRow>
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{{ t('admin.overview.topErrorUsers') }}</CardTitle>
          <CardDescription>{{ t('admin.overview.errorRatePerUser') }}</CardDescription>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{{ t('admin.logs.user') }}</TableHead>
                <TableHead class="text-right">{{ t('admin.overview.totalRequests') }}</TableHead>
                <TableHead class="text-right">{{ t('admin.overview.errorCount') }}</TableHead>
                <TableHead class="text-right">{{ t('admin.overview.errorRate') }}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              <template v-if="loading">
                <TableRow v-for="index in 5" :key="`erruser-skeleton-${index}`">
                  <TableCell><Skeleton class="h-4 w-36" /></TableCell>
                  <TableCell><Skeleton class="ml-auto h-4 w-16" /></TableCell>
                  <TableCell><Skeleton class="ml-auto h-4 w-12" /></TableCell>
                  <TableCell><Skeleton class="ml-auto h-4 w-12" /></TableCell>
                </TableRow>
              </template>
              <TableEmpty v-else-if="errorUsers.length === 0" :colspan="4" class="text-muted-foreground">
                {{ t('admin.overview.noErrors') }}
              </TableEmpty>
              <TableRow v-for="user in errorUsers" v-else :key="user.user_id">
                <TableCell class="font-medium">{{ user.username }}</TableCell>
                <TableCell class="text-right tabular-nums">{{ formatNumber(user.req_count) }}</TableCell>
                <TableCell class="text-right">
                  <Badge variant="destructive">{{ formatNumber(user.error_count) }}</Badge>
                </TableCell>
                <TableCell class="text-right tabular-nums">{{ userErrorRate(user.req_count, user.error_count) }}</TableCell>
              </TableRow>
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>

    <div class="grid grid-cols-1 gap-6 xl:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle>{{ t('admin.overview.topModels') }}</CardTitle>
          <CardDescription>{{ t('admin.overview.totalRequests') }}</CardDescription>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{{ t('admin.models.model') }}</TableHead>
                <TableHead class="text-right">{{ t('admin.overview.totalRequests') }}</TableHead>
                <TableHead class="text-right">{{ t('admin.overview.tokensUsed') }}</TableHead>
                <TableHead class="text-right">{{ t('common.error') }}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              <template v-if="loading">
                <TableRow v-for="index in 5" :key="`model-skeleton-${index}`">
                  <TableCell><Skeleton class="h-4 w-40" /></TableCell>
                  <TableCell><Skeleton class="ml-auto h-4 w-16" /></TableCell>
                  <TableCell><Skeleton class="ml-auto h-4 w-16" /></TableCell>
                  <TableCell><Skeleton class="ml-auto h-4 w-12" /></TableCell>
                </TableRow>
              </template>
              <TableEmpty v-else-if="topModels.length === 0" :colspan="4" class="text-muted-foreground">
                {{ t('common.noData') }}
              </TableEmpty>
              <TableRow v-for="model in topModels" v-else :key="model.model">
                <TableCell class="font-medium">{{ model.model }}</TableCell>
                <TableCell class="text-right tabular-nums">{{ formatNumber(model.req_count) }}</TableCell>
                <TableCell class="text-right tabular-nums">{{ formatTokens(model.total_quota) }}</TableCell>
                <TableCell class="text-right">
                  <Badge :variant="model.error_count > 0 ? 'destructive' : 'secondary'">
                    {{ formatNumber(model.error_count) }}
                  </Badge>
                </TableCell>
              </TableRow>
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{{ t('admin.overview.topUsers') }}</CardTitle>
          <CardDescription>{{ t('admin.overview.tokensUsed') }}</CardDescription>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{{ t('admin.logs.user') }}</TableHead>
                <TableHead class="text-right">{{ t('admin.overview.totalRequests') }}</TableHead>
                <TableHead class="text-right">{{ t('admin.overview.tokensUsed') }}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              <template v-if="loading">
                <TableRow v-for="index in 5" :key="`user-skeleton-${index}`">
                  <TableCell><Skeleton class="h-4 w-36" /></TableCell>
                  <TableCell><Skeleton class="ml-auto h-4 w-16" /></TableCell>
                  <TableCell><Skeleton class="ml-auto h-4 w-16" /></TableCell>
                </TableRow>
              </template>
              <TableEmpty v-else-if="topUsers.length === 0" :colspan="3" class="text-muted-foreground">
                {{ t('common.noData') }}
              </TableEmpty>
              <TableRow v-for="user in topUsers" v-else :key="user.user_id">
                <TableCell class="font-medium">{{ user.username }}</TableCell>
                <TableCell class="text-right tabular-nums">{{ formatNumber(user.req_count) }}</TableCell>
                <TableCell class="text-right tabular-nums">{{ formatTokens(user.total_quota) }}</TableCell>
              </TableRow>
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  </div>
</template>
