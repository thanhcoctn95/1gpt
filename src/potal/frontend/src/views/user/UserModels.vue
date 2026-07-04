<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { toast } from 'vue-sonner'
import { IconInfoCircle, IconPlayerPlay, IconRefresh } from '@tabler/icons-vue'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import {
  Table,
  TableBody,
  TableCell,
  TableEmpty,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Skeleton } from '@/components/ui/skeleton'
import { useAuth } from '@/composables/useAuth'
import { formatNumber } from '@/lib/format'
import {
  getDashboardModels,
  getModelRatios,
  testDashboardModel,
  ApiError,
  type ModelRow,
  type ModelRatioRow,
  type GroupRatioRow,
} from '@/services/api'

const { t } = useI18n()
const { userApiKey } = useAuth()

const loading = ref(true)
const models = ref<ModelRow[]>([])
const ratios = ref<ModelRatioRow[]>([])
const groups = ref<GroupRatioRow[]>([])
const testOpen = ref(false)
const testModelName = ref('')
const testPrompt = ref('reply exactly: pong')
const testing = ref(false)
const testResult = ref('')
const testUsage = ref('')

const ratioMap = computed(() => {
  const map = new Map<string, ModelRatioRow>()
  for (const r of ratios.value) map.set(r.model_name, r)
  return map
})

const rows = computed(() =>
  models.value.map((m) => {
    const r = ratioMap.value.get(m.model_name)
    const ratio = Number(r?.model_ratio ?? 1)
    const completionRatio = Number(r?.completion_ratio ?? 1)
    const inputPer1k = 1000 * ratio
    const outputPer1k = 1000 * ratio * completionRatio
    return {
      model_name: m.model_name,
      description: m.description,
      ratio,
      completionRatio,
      inputPer1k,
      outputPer1k,
      sampleTotal: inputPer1k + outputPer1k,
    }
  }),
)

async function load() {
  loading.value = true
  try {
    const [modelsRes, ratiosRes] = await Promise.all([
      getDashboardModels(userApiKey.value),
      getModelRatios(userApiKey.value).catch(() => ({ models: [], groups: [] })),
    ])
    models.value = modelsRes
    ratios.value = ratiosRes.models
    groups.value = ratiosRes.groups
  } catch (err) {
    const msg = err instanceof ApiError ? err.message : String(err)
    toast.error(t('common.error'), { description: msg })
  } finally {
    loading.value = false
  }
}

function fmtRatio(v: number | undefined) {
  return typeof v === 'number' && Number.isFinite(v) ? `${v.toFixed(2)}×` : '—'
}

function fmtTokenCalc(value: number) {
  return formatNumber(Math.round(value))
}

function openTest(modelName: string) {
  testModelName.value = modelName
  testPrompt.value = 'reply exactly: pong'
  testResult.value = ''
  testUsage.value = ''
  testOpen.value = true
}

function extractText(payload: any): string {
  const content = payload?.choices?.[0]?.message?.content ?? payload?.choices?.[0]?.text
  if (typeof content === 'string' && content.trim()) return content.trim()
  return JSON.stringify(payload, null, 2)
}

function extractUsage(payload: any): string {
  const usage = payload?.usage
  if (!usage) return ''
  const prompt = Number(usage.prompt_tokens ?? 0)
  const completion = Number(usage.completion_tokens ?? 0)
  const total = Number(usage.total_tokens ?? prompt + completion)
  return `${t('user.models.usage')}: ${formatNumber(prompt)} / ${formatNumber(completion)} / ${formatNumber(total)}`
}

