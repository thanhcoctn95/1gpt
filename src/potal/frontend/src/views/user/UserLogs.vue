<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { toast } from 'vue-sonner'
import { IconChevronLeft, IconChevronRight, IconRefresh, IconSearch } from '@tabler/icons-vue'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Skeleton } from '@/components/ui/skeleton'
import {
  Table,
  TableBody,
  TableCell,
  TableEmpty,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { useAuth } from '@/composables/useAuth'
import {
  getDashboardLogs,
  getDashboardLogModelStats,
  getDashboardLogStatusStats,
  ApiError,
  type DashboardLogParams,
  type LogModelStatRow,
  type LogStatusStat,
  type LogRow,
} from '@/services/api'
import { formatDateTime, formatNumber, formatCredit, isErrorLog, todayISODate } from '@/lib/format'

const { t } = useI18n()
const { userApiKey } = useAuth()

const loading = ref(true)
const items = ref<LogRow[]>([])
const modelStats = ref<LogModelStatRow[]>([])
const statusStats = ref<LogStatusStat | null>(null)
const page = ref(1)
const size = ref(20)
const total = ref(0)
const modelFilter = ref('')
const statusFilter = ref<'all' | 'success' | 'error'>('all')
const fromDate = ref(todayISODate())
const toDate = ref(todayISODate())

const totalPages = computed(() => Math.max(1, Math.ceil(total.value / size.value)))
const modelChartRows = computed(() =>
  modelStats.value.map((row) => ({
    model: String(row.model_name || '—'),
    count: Number(row.request_count ?? 0),
    tokens: Number(row.tokens_total ?? 0),
  })),
)
const maxModelRequests = computed(() => Math.max(1, ...modelChartRows.value.map((row) => row.count)))

const statusBreakdown = computed(() => {
  const success = Number(statusStats.value?.success_count ?? 0)
  const error = Number(statusStats.value?.error_count ?? 0)
  const total = Number(statusStats.value?.total ?? success + error)
  const denom = total > 0 ? total : 1
  const successPct = (success / denom) * 100
  const errorPct = (error / denom) * 100
  return {
    success,
    error,
    total,
    successPct,
    errorPct,
    // Conic gradient stop for the donut: green up to successPct, red after.
    gradient: `conic-gradient(rgb(34 197 94) 0% ${successPct}%, rgb(239 68 68) ${successPct}% 100%)`,
  }
})

function dateToUnixSeconds(value: string, endOfDay: boolean): number | undefined {
  if (!value) return undefined
  const suffix = endOfDay ? 'T23:59:59' : 'T00:00:00'
  const time = new Date(`${value}${suffix}`).getTime()
  return Number.isNaN(time) ? undefined : Math.floor(time / 1000)
}

function buildParams(): DashboardLogParams {
  return {
    page: page.value,
    size: size.value,
    modelName: modelFilter.value.trim() || undefined,
    status: statusFilter.value === 'all' ? '' : statusFilter.value,
    startTime: dateToUnixSeconds(fromDate.value, false),
    endTime: dateToUnixSeconds(toDate.value, true),
  }
}

let loadingRequest = false
let refreshTimer: number | undefined

async function load(showSkeleton = true) {
  if (loadingRequest) return
  loadingRequest = true
  if (showSkeleton) loading.value = true
  try {
    const params = buildParams()
    const [logsRes, statsRes, statusRes] = await Promise.all([
      getDashboardLogs(userApiKey.value, params),
      getDashboardLogModelStats(userApiKey.value, params),
      getDashboardLogStatusStats(userApiKey.value, {
        modelName: params.modelName,
        startTime: params.startTime,
        endTime: params.endTime,
      }),
    ])
    items.value = logsRes.items
    total.value = logsRes.total
    page.value = logsRes.page || page.value
    size.value = logsRes.size || size.value
    modelStats.value = statsRes
    statusStats.value = statusRes
  } catch (err) {
    const msg = err instanceof ApiError ? err.message : String(err)
    toast.error(t('common.error'), { description: msg })
  } finally {
    loading.value = false
    loadingRequest = false
  }
}

function applyFilters() {
  page.value = 1
  load()
}

function resetFilters() {
  modelFilter.value = ''
  statusFilter.value = 'all'
  fromDate.value = todayISODate()
  toDate.value = todayISODate()
  page.value = 1
  load()
}

function go(delta: number) {
  const next = page.value + delta
  if (next < 1 || next > totalPages.value) return
  page.value = next
  load()
}

function responseTime(value: unknown) {
  const n = Number(value ?? 0)
  if (!Number.isFinite(n) || n <= 0) return '—'
  const seconds = n > 1000 ? n / 1000 : n
  return seconds >= 10 ? `${seconds.toFixed(0)}s` : `${seconds.toFixed(2)}s`
}

function rowIsError(row: LogRow) {
  if (row.request_status) return row.request_status === 'error'
  return isErrorLog(row)
}

function errorDetail(row: LogRow): string {
  const label = row.error_message || row.error_type || row.error_code
  const parts = [row.status_code, label].filter(Boolean)
  return parts.length > 0 ? parts.join(' · ') : '—'
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
  <div class="flex flex-col gap-6">
    <Card>
      <CardHeader>
        <CardTitle class="text-base">{{ t('common.search') }}</CardTitle>
        <CardDescription>{{ t('user.logs.filterHint') }}</CardDescription>
      </CardHeader>
      <CardContent>
        <form class="grid gap-4 md:grid-cols-2 xl:grid-cols-5" @submit.prevent="applyFilters">
          <Input v-model="modelFilter" :placeholder="t('user.logs.filterModel')" />
          <Select v-model="statusFilter">
            <SelectTrigger class="w-full">
              <SelectValue :placeholder="t('user.logs.filterStatus')" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">{{ t('user.logs.statusAll') }}</SelectItem>
              <SelectItem value="success">{{ t('user.logs.statusSuccess') }}</SelectItem>
              <SelectItem value="error">{{ t('user.logs.statusError') }}</SelectItem>
            </SelectContent>
          </Select>
          <Input v-model="fromDate" type="date" :aria-label="t('common.from')" />
          <Input v-model="toDate" type="date" :aria-label="t('common.to')" />
          <div class="flex gap-2">
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

    <Card>
      <CardHeader>
        <CardTitle class="text-base">{{ t('user.logs.statsTitle') }}</CardTitle>
        <CardDescription>{{ t('user.logs.statsHint') }}</CardDescription>
      </CardHeader>
      <CardContent>
        <div class="grid gap-8 lg:grid-cols-2">
          <!-- Success / error rate -->
          <div class="flex flex-col gap-3">
            <h3 class="text-sm font-medium">{{ t('user.logs.statusChart') }}</h3>
            <div v-if="loading" class="flex items-center gap-6">
              <Skeleton class="size-32 rounded-full" />
              <div class="flex flex-1 flex-col gap-3">
                <Skeleton class="h-6 w-full" />
                <Skeleton class="h-6 w-full" />
              </div>
            </div>
            <div v-else-if="!statusBreakdown.total" class="py-6 text-center text-sm text-muted-foreground">
              {{ t('common.noData') }}
            </div>
            <div v-else class="flex flex-col items-center gap-6 sm:flex-row sm:gap-8">
              <div
                class="relative size-32 shrink-0 rounded-full"
                :style="{ background: statusBreakdown.gradient }"
                role="img"
                :aria-label="`${t('user.logs.statusSuccess')} ${statusBreakdown.successPct.toFixed(1)}%, ${t('user.logs.statusError')} ${statusBreakdown.errorPct.toFixed(1)}%`"
              >
                <div class="absolute inset-[22%] flex flex-col items-center justify-center rounded-full bg-background">
                  <span class="text-lg font-semibold tabular-nums">{{ statusBreakdown.successPct.toFixed(0) }}%</span>
                  <span class="text-xs text-muted-foreground">{{ t('user.logs.statusSuccess') }}</span>
                </div>
              </div>
              <ul class="flex flex-1 flex-col gap-3 text-sm">
                <li class="flex items-center justify-between gap-3">
                  <span class="flex items-center gap-2">
                    <span class="size-3 rounded-full" style="background: rgb(34 197 94)" />
                    {{ t('user.logs.statusSuccess') }}
                  </span>
                  <span class="tabular-nums text-muted-foreground">
                    {{ formatNumber(statusBreakdown.success) }} ({{ statusBreakdown.successPct.toFixed(1) }}%)
                  </span>
                </li>
                <li class="flex items-center justify-between gap-3">
                  <span class="flex items-center gap-2">
                    <span class="size-3 rounded-full" style="background: rgb(239 68 68)" />
                    {{ t('user.logs.statusError') }}
                  </span>
                  <span class="tabular-nums text-muted-foreground">
                    {{ formatNumber(statusBreakdown.error) }} ({{ statusBreakdown.errorPct.toFixed(1) }}%)
                  </span>
                </li>
                <li class="flex items-center justify-between gap-3 border-t pt-2">
                  <span class="font-medium">{{ t('common.total') }}</span>
                  <span class="tabular-nums">{{ formatNumber(statusBreakdown.total) }}</span>
                </li>
              </ul>
            </div>
          </div>

          <!-- Requests / tokens by model -->
          <div class="flex flex-col gap-3">
            <h3 class="text-sm font-medium">{{ t('user.logs.modelRequests') }}</h3>
            <div v-if="loading" class="flex flex-col gap-3">
              <Skeleton v-for="i in 5" :key="i" class="h-8 w-full" />
            </div>
            <div v-else-if="!modelChartRows.length" class="py-6 text-center text-sm text-muted-foreground">
              {{ t('common.noData') }}
            </div>
            <ul v-else class="flex flex-col gap-3">
              <li v-for="row in modelChartRows" :key="row.model" class="grid gap-1">
                <div class="flex items-center justify-between gap-3 text-sm">
                  <span class="truncate font-medium">{{ row.model }}</span>
                  <span class="tabular-nums text-muted-foreground">
                    {{ formatNumber(row.count) }} {{ t('user.overview.requests') }}
                    <span class="mx-1">·</span>
                    {{ formatNumber(row.tokens) }} {{ t('user.logs.tokensLabel') }}
                  </span>
                </div>
                <div class="h-2.5 w-full overflow-hidden rounded-full bg-muted">
                  <div
                    class="h-full rounded-full bg-primary"
                    :style="{ width: `${Math.max(4, (row.count / maxModelRequests) * 100)}%` }"
                  />
                </div>
              </li>
            </ul>
          </div>
        </div>
      </CardContent>
    </Card>

    <Card>
      <CardHeader>
        <CardTitle class="text-base">{{ t('user.logs.title') }}</CardTitle>
        <CardDescription>{{ t('common.total') }}: {{ formatNumber(total) }}</CardDescription>
      </CardHeader>
      <CardContent>
        <div v-if="loading" class="flex flex-col gap-2">
          <Skeleton v-for="i in 8" :key="i" class="h-10 w-full" />
        </div>
        <template v-else>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{{ t('user.logs.time') }}</TableHead>
                <TableHead>{{ t('user.logs.model') }}</TableHead>
                <TableHead class="text-right">{{ t('user.logs.tokensIn') }}</TableHead>
                <TableHead class="text-right">{{ t('user.logs.tokensOut') }}</TableHead>
                <TableHead class="text-right">{{ t('user.logs.convertedTokens') }}</TableHead>
                <TableHead class="text-right">{{ t('user.logs.cost') }}</TableHead>
                <TableHead class="text-right">{{ t('user.logs.responseTime') }}</TableHead>
                <TableHead>{{ t('user.logs.channel') }}</TableHead>
                <TableHead>{{ t('common.status') }}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              <TableEmpty v-if="!items.length" :colspan="9">{{ t('common.noData') }}</TableEmpty>
              <TableRow v-for="row in items" :key="String(row.id)">
                <TableCell class="whitespace-nowrap text-muted-foreground">
                  {{ formatDateTime(row.created_at) }}
                </TableCell>
                <TableCell class="font-medium">{{ row.model_name || '—' }}</TableCell>
                <TableCell class="text-right tabular-nums">{{ formatNumber(row.prompt_tokens) }}</TableCell>
                <TableCell class="text-right tabular-nums">{{ formatNumber(row.completion_tokens) }}</TableCell>
                <TableCell class="text-right tabular-nums">{{ formatNumber(row.quota) }}</TableCell>
                <TableCell class="text-right tabular-nums">{{ formatCredit(row.quota) }}</TableCell>
                <TableCell class="text-right tabular-nums">{{ responseTime(row.use_time) }}</TableCell>
                <TableCell class="text-muted-foreground">{{ row.channel_name || '—' }}</TableCell>
                <TableCell>
                  <div class="flex min-w-64 max-w-md flex-col gap-1">
                    <Badge class="w-fit" :variant="rowIsError(row) ? 'destructive' : 'secondary'">
                      {{ rowIsError(row) ? t('common.error') : t('common.success') }}
                    </Badge>
                    <span v-if="rowIsError(row)" class="select-text whitespace-pre-wrap break-words text-xs text-muted-foreground">
                      {{ errorDetail(row) }}
                    </span>
                  </div>
                </TableCell>
              </TableRow>
            </TableBody>
          </Table>

          <div class="mt-4 flex items-center justify-between text-sm text-muted-foreground">
            <span>{{ t('common.total') }}: {{ formatNumber(total) }}</span>
            <div class="flex items-center gap-2">
              <span>{{ t('common.page') }} {{ page }} / {{ totalPages }}</span>
              <Button variant="outline" size="icon" class="size-8" :disabled="page <= 1" @click="go(-1)">
                <IconChevronLeft class="size-4" />
              </Button>
              <Button
                variant="outline"
                size="icon"
                class="size-8"
                :disabled="page >= totalPages"
                @click="go(1)"
              >
                <IconChevronRight class="size-4" />
              </Button>
            </div>
          </div>
        </template>
      </CardContent>
    </Card>
  </div>
</template>
