<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
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
import { getDashboardLogs, ApiError, type DashboardLogParams, type LogRow } from '@/services/api'
import { formatDateTime, formatNumber, isErrorLog } from '@/lib/format'

const { t } = useI18n()
const { userApiKey } = useAuth()

const loading = ref(true)
const items = ref<LogRow[]>([])
const page = ref(1)
const size = ref(20)
const total = ref(0)
const modelFilter = ref('')
const statusFilter = ref<'all' | 'success' | 'error'>('all')
const fromDate = ref('')
const toDate = ref('')

const totalPages = computed(() => Math.max(1, Math.ceil(total.value / size.value)))

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

async function load() {
  loading.value = true
  try {
    const res = await getDashboardLogs(userApiKey.value, buildParams())
    items.value = res.items
    total.value = res.total
    page.value = res.page || page.value
    size.value = res.size || size.value
  } catch (err) {
    const msg = err instanceof ApiError ? err.message : String(err)
    toast.error(t('common.error'), { description: msg })
  } finally {
    loading.value = false
  }
}

function applyFilters() {
  page.value = 1
  load()
}

function resetFilters() {
  modelFilter.value = ''
  statusFilter.value = 'all'
  fromDate.value = ''
  toDate.value = ''
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

onMounted(load)
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
                <TableHead class="text-right">{{ t('user.logs.responseTime') }}</TableHead>
                <TableHead>{{ t('user.logs.channel') }}</TableHead>
                <TableHead>{{ t('common.status') }}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              <TableEmpty v-if="!items.length" :colspan="7">{{ t('common.noData') }}</TableEmpty>
              <TableRow v-for="row in items" :key="String(row.id)">
                <TableCell class="whitespace-nowrap text-muted-foreground">
                  {{ formatDateTime(row.created_at) }}
                </TableCell>
                <TableCell class="font-medium">{{ row.model_name || '—' }}</TableCell>
                <TableCell class="text-right tabular-nums">{{ formatNumber(row.prompt_tokens) }}</TableCell>
                <TableCell class="text-right tabular-nums">{{ formatNumber(row.completion_tokens) }}</TableCell>
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