async function runTest() {
  if (!testModelName.value || testing.value) return
  testing.value = true
  testResult.value = ''
  testUsage.value = ''
  const started = performance.now()
  try {
    const response = await testDashboardModel(userApiKey.value, {
      model: testModelName.value,
      prompt: testPrompt.value,
      maxTokens: 64,
    })
    testResult.value = extractText(response)
    const elapsed = Math.max(1, Math.round(performance.now() - started))
    testUsage.value = [extractUsage(response), `${t('user.models.responseTime')}: ${(elapsed / 1000).toFixed(2)}s`]
      .filter(Boolean)
      .join(' · ')
    toast.success(t('user.models.testSuccess'))
  } catch (err) {
    const msg = err instanceof ApiError ? err.message : String(err)
    testResult.value = msg
    toast.error(t('user.models.testError'), { description: msg })
  } finally {
    testing.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="flex flex-col gap-4 md:gap-6">
    <Card>
      <CardHeader>
        <CardTitle class="flex items-center gap-2 text-base">
          <IconInfoCircle class="size-4" /> {{ t('user.models.howBilling') }}
        </CardTitle>
        <CardDescription>{{ t('user.models.billingNote') }}</CardDescription>
      </CardHeader>
    </Card>

    <Card>
      <CardHeader>
        <CardTitle class="text-base">{{ t('user.models.available') }}</CardTitle>
        <CardDescription>{{ t('user.models.calcHint') }}</CardDescription>
      </CardHeader>
      <CardContent>
        <div v-if="loading" class="flex flex-col gap-2">
          <Skeleton v-for="i in 6" :key="i" class="h-10 w-full" />
        </div>
        <Table v-else>
          <TableHeader>
            <TableRow>
              <TableHead>{{ t('user.models.model') }}</TableHead>
              <TableHead>{{ t('user.models.description') }}</TableHead>
              <TableHead class="text-right">{{ t('user.models.ratio') }}</TableHead>
              <TableHead>{{ t('user.models.tokenCalc') }}</TableHead>
              <TableHead class="text-right">{{ t('common.actions') }}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableEmpty v-if="!rows.length" :colspan="5">{{ t('common.noData') }}</TableEmpty>
            <TableRow v-for="row in rows" :key="row.model_name">
              <TableCell class="font-medium">{{ row.model_name }}</TableCell>
              <TableCell class="max-w-80 text-muted-foreground">{{ row.description || '—' }}</TableCell>
              <TableCell class="text-right tabular-nums">{{ fmtRatio(row.ratio) }}</TableCell>
              <TableCell>
                <div class="flex flex-col gap-1 text-sm">
                  <span>{{ t('user.models.input1k') }} → {{ fmtTokenCalc(row.inputPer1k) }}</span>
                  <span>{{ t('user.models.output1k') }} → {{ fmtTokenCalc(row.outputPer1k) }}</span>
                  <span class="text-muted-foreground">
                    {{ t('user.models.sample1k') }} → {{ fmtTokenCalc(row.sampleTotal) }}
                  </span>
                </div>
              </TableCell>
              <TableCell class="text-right">
                <Button variant="outline" size="sm" @click="openTest(row.model_name)">
                  <IconPlayerPlay class="size-4" />
                  {{ t('user.models.test') }}
                </Button>
              </TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </CardContent>
    </Card>

    <Card v-if="loading || groups.length">
      <CardHeader>
        <CardTitle class="text-base">{{ t('user.models.groupRatios') }}</CardTitle>
      </CardHeader>
      <CardContent>
        <div v-if="loading" class="flex flex-col gap-2">
          <Skeleton v-for="i in 3" :key="i" class="h-10 w-full" />
        </div>
        <Table v-else>
          <TableHeader>
            <TableRow>
              <TableHead>{{ t('user.models.group') }}</TableHead>
              <TableHead class="text-right">{{ t('user.models.ratio') }}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="g in groups" :key="g.name">
              <TableCell class="font-medium">{{ g.name }}</TableCell>
              <TableCell class="text-right tabular-nums">{{ fmtRatio(g.group_ratio) }}</TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </CardContent>
    </Card>

    <Dialog v-model:open="testOpen">
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{{ t('user.models.testTitle') }}</DialogTitle>
          <DialogDescription>{{ testModelName }}</DialogDescription>
        </DialogHeader>
        <div class="grid gap-3">
          <Label for="model-test-prompt">{{ t('user.models.prompt') }}</Label>
          <Textarea id="model-test-prompt" v-model="testPrompt" class="min-h-24" />
          <div v-if="testUsage" class="text-xs text-muted-foreground">{{ testUsage }}</div>
          <pre v-if="testResult" class="max-h-72 overflow-auto rounded-md bg-muted p-3 text-sm whitespace-pre-wrap">{{ testResult }}</pre>
        </div>
        <DialogFooter>
          <Button type="button" variant="outline" :disabled="testing" @click="testOpen = false">
            {{ t('common.close') }}
          </Button>
          <Button type="button" :disabled="testing" @click="runTest">
            <IconRefresh v-if="testing" class="size-4 animate-spin" />
            <IconPlayerPlay v-else class="size-4" />
            {{ testing ? t('common.loading') : t('user.models.runTest') }}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
