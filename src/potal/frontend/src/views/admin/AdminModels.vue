<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { toast } from 'vue-sonner'
import { IconPlayerPause, IconPlayerPlay, IconRefresh } from '@tabler/icons-vue'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Checkbox } from '@/components/ui/checkbox'
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TableBody, TableCell, TableEmpty, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { useAuth } from '@/composables/useAuth'
import { formatCreditRate, portalModelCreditRates } from '@/lib/format'
import { ApiError, getAdminModels, setModelActive } from '@/services/api'
import type { AdminModelRow } from '@/services/api'

const { t } = useI18n()
const { adminToken } = useAuth()

const loading = ref(false)
const showAll = ref(true)
const models = ref<AdminModelRow[]>([])
const total = ref(0)
const activeCount = ref(0)
const togglingModel = ref('')

const countLabel = computed(() => t('admin.models.activeCount', { active: activeCount.value, total: total.value }))

function errorMessage(err: unknown): string {
  return err instanceof ApiError ? err.message : t('admin.models.toggleError')
}

function channelList(channels: string): string[] {
  return channels
    .split(',')
    .map((channel) => channel.trim())
    .filter(Boolean)
}

function modelRates(modelName: string) {
  return portalModelCreditRates(modelName)
}

async function fetchModels() {
  loading.value = true
  try {
    const response = await getAdminModels(adminToken.value, { showAll: showAll.value })
    models.value = response.items
    total.value = response.total
    activeCount.value = response.activeCount
  } catch (err) {
    toast.error(errorMessage(err))
  } finally {
    loading.value = false
  }
}

async function toggleModel(model: AdminModelRow) {
  if (togglingModel.value) return
  const nextActive = model.status !== 1
  togglingModel.value = model.model_name
  try {
    const result = await setModelActive(adminToken.value, model.model_name, nextActive)
    model.status = result.status
    activeCount.value += nextActive ? 1 : -1
    toast.success(t(nextActive ? 'admin.models.activated' : 'admin.models.deactivated', { name: model.model_name }))
  } catch (err) {
    toast.error(t('admin.models.toggleError'), { description: errorMessage(err) })
  } finally {
    togglingModel.value = ''
  }
}

watch(showAll, fetchModels)
onMounted(fetchModels)
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
      <div class="flex flex-col gap-1">
        <h1 class="text-xl font-semibold tracking-tight sm:text-2xl">{{ t('admin.models.title') }}</h1>
        <p class="text-sm text-muted-foreground">{{ countLabel }}</p>
      </div>
      <div class="flex items-center gap-4">
        <label class="flex items-center gap-2 text-sm font-medium">
          <Checkbox v-model="showAll" aria-label="Show all models" />
          {{ t('admin.models.showAll') }}
        </label>
        <Button variant="outline" :disabled="loading" @click="fetchModels">
          <IconRefresh class="size-4" />
          {{ t('common.refresh') }}
        </Button>
      </div>
    </div>

    <Card>
      <CardHeader>
        <CardTitle>{{ t('admin.nav.models') }}</CardTitle>
        <CardDescription>{{ countLabel }}</CardDescription>
      </CardHeader>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{{ t('admin.models.model') }}</TableHead>
              <TableHead>{{ t('admin.models.description') }}</TableHead>
              <TableHead>{{ t('admin.models.channels') }}</TableHead>
              <TableHead class="text-right">{{ t('admin.models.inputRate') }}</TableHead>
              <TableHead class="text-right">{{ t('admin.models.outputRate') }}</TableHead>
              <TableHead>{{ t('common.status') }}</TableHead>
              <TableHead class="text-right">{{ t('common.actions') }}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <template v-if="loading">
              <TableRow v-for="index in 8" :key="`model-skeleton-${index}`">
                <TableCell><Skeleton class="h-4 w-44" /></TableCell>
                <TableCell><Skeleton class="h-4 w-64" /></TableCell>
                <TableCell><Skeleton class="h-4 w-36" /></TableCell>
                <TableCell><Skeleton class="ml-auto h-4 w-16" /></TableCell>
                <TableCell><Skeleton class="ml-auto h-4 w-16" /></TableCell>
                <TableCell><Skeleton class="h-6 w-20" /></TableCell>
                <TableCell><Skeleton class="ml-auto h-8 w-28" /></TableCell>
              </TableRow>
            </template>
            <TableEmpty v-else-if="models.length === 0" :colspan="7" class="text-muted-foreground">
              {{ t('common.noData') }}
            </TableEmpty>
            <TableRow v-for="model in models" v-else :key="model.model_name">
              <TableCell class="font-medium">{{ model.model_name }}</TableCell>
              <TableCell class="max-w-md text-muted-foreground">{{ model.description || '—' }}</TableCell>
              <TableCell>
                <div class="flex max-w-xs flex-wrap gap-1">
                  <Badge v-for="channel in channelList(model.channels)" :key="`${model.model_name}-${channel}`" variant="outline">
                    {{ channel }}
                  </Badge>
                  <span v-if="channelList(model.channels).length === 0" class="text-muted-foreground">—</span>
                </div>
              </TableCell>
              <TableCell class="text-right tabular-nums">
                {{ modelRates(model.model_name) ? `${formatCreditRate(modelRates(model.model_name)!.input)}×` : '—' }}
              </TableCell>
              <TableCell class="text-right tabular-nums">
                {{ modelRates(model.model_name) ? `${formatCreditRate(modelRates(model.model_name)!.output)}×` : '—' }}
              </TableCell>
              <TableCell>
                <Badge :variant="model.status === 1 ? 'secondary' : 'outline'">
                  {{ model.status === 1 ? t('common.active') : t('common.inactive') }}
                </Badge>
              </TableCell>
              <TableCell class="text-right">
                <Button
                  :variant="model.status === 1 ? 'outline' : 'default'"
                  size="sm"
                  :disabled="Boolean(togglingModel)"
                  @click="toggleModel(model)"
                >
                  <IconPlayerPause v-if="model.status === 1" class="size-4" />
                  <IconPlayerPlay v-else class="size-4" />
                  {{ togglingModel === model.model_name ? t('common.loading') : model.status === 1 ? t('admin.models.deactivate') : t('admin.models.activate') }}
                </Button>
              </TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  </div>
</template>
