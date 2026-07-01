<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { checkAdminChannelCredit, getAdminChannels, getAdminModels, getAdminPlans, getAdminLogs, getAdminLogsStats, getAvailableModels, getDashboardLogs, getDashboardMe, getDashboardModels, getModelRatios, getHealth, getPortalConfig, getProvisionedUsers, getPublicPlans, getUserToken, grantDailyExtraQuota, loginAdmin, provisionUser, setModelActive, testDashboard, updateAdminChannel, createPlan, updatePlan, type AdminChannelCreditResult, type AdminChannelRow, type AdminLogStatsResponse, type AdminModelRow, type AdminModelsResponse, type AdminPlanRow, type DashboardMe, type HealthResponse, type LogRow, type ModelRatioRow, type GroupRatioRow, type ModelRatiosResponse, type ModelRow, type PlanPayload, type PortalConfig, type ProvisionResult, type ProvisionedUserRow, type PublicPlanRow, type UserTokenResult } from './services/api'
import LandingPage from './views/LandingPage.vue'
import AdminPortal from './admin/AdminPortal.vue'
import AdminDashboard from './admin/AdminDashboard.vue'
import { adminMenuItems } from './admin/admin-menu'
import type { AdminMenuKey } from './admin/types'

const apiKey = ref(localStorage.getItem('newApiPotalKey') || '')
const adminToken = ref(localStorage.getItem('newApiPotalAdminToken') || '')
const adminUserId = ref(Number(localStorage.getItem('newApiPotalAdminUserId') || 0))
const loggedIn = ref(Boolean(apiKey.value))
const adminLoggedIn = computed(() => Boolean(adminToken.value))
const activeMenu = ref<'overview' | 'pricing' | 'models' | 'logs' | 'docs' | 'admin'>('overview')
const health = ref<HealthResponse | null>(null)
const portalConfig = ref<PortalConfig | null>(null)
const me = ref<DashboardMe | null>(null)
const models = ref<ModelRow[]>([])
const logs = ref<LogRow[]>([])
const overviewLogs = ref<LogRow[]>([])
const logsPage = ref(1)
const logsPageSize = 10
const logsTotal = ref(0)
const userLogsFilter = ref({ model: '', status: '', startDate: '', endDate: '' })
const modelRatios = ref<ModelRatioRow[]>([])
const groupRatios = ref<GroupRatioRow[]>([])
const adminPlans = ref<AdminPlanRow[]>([])
const provisionedUsers = ref<ProvisionedUserRow[]>([])
const showCreateUserModal = ref(false)
const createUserForm = ref({ username: '', planId: 0 })
const createUserStatus = ref('')
const createUserKind = ref<'ok' | 'err' | ''>('')
const createUserSubmitting = ref(false)
const tokenFetchForm = ref({ userId: 0, username: '' })
const tokenFetchResult = ref<UserTokenResult | null>(null)
const tokenFetchStatus = ref('')
const tokenFetchKind = ref<'ok' | 'err' | ''>('')
const showGrantQuotaModal = ref(false)
const grantQuotaForm = ref({ userId: 0, username: '', amount: 10_000_000 })
const grantQuotaStatus = ref('')
const grantQuotaKind = ref<'ok' | 'err' | ''>('')
const grantQuotaSubmitting = ref(false)
const grantQuotaResult = ref<Record<string, unknown> | null>(null)
const showPlanModal = ref(false)
const planForm = ref({ id: 0, title: '', subtitle: '', priceAmount: 0, totalAmount: 20_000_000, quotaResetPeriod: 'never' as 'daily' | 'never', upgradeGroup: '', sortOrder: 50, modelList: '' as string })
const availableModels = ref<Array<{ model_name: string }>>([])
const planFormModelSearch = ref('')
const planFormSelectedModels = ref<string[]>([])
const publicPlans = ref<PublicPlanRow[]>([])
const publicPlansLoading = ref(false)
const planFormStatus = ref('')
const planFormKind = ref<'ok' | 'err' | ''>('')
const planFormSubmitting = ref(false)
const planFormEditing = ref(false)
const adminMenu = ref<AdminMenuKey>('dashboard')
const adminChannels = ref<AdminChannelRow[]>([])
const adminChannelsLoading = ref(false)
const adminChannelsFilter = ref({ q: '', status: '' as '' | number })
const adminChannelEditing = ref<number | null>(null)
const adminChannelForm = ref({ name: '', status: 1, baseUrl: '', group: '', models: '', weight: 0, priority: 0 })
const adminChannelCredit = ref<Record<number, AdminChannelCreditResult>>({})
const adminChannelChecking = ref<Set<number>>(new Set())
const adminLoginForm = ref({ username: '', password: '' })
const adminLogs = ref<LogRow[]>([])
const adminLogsPage = ref(1)
const adminLogsPageSize = 20
const adminLogsTotal = ref(0)
const adminLogsLoading = ref(false)
const adminLogsFilter = ref({ username: '', modelName: '', startDate: '', endDate: '' })
const adminLogsStats = ref<AdminLogStatsResponse | null>(null)
const adminLogsStatsLoading = ref(false)
const adminModelUsageOpen = ref(false)
const adminModels = ref<AdminModelsResponse | null>(null)
const adminModelsLoading = ref(false)
const adminModelsError = ref('')
const adminLogsMaxModelQuota = computed(() => {
  const list = adminLogsStats.value?.byModel || []
  return Math.max(1, ...list.map(m => Number(m.total_quota || 0)))
})
const adminLoginStatus = ref('')
const adminLoginKind = ref<'ok' | 'err' | ''>('')
const testingModels = ref<Set<string>>(new Set())
const notifications = ref<Array<{ id: number; type: 'ok' | 'err' | 'info'; title: string; message: string }>>([])
const error = ref('')
const dashboardReloading = ref(false)
const adminReloading = ref(false)
let dashboardReloadTimer: ReturnType<typeof window.setInterval> | undefined
let adminReloadTimer: ReturnType<typeof window.setInterval> | undefined
type ThemeMode = 'light' | 'dark'
const themeMode = ref<ThemeMode>('dark') // always dark (landing-aligned)
const isAdminRoute = ref(window.location.pathname === '/admin')
const navScrolled = ref(false)
const apiHealthy = ref<boolean | null>(null)
const healthChecking = ref(false)
const healthLatencyMs = ref<number | null>(null)
const healthLastCheckedAt = ref<number | null>(null)
const healthStatusClass = computed(() => {
  if (healthChecking.value) return 'checking'
  return apiHealthy.value === true ? 'ok' : apiHealthy.value === false ? 'off' : 'pending'
})
const healthStatusLabel = computed(() => {
  if (healthChecking.value) return 'CHECKING'
  if (apiHealthy.value === true && healthLatencyMs.value != null) return `LIVE · ${healthLatencyMs.value}ms`
  if (apiHealthy.value === true) return 'LIVE'
  if (apiHealthy.value === false) return 'OFFLINE'
  return 'PENDING'
})
const healthStatusTitle = computed(() => {
  const t = healthLastCheckedAt.value ? new Date(healthLastCheckedAt.value).toLocaleTimeString('vi-VN') : 'chưa kiểm tra'
  if (healthChecking.value) return 'Đang kiểm tra API…'
  return apiHealthy.value === true
    ? `API đang chạy — kiểm tra lúc ${t}`
    : apiHealthy.value === false
      ? `API không phản hồi (lúc ${t}) — bấm để thử lại`
      : 'Chưa kiểm tra'
})

async function refreshHealth() {
  if (healthChecking.value) return
  healthChecking.value = true
  const t0 = performance.now()
  try {
    const res = await getHealth()
    health.value = res
    healthLatencyMs.value = Math.round(performance.now() - t0)
    apiHealthy.value = true
  } catch {
    health.value = { success: false, service: 'unknown', newApiBaseUrl: '', time: new Date().toISOString() }
    healthLatencyMs.value = null
    apiHealthy.value = false
  } finally {
    healthChecking.value = false
    healthLastCheckedAt.value = Date.now()
  }
}

const currentSub = computed(() => me.value?.subscriptions?.find(s => s.status === 'active') || me.value?.subscriptions?.[0])
const currentPlanName = computed(() => String(currentSub.value?.plan_title || '').trim().toLowerCase())
const currentSubIsTokenPack = computed(() => String(currentSub.value?.quota_reset_period || 'daily') === 'never')
const refundDaysLeft = computed(() => {
  const endTime = currentSub.value?.end_time
  if (!endTime || currentSubIsTokenPack.value) return 0
  const end = new Date(String(endTime)).getTime()
  if (!Number.isFinite(end)) return 0
  return Math.max(0, Math.min(29, Math.floor((end - Date.now()) / 86_400_000)))
})
const refundPlanPrice = computed(() => Number(currentSub.value?.price_amount || 0))
const refundDailyValue = computed(() => refundPlanPrice.value / 30)
const refundEstimate = computed(() => refundPlanPrice.value > 0 ? Math.round(refundDailyValue.value * refundDaysLeft.value) : 0)
function isTokenPackRow(row: ProvisionedUserRow): boolean {
  return String(row.quota_reset_period || 'daily') === 'never'
}
const userId = computed(() => Number(me.value?.user?.user_id || adminUserId.value || 0))
const accountName = computed(() => String(me.value?.user?.display_name || me.value?.user?.username || me.value?.user?.user_id || ''))
const maskedKey = computed(() => apiKey.value.length <= 12 ? '••••••••' : `${apiKey.value.slice(0, 6)}••••••••${apiKey.value.slice(-4)}`)
const maskedAdminToken = computed(() => adminToken.value.length <= 12 ? '••••••••' : `${adminToken.value.slice(0, 6)}••••••••${adminToken.value.slice(-4)}`)

const newApiPublicBaseUrl = computed(() => portalConfig.value?.newApiPublicBaseUrl || health.value?.newApiPublicBaseUrl || 'http://localhost:3000')
const openAiBaseUrl = computed(() => portalConfig.value?.openAiBaseUrl || `${newApiPublicBaseUrl.value}/v1`)
const chatCompletionsUrl = computed(() => `${openAiBaseUrl.value}/chat/completions`)
const logsTotalPages = computed(() => Math.max(1, Math.ceil(logsTotal.value / logsPageSize)))
const adminLogsTotalPages = computed(() => Math.max(1, Math.ceil(adminLogsTotal.value / adminLogsPageSize)))

const curlSample = computed(() => `curl ${chatCompletionsUrl.value} \
  -H "Authorization: Bearer sk-..." \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-5.5","messages":[{"role":"user","content":"Xin chào"}]}'`)
const claudeCodeConfig = computed(() => `{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "sk-...",
    "ANTHROPIC_BASE_URL": "${newApiPublicBaseUrl.value}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "gpt-5.5",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "gpt-5.5-xhigh",
    "CLAUDE_CODE_SUBAGENT_MODEL": "gpt-5.5"
  },
  "model": "sonnet",
  "disableLoginPrompt": true
}`)
const codexConfig = computed(() => `model = "gpt-5.5"
model_provider = "newapi-local"

[model_providers.newapi-local]
name = "newapi-local"
base_url = "${openAiBaseUrl.value}"
wire_api = "responses"`)
const openCodeConfig = computed(() => `{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "openai": {
      "options": {
        "baseURL": "${openAiBaseUrl.value}",
        "apiKey": "{env:OPENAI_API_KEY}"
      }
    }
  },
  "model": "openai/gpt-5.5"
}`)
const rooCodeConfig = computed(() => `Base URL: ${openAiBaseUrl.value}
API Key:  sk-...
Model ID: gpt-5.5`)


type ModelSupportRow = { model: string; note: string; plus: string; pro: string; ultra: string; max?: string }
type UserQuotaPolicy = {
  inputRate: number;
  outputRate: number;
  label: string;
  tier: string;
  benefit: string;
}

const defaultUserQuotaPolicy: UserQuotaPolicy = {
  inputRate: 1,
  outputRate: 1,
  label: 'Input 1x · Output 1x',
  tier: 'user_token_1x',
  benefit: 'Token đầu vào và token trả lời trừ cùng hệ số.',
}

const userQuotaPolicies: Record<string, UserQuotaPolicy> = {
  'gpt-5.4': {
    inputRate: 0.5,
    outputRate: 3,
    label: 'Input 0.5x · Output 3x',
    tier: 'openai_price_gpt54',
    benefit: 'Model tiết kiệm hơn: input nhẹ, token trả lời tính cao hơn token đầu vào.',
  },
  'gpt-5.5': {
    inputRate: 1.2,
    outputRate: 6,
    label: 'Input 1.2x · Output 6x',
    tier: 'openai_price_gpt55',
    benefit: 'Model cao cấp: token đầu vào trừ 1.2x, token trả lời trừ nhiều token credit hơn token đầu vào.',
  },
  'gpt-5.5-xhigh': {
    inputRate: 1.2,
    outputRate: 6,
    label: 'Input 1.2x · Output 6x',
    tier: 'openai_price_gpt55',
    benefit: 'Model suy luận cao: token đầu vào trừ 1.2x, token trả lời trừ nhiều token credit hơn token đầu vào.',
  },
  'opus-4.8': {
    inputRate: 1.2,
    outputRate: 6,
    label: 'Input 1.2x · Output 6x',
    tier: 'openai_price_gpt55',
    benefit: 'Model cao cấp: token đầu vào trừ 1.2x, token trả lời trừ nhiều token credit hơn token đầu vào.',
  },
  'opus-4.8-thinking': {
    inputRate: 1.2,
    outputRate: 6,
    label: 'Input 1.2x · Output 6x',
    tier: 'openai_price_gpt55',
    benefit: 'Model suy luận cao: token đầu vào trừ 1.2x, token trả lời trừ nhiều token credit hơn token đầu vào.',
  },
  'claude-opus-4.8': {
    inputRate: 1.2,
    outputRate: 6,
    label: 'Input 1.2x · Output 6x',
    tier: 'openai_price_gpt55',
    benefit: 'Model cao cấp: token đầu vào trừ 1.2x, token trả lời trừ nhiều token credit hơn token đầu vào.',
  },
  'claude-opus-4.8-thinking': {
    inputRate: 1.2,
    outputRate: 6,
    label: 'Input 1.2x · Output 6x',
    tier: 'openai_price_gpt55',
    benefit: 'Model suy luận cao: token đầu vào trừ 1.2x, token trả lời trừ nhiều token credit hơn token đầu vào.',
  },
  'minimax-m3': defaultUserQuotaPolicy,
  'glm-5.2': {
    inputRate: 0.5,
    outputRate: 0.5,
    label: 'Input 0.5x · Output 0.5x',
    tier: 'user_token_0_5x',
    benefit: 'Tiết kiệm 50% token credit cho cả input và output.',
  },
  'glm-5.1': {
    inputRate: 0.25,
    outputRate: 0.25,
    label: 'Input 0.25x · Output 0.25x',
    tier: 'user_token_0_25x',
    benefit: 'Tiết kiệm 75% token credit cho cả input và output.',
  },
}

const modelSupportRows: ModelSupportRow[] = [
  // —— GPT ——
  { model: 'gpt-5.5', note: 'GPT 5.5', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn' },
  { model: 'gpt-5.5-high', note: 'GPT 5.5 High', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn' },
  { model: 'gpt-5.5-xhigh', note: 'GPT 5.5 X-High', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn' },
  { model: 'gpt-5.4', note: 'GPT 5.4', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn' },
  { model: 'gpt-5.3-codex', note: 'GPT 5.3 Codex', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn' },
  { model: 'gpt-5.3-codex-high', note: 'GPT 5.3 Codex High', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn' },
  { model: 'gpt-5.3-codex-xhigh', note: 'GPT 5.3 Codex X-High', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn' },
  // —— Kimi ——
  { model: 'kimi-k2.6', note: 'Kimi K2.6', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn' },
  // —— DeepSeek ——
  { model: 'deepseek-v4-flash', note: 'DeepSeek V4 Flash', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn' },
  { model: 'deepseek-v4-pro', note: 'DeepSeek V4 Pro', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn' },
  // —— MiniMax ——
  { model: 'minimax-m3', note: 'MiniMax M3', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn' },
  // —— Claude Opus (dot format — active) ——
  { model: 'claude-opus-4.6', note: 'Claude Opus 4.6', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn', max: 'Không giới hạn' },
  { model: 'claude-opus-4.6-thinking', note: 'Claude Opus 4.6 thinking', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn', max: 'Không giới hạn' },
  { model: 'claude-opus-4.7', note: 'Claude Opus 4.7', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn', max: 'Không giới hạn' },
  { model: 'claude-opus-4.7-thinking', note: 'Claude Opus 4.7 thinking', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn', max: 'Không giới hạn' },
  { model: 'claude-opus-4.8', note: 'Claude Opus 4.8', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn', max: 'Không giới hạn' },
  { model: 'claude-opus-4.8-thinking', note: 'Claude Opus 4.8 thinking', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn', max: 'Không giới hạn' },
  { model: 'opus-4.8', note: 'Opus 4.8 (short)', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn', max: 'Không giới hạn' },
  { model: 'opus-4.8-thinking', note: 'Opus 4.8 thinking (short)', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn', max: 'Không giới hạn' },
  // —— Claude Opus (dash format — inactive) ——
  { model: 'claude-opus-4-6', note: 'Claude Opus 4-6', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn', max: 'Không giới hạn' },
  { model: 'claude-opus-4-7', note: 'Claude Opus 4-7', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn', max: 'Không giới hạn' },
  { model: 'claude-opus-4-8', note: 'Claude Opus 4-8', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn', max: 'Không giới hạn' },
  // —— Claude Sonnet & Haiku ——
  { model: 'claude-sonnet-4.5-lite', note: 'Claude Sonnet 4.5 Lite', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn' },
  { model: 'claude-sonnet-4.6', note: 'Claude Sonnet 4.6', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn' },
  { model: 'claude-haiku-4.5', note: 'Claude Haiku 4.5', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn' },
  // —— Other ——
  { model: 'glm-5.1', note: 'GLM 5.1', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn' },
  { model: 'qwen3.5', note: 'Qwen 3.5', plus: 'Không giới hạn', pro: 'Không giới hạn', ultra: 'Không giới hạn' },
]

const request24hStats = computed(() => {
  const buckets = Array.from({ length: 12 }, (_, index) => ({ label: `${index * 2}h`, count: 0 }))
  for (const log of overviewLogs.value) {
    const date = new Date(String(log.created_at || ''))
    const hour = Number.isFinite(date.getTime()) ? date.getHours() : 0
    const bucketIndex = Math.min(11, Math.max(0, Math.floor(hour / 2)))
    buckets[bucketIndex].count += 1
  }
  const total = buckets.reduce((sum, bucket) => sum + bucket.count, 0)
  const max = Math.max(1, ...buckets.map(bucket => bucket.count))
  return { buckets, total, max }
})

const adminStats = computed(() => {
  const rows = provisionedUsers.value
  const uniqueUserIds = new Set(rows.map(r => Number(r.user_id)))
  const totalUsers = uniqueUserIds.size
  const activeSubs = rows.filter(r => String(r.subscription_status || '') === 'active').length
  const totalQuota = rows.reduce((sum, r) => sum + Number(r.amount_total || 0), 0)
  const extraToday = rows.reduce((sum, r) => sum + Number(r.daily_extra_quota || 0), 0)
  return { totalUsers, activeSubs, totalQuota, extraToday }
})

const topUsersByUsage = computed(() => {
  return [...provisionedUsers.value]
    .map(u => ({ ...u, _used: Number(u.amount_used || 0) }))
    .sort((a, b) => b._used - a._used)
    .slice(0, 5)
})

const adminClock = ref('')
let adminClockTimer: ReturnType<typeof setInterval> | null = null
function tickAdminClock() {
  const d = new Date()
  const pad = (n: number) => String(n).padStart(2, '0')
  adminClock.value = `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
}

const currentAdminItem = computed(() => adminMenuItems.find(i => i.key === adminMenu.value) || adminMenuItems[0])
const adminShellHealth = computed(() => {
  if (adminReloading.value) return { label: 'SYNCING', tone: 'info', text: 'Đang đồng bộ dữ liệu admin…' }
  if (adminLogsLoading.value || adminModelsLoading.value || adminChannelsLoading.value) return { label: 'LOADING', tone: 'info', text: 'Đang tải dữ liệu màn hiện tại.' }
  if (apiHealthy.value === false) return { label: 'API OFFLINE', tone: 'err', text: 'Backend chưa phản hồi trong lần kiểm tra gần nhất.' }
  return { label: 'LIVE', tone: 'ok', text: 'Admin portal đang dùng dữ liệu realtime từ 1API/New API.' }
})

const topModelStats = computed(() => {
  const counts = new Map<string, number>()
  for (const log of overviewLogs.value) {
    const modelName = String(log.model_name || 'unknown')
    counts.set(modelName, (counts.get(modelName) || 0) + 1)
  }
  const items = [...counts.entries()]
    .map(([model, count]) => ({ model, count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 5)
  const total = items.reduce((sum, item) => sum + item.count, 0)
  const max = Math.max(1, ...items.map(item => item.count))
  return { items, total, max }
})

function fmt(value: unknown) { return value === null || value === undefined || value === '' ? '-' : Number.isFinite(Number(value)) ? Number(value).toLocaleString('en-US') : String(value) }
function fmtCorn(value: unknown): string {
  const n = Number(value)
  if (!Number.isFinite(n)) return '-'
  return `${(n / 1_000_000).toLocaleString('vi-VN', { minimumFractionDigits: 0, maximumFractionDigits: 2 })} 🌽`
}
function fmtUnixSeconds(value: unknown): string {
  const n = Number(value)
  if (!Number.isFinite(n) || n <= 0) return '-'
  return new Date(n * 1000).toLocaleString('vi-VN')
}
function fmtMoney(value: unknown) {
  const n = Number(value || 0)
  if (!Number.isFinite(n)) return '-'
  return n.toLocaleString('vi-VN', { style: 'currency', currency: 'VND', maximumFractionDigits: 0 })
}
function fmtQuota(value: unknown): string {
  const n = Number(value)
  if (!Number.isFinite(n) || n <= 0) return '-'
  if (n >= 1_000_000) return `${Math.round(n / 1_000_000)}M`
  if (n >= 1_000) return `${Math.round(n / 1_000)}K`
  return String(n)
}
function fmtAmountInput(value: number | string | undefined | null): string {
  const n = Number(value || 0)
  return Number.isFinite(n) && n > 0 ? n.toLocaleString('en-US') : ''
}
function parseAmountInput(raw: string): number {
  const digits = String(raw || '').replace(/[^\d]/g, '')
  return digits ? Number(digits) : 0
}
function onAmountInput(field: 'amount' | 'userId', event: Event) {
  const input = event.target as HTMLInputElement
  const parsed = parseAmountInput(input.value)
  if (field === 'amount') grantQuotaForm.value.amount = parsed
  else grantQuotaForm.value.userId = parsed
  input.value = parsed > 0 ? parsed.toLocaleString('en-US') : ''
}
function fmtDate(value: unknown) {
  if (!value) return '-'
  const date = new Date(String(value))
  if (!Number.isFinite(date.getTime())) return String(value)
  return date.toLocaleDateString('vi-VN', {
    year: 'numeric', month: '2-digit', day: '2-digit',
  })
}
function fmtDateTime(value: unknown) {
  if (!value) return '-'
  const date = new Date(String(value))
  if (!Number.isFinite(date.getTime())) return String(value)
  return date.toLocaleString('vi-VN', {
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
    hour12: false,
  })
}
function getLogOther(log: LogRow): Record<string, unknown> {
  const raw = log.other
  if (!raw) return {}
  if (typeof raw === 'object') return raw as Record<string, unknown>
  try {
    const parsed = JSON.parse(String(raw))
    return parsed && typeof parsed === 'object' ? parsed : {}
  } catch {
    return {}
  }
}
function logCacheReadTokens(log: LogRow) { return Number(getLogOther(log).cache_tokens || 0) }
function logCacheWriteTokens(log: LogRow) {
  const other = getLogOther(log)
  const cacheWrite5m = Number(other.cache_creation_tokens_5m || 0)
  const cacheWrite1h = Number(other.cache_creation_tokens_1h || 0)
  return cacheWrite5m || cacheWrite1h
    ? cacheWrite5m + cacheWrite1h
    : Number(other.cache_creation_tokens || 0)
}
function logCacheCreationTokens(log: LogRow) {
  const other = getLogOther(log)
  const generic = Number(other.cache_creation_tokens || 0)
  const split = logCacheWriteTokens(log)
  return Math.max(generic, split)
}
function logCacheRatio(log: LogRow) { return Number(getLogOther(log).cache_ratio || 1) }
function logCacheCreationRatio(log: LogRow) {
  const other = getLogOther(log)
  const r5m = Number(other.cache_creation_ratio_5m || 0)
  const r1h = Number(other.cache_creation_ratio_1h || 0)
  return r5m || r1h || Number(other.cache_creation_ratio || 1)
}
function logImageTokens(log: LogRow) { return Number(getLogOther(log).image_output || 0) }
function logImageRatio(log: LogRow) { return Number(getLogOther(log).image_ratio || 1) }
function logModelRatio(log: LogRow) { return Number(getLogOther(log).model_ratio || 1) }
function logCompletionRatio(log: LogRow) { return Number(getLogOther(log).completion_ratio || 1) }
function logGroupRatio(log: LogRow) { return Number(getLogOther(log).group_ratio || 1) }
function quotaPolicyFor(modelName: string): UserQuotaPolicy {
  return userQuotaPolicies[modelName] || defaultUserQuotaPolicy
}
function rawTokens(prompt: number, completion: number): number {
  return prompt + completion
}
function expectedQuotaForPolicy(modelName: string, inputTokens: number, outputTokens: number): number {
  const policy = quotaPolicyFor(modelName)
  return Math.round(inputTokens * policy.inputRate + outputTokens * policy.outputRate)
}
function logQuotaBreakdown(log: LogRow) {
  const prompt = Number(log.prompt_tokens || 0)
  const completion = Number(log.completion_tokens || 0)
  const other = getLogOther(log)
  const policy = quotaPolicyFor(String(log.model_name || ''))
  if (other.billing_mode === 'tiered_expr') {
    const total = expectedQuotaForPolicy(String(log.model_name || ''), prompt, completion)
    return { prompt, completion, cacheRead: 0, cacheWrite: 0, image: 0, mr: policy.inputRate, cr: policy.outputRate, gr: 1, cacheRatio: 1, cacheCreationRatio: 1, imageRatio: 1, inputQuota: Math.round(prompt * policy.inputRate), outputQuota: Math.round(completion * policy.outputRate), total }
  }
  const cacheRead = logCacheReadTokens(log)
  const cacheWrite = logCacheCreationTokens(log)
  const image = logImageTokens(log)
  const mr = logModelRatio(log)
  const cr = logCompletionRatio(log)
  const gr = logGroupRatio(log)
  const cacheRatio = logCacheRatio(log)
  const cacheCreationRatio = logCacheCreationRatio(log)
  const imageRatio = logImageRatio(log)
  const billablePrompt = Math.max(0, prompt - cacheRead - cacheWrite - image)
  const promptQuota = billablePrompt + cacheRead * cacheRatio + cacheWrite * cacheCreationRatio + image * imageRatio
  const outputQuota = completion * cr
  const total = Math.round((promptQuota + outputQuota) * mr * gr)
  return { prompt, completion, cacheRead, cacheWrite, image, mr, cr, gr, cacheRatio, cacheCreationRatio, imageRatio, inputQuota: Math.round(promptQuota * mr * gr), outputQuota: Math.round(outputQuota * mr * gr), total }
}
function logQuotaFormula(log: LogRow) {
  const other = getLogOther(log)
  const modelName = String(log.model_name || '')
  const prompt = Number(log.prompt_tokens || 0)
  const completion = Number(log.completion_tokens || 0)
  if (other.billing_mode === 'tiered_expr') {
    const policy = quotaPolicyFor(modelName)
    const tier = String(other.matched_tier || policy.tier)
    return `input ${fmt(prompt)}×${policy.inputRate} + output ${fmt(completion)}×${policy.outputRate} = ${fmt(Number(log.quota || expectedQuotaForPolicy(modelName, prompt, completion)))} token credit · ${tier}`
  }
  const b = logQuotaBreakdown(log)
  const actual = Number(log.quota || 0)
  const parts = [`input ${fmt(b.prompt)}`]
  if (b.cacheRead) parts.push(`cache ${fmt(b.cacheRead)}×${b.cacheRatio}`)
  if (b.cacheWrite) parts.push(`cache write ${fmt(b.cacheWrite)}×${b.cacheCreationRatio}`)
  if (b.image) parts.push(`image ${fmt(b.image)}×${b.imageRatio}`)
  parts.push(`output ${fmt(b.completion)}×${b.cr}`)
  return `${parts.join(' + ')}; model×${b.mr}, group×${b.gr} => ${fmt(actual || b.total)} token credit`
}
function modelRatioFor(modelName: string): ModelRatioRow | undefined {
  return modelRatios.value.find(r => r.model_name === modelName)
}

function modelQuotaRateFor(modelName: string): string {
  return quotaPolicyFor(modelName).label
}

function modelCreditRateFor(modelName: string): string {
  const policy = quotaPolicyFor(modelName)
  return `Input ${policy.inputRate}x, output ${policy.outputRate}x`
}

function modelBenefitFor(modelName: string): string {
  return quotaPolicyFor(modelName).benefit
}

// User-facing model table: driven by active models returned from the API
// (already filtered by status on the backend). Static metadata (note/quota labels)
// is merged in from modelSupportRows when available; otherwise sensible defaults are used.
const visibleModelRows = computed<ModelSupportRow[]>(() => {
  const metaByName = new Map(modelSupportRows.map(r => [r.model, r]))
  return models.value.map(m => {
    const meta = metaByName.get(m.model_name)
    return meta ?? {
      model: m.model_name,
      note: m.description || m.model_name,
      plus: 'Không giới hạn',
      pro: 'Không giới hạn',
      ultra: 'Không giới hạn',
    }
  })
})
function groupRatioFor(groupName: string): number {
  return groupRatios.value.find(r => r.name === groupName)?.group_ratio ?? 1
}
function defaultGroupRatio(): number {
  // default group is '' or first entry — use 1 if not found
  return groupRatios.value.find(r => !r.name || r.name === 'default')?.group_ratio ?? 1
}
function quotaExampleFor(modelName: string, inputTokens = 1000, outputTokens = 500): string {
  const policy = quotaPolicyFor(modelName)
  const total = expectedQuotaForPolicy(modelName, inputTokens, outputTokens)
  const formula = `${inputTokens}×${policy.inputRate} + ${outputTokens}×${policy.outputRate}`
  return `${formula} = ${total.toLocaleString('en-US')} token credit`
}
function applyTheme(mode: ThemeMode) { document.documentElement.dataset.theme = mode; localStorage.setItem('newApiPotalTheme', mode) }
function toggleTheme() { themeMode.value = themeMode.value === 'light' ? 'dark' : 'light'; applyTheme(themeMode.value) }
function onScroll() { navScrolled.value = window.scrollY > 8 }
function goToAdmin() {
  if (isAdminRoute.value) return
  window.history.pushState({}, '', '/admin')
  isAdminRoute.value = true
  activeMenu.value = 'admin'
  // If not admin-logged-in yet, the admin section will show its login form
}
function onPopState() {
  isAdminRoute.value = window.location.pathname === '/admin'
  if (isAdminRoute.value) activeMenu.value = 'admin'
}

async function loadLogs(page = logsPage.value) {
  const result = await getDashboardLogs(apiKey.value, { page, size: logsPageSize })
  logs.value = result.items || []
  logsPage.value = Number(result.page || page)
  logsTotal.value = Number(result.total || 0)
}

async function loadOverviewLogs() {
  const result = await getDashboardLogs(apiKey.value, { page: 1, size: 1000 })
  overviewLogs.value = result.items || []
}

async function changeLogsPage(page: number) {
  const nextPage = Math.min(logsTotalPages.value, Math.max(1, page))
  await loadLogs(nextPage)
}

function isLogError(log: LogRow): boolean {
  // 1) Explicit error markers in response content
  const content = String(log.content || '').toLowerCase()
  if (content.includes('"error"') || content.includes('"code":') || content.includes('exception') || content.includes('"failed"')) return true
  // 2) quota = 0 nhưng có tokens => chưa bill được => fail
  const quota = Number(log.quota || 0)
  const prompt = Number(log.prompt_tokens || 0)
  const completion = Number(log.completion_tokens || 0)
  if (quota === 0 && (prompt > 0 || completion > 0)) return true
  // 3) use_time <= 0 mà đã có prompt_tokens => request lỗi giữa chừng
  const useTime = Number(log.use_time || 0)
  if (useTime <= 0 && prompt > 0) return true
  return false
}

function logMatchesFilter(log: LogRow): boolean {
  const f = userLogsFilter.value
  if (f.model && String(log.model_name || '') !== f.model) return false
  if (f.status === 'ok' && isLogError(log)) return false
  if (f.status === 'error' && !isLogError(log)) return false
  if (f.startDate) {
    const ts = Number(log.created_at || 0) * 1000
    const startTs = new Date(f.startDate).getTime()
    if (ts < startTs) return false
  }
  if (f.endDate) {
    const ts = Number(log.created_at || 0) * 1000
    const endTs = new Date(f.endDate).getTime() + 86_400_000
    if (ts > endTs) return false
  }
  return true
}

const userLogsAvailableModels = computed(() => {
  const set = new Set<string>()
  for (const l of overviewLogs.value) {
    const m = String(l.model_name || '').trim()
    if (m) set.add(m)
  }
  return Array.from(set).sort()
})

// Filtered logs (full set, client-side)
const filteredLogs = computed(() => overviewLogs.value.filter(logMatchesFilter))

// Paginated slice for the table
const paginatedFilteredLogs = computed(() => {
  const start = (logsPage.value - 1) * logsPageSize
  return filteredLogs.value.slice(start, start + logsPageSize)
})

const hasActiveFilter = computed(() => {
  const f = userLogsFilter.value
  return Boolean(f.model || f.status || f.startDate || f.endDate)
})

// Total pages is based on filtered count
const filteredLogsTotal = computed(() => filteredLogs.value.length)
const filteredLogsTotalPages = computed(() => Math.max(1, Math.ceil(filteredLogsTotal.value / logsPageSize)))

const userLogsModelUsage = computed(() => {
  const map = new Map<string, { model: string; count: number; quota: number }>()
  for (const l of filteredLogs.value) {
    const m = String(l.model_name || '').trim() || 'unknown'
    const cur = map.get(m) || { model: m, count: 0, quota: 0 }
    cur.count += 1
    cur.quota += Number(l.quota || 0)
    map.set(m, cur)
  }
  const arr = Array.from(map.values()).sort((a, b) => b.quota - a.quota)
  const max = Math.max(1, ...arr.map(r => r.quota))
  return arr.map(r => ({ ...r, pct: Math.max(2, Math.round((r.quota / max) * 100)) }))
})

const userLogsErrorStats = computed(() => {
  let success = 0
  let error = 0
  for (const l of filteredLogs.value) (isLogError(l) ? error++ : success++)
  const total = success + error
  const errorRate = total ? (error / total) * 100 : 0
  const successRate = total ? (success / total) * 100 : 100
  return { success, error, total, errorRate, successRate }
})

async function applyUserLogsFilter() {
  logsPage.value = 1
  await loadOverviewLogs()
}

function resetUserLogsFilter() {
  userLogsFilter.value = { model: '', status: '', startDate: '', endDate: '' }
  logsPage.value = 1
}

async function loadDashboard() {
  if (!apiKey.value || dashboardReloading.value) return
  dashboardReloading.value = true
  try {
    me.value = await getDashboardMe(apiKey.value)
    models.value = await getDashboardModels(apiKey.value)
    try {
      const ratioData = await getModelRatios(apiKey.value)
      modelRatios.value = ratioData.models || []
      groupRatios.value = ratioData.groups || []
    } catch { modelRatios.value = []; groupRatios.value = [] }
    await loadOverviewLogs()
    await loadLogs(logsPage.value)
  } finally {
    dashboardReloading.value = false
  }
}

async function reloadDashboard() {
  try {
    await loadDashboard()
    error.value = ''
  } catch (err) {
    error.value = err instanceof Error ? err.message : String(err)
  }
}

function startDashboardAutoReload() {
  if (dashboardReloadTimer) window.clearInterval(dashboardReloadTimer)
  dashboardReloadTimer = window.setInterval(() => {
    if (loggedIn.value && activeMenu.value !== 'admin') void reloadDashboard()
  }, 10_000)
}

function stopDashboardAutoReload() {
  if (!dashboardReloadTimer) return
  window.clearInterval(dashboardReloadTimer)
  dashboardReloadTimer = undefined
}

function startAdminAutoReload() {
  if (adminReloadTimer) window.clearInterval(adminReloadTimer)
  adminReloadTimer = window.setInterval(() => {
    if (adminLoggedIn.value && activeMenu.value === 'admin') void reloadAdmin()
  }, 10_000)
  tickAdminClock()
  if (!adminClockTimer) adminClockTimer = setInterval(tickAdminClock, 1000)
}

function stopAdminAutoReload() {
  if (!adminReloadTimer) return
  window.clearInterval(adminReloadTimer)
  adminReloadTimer = undefined
  if (adminClockTimer) { clearInterval(adminClockTimer); adminClockTimer = null }
}

async function login() {
  if (!apiKey.value.trim()) { error.value = 'Vui lòng nhập API key.'; return }
  try {
    apiKey.value = apiKey.value.trim()
    localStorage.setItem('newApiPotalKey', apiKey.value)
    logsPage.value = 1
    await loadDashboard()
    loggedIn.value = true
    startDashboardAutoReload()
    activeMenu.value = 'overview'
    error.value = ''
  } catch (err) {
    localStorage.removeItem('newApiPotalKey')
    loggedIn.value = false
    error.value = err instanceof Error ? err.message : String(err)
  }
}

function logout() { stopDashboardAutoReload(); stopAdminAutoReload(); localStorage.removeItem('newApiPotalKey'); localStorage.removeItem('newApiPotalAdminToken'); localStorage.removeItem('newApiPotalAdminUserId'); apiKey.value = ''; adminToken.value = ''; adminUserId.value = 0; loggedIn.value = false; me.value = null; activeMenu.value = 'overview'; if (window.location.pathname !== '/') { window.history.pushState({}, '', '/'); isAdminRoute.value = false } }

async function onLandingLogin(rawKey: string) {
  const key = rawKey.trim()
  if (!key) return
  apiKey.value = key
  localStorage.setItem('newApiPotalKey', key)
  try {
    await loadDashboard()
    loggedIn.value = true
    startDashboardAutoReload()
    activeMenu.value = 'overview'
    error.value = ''
  } catch (err) {
    localStorage.removeItem('newApiPotalKey')
    apiKey.value = ''
    error.value = err instanceof Error ? err.message : String(err)
  }
}

function onLandingGoAdmin() {
  if (isAdminRoute.value) return
  window.history.pushState({}, '', '/admin')
  isAdminRoute.value = true
  activeMenu.value = 'admin'
}

async function quickTestModel(modelName: string) {
  if (!apiKey.value) { notify('err', 'Chưa đăng nhập'); return }
  if (testingModels.value.has(modelName)) return
  testingModels.value.add(modelName)
  try {
    const startedAt = Date.now()
    await testDashboard(apiKey.value, { model: modelName, prompt: 'reply exactly: pong', maxTokens: 20 })
    const elapsed = Date.now() - startedAt
    notify('ok', `${modelName} · ${elapsed}ms · thành công`)
    await loadDashboard()
  } catch {
    notify('err', `${modelName} · thất bại`)
  } finally {
    testingModels.value.delete(modelName)
  }
}

function notify(type: 'ok' | 'err' | 'info', title: string, message = '') {
  const id = Date.now() + Math.floor(Math.random() * 1000)
  notifications.value.push({ id, type, title, message })
  setTimeout(() => {
    notifications.value = notifications.value.filter(n => n.id !== id)
  }, 5500)
}

function dismissNotification(id: number) {
  notifications.value = notifications.value.filter(n => n.id !== id)
}

async function copyText(text: string) {
  await navigator.clipboard.writeText(text)
}

async function copyBackendUrl() {
  const url = health.value?.newApiPublicBaseUrl || health.value?.newApiBaseUrl || newApiPublicBaseUrl.value
  await navigator.clipboard.writeText(String(url))
  notify('ok', 'Đã copy', String(url))
}

async function copyApiKey() {
  if (!apiKey.value) return
  await navigator.clipboard.writeText(apiKey.value)
  notify('ok', 'Đã copy API key', maskedKey.value)
}

async function loginAdminAccount() {
  adminLoginStatus.value = 'Đang đăng nhập admin...'
  try {
    const username = adminLoginForm.value.username.trim()
    if (!username || !adminLoginForm.value.password) throw new Error('Vui lòng nhập username và password admin.')
    const res = await loginAdmin({ username, password: adminLoginForm.value.password })
    adminToken.value = res.adminToken
    adminUserId.value = res.user.id
    localStorage.setItem('newApiPotalAdminToken', adminToken.value)
    localStorage.setItem('newApiPotalAdminUserId', String(adminUserId.value))
    adminLoginStatus.value = `Đã đăng nhập admin: ${res.user.username}`
    adminLoginKind.value = 'ok'
    activeMenu.value = 'admin'
    isAdminRoute.value = true
    if (window.location.pathname !== '/admin') window.history.pushState({}, '', '/admin')
    await loadAdmin()
    startAdminAutoReload()
  } catch (err) {
    adminToken.value = ''
    adminUserId.value = 0
    localStorage.removeItem('newApiPotalAdminToken')
    localStorage.removeItem('newApiPotalAdminUserId')
    adminLoginStatus.value = err instanceof Error ? err.message : String(err)
    adminLoginKind.value = 'err'
  }
}

async function loadAdminLogs(page = adminLogsPage.value) {
  if (!adminToken.value || adminLogsLoading.value) return
  adminLogsLoading.value = true
  adminLogsStatsLoading.value = true
  try {
    const f = adminLogsFilter.value
    const startTime = f.startDate ? Math.floor(new Date(f.startDate).getTime() / 1000) : undefined
    const endTime = f.endDate ? Math.floor(new Date(f.endDate + 'T23:59:59').getTime() / 1000) : undefined
    const filterParams = {
      username: f.username.trim() || undefined,
      modelName: f.modelName.trim() || undefined,
      startTime, endTime,
    }
    const [result] = await Promise.all([
      getAdminLogs(adminToken.value, { page, size: adminLogsPageSize, ...filterParams }),
      getAdminLogsStats(adminToken.value, filterParams).then(s => { adminLogsStats.value = s }).catch(() => { adminLogsStats.value = null }),
    ])
    adminLogs.value = result.items || []
    adminLogsPage.value = Number(result.page || page)
    adminLogsTotal.value = Number(result.total || 0)
  } finally {
    adminLogsLoading.value = false
    adminLogsStatsLoading.value = false
  }
}

async function changeAdminLogsPage(page: number) {
  await loadAdminLogs(Math.min(adminLogsTotalPages.value, Math.max(1, page)))
}

async function applyAdminLogsFilter() {
  adminLogsPage.value = 1
  await loadAdminLogs(1)
}

async function loadAdminModelsList() {
  if (!adminToken.value || adminModelsLoading.value) return
  adminModelsLoading.value = true
  adminModelsError.value = ''
  try {
    adminModels.value = await getAdminModels(adminToken.value, { showAll: true })
  } catch (err) {
    adminModelsError.value = err instanceof Error ? err.message : String(err)
    notify('err', 'Không tải được danh sách model', adminModelsError.value)
  } finally {
    adminModelsLoading.value = false
  }
}

async function loadAvailableModels() {
  if (!adminToken.value || availableModels.value.length) return
  try {
    availableModels.value = await getAvailableModels(adminToken.value)
  } catch (err) {
    notify('err', 'Không tải được danh sách model khả dụng', err instanceof Error ? err.message : String(err))
  }
}

function togglePlanModel(name: string) {
  const idx = planFormSelectedModels.value.indexOf(name)
  if (idx >= 0) planFormSelectedModels.value.splice(idx, 1)
  else planFormSelectedModels.value.push(name)
}

const planFormFilteredModels = computed(() => {
  const q = planFormModelSearch.value.trim().toLowerCase()
  const all = availableModels.value.map(m => m.model_name)
  if (!q) return all
  return all.filter(n => n.toLowerCase().includes(q))
})

async function loadPublicPlans() {
  if (publicPlans.value.length || publicPlansLoading.value) return
  publicPlansLoading.value = true
  try {
    publicPlans.value = await getPublicPlans()
  } catch {
    // silent — pricing page falls back to empty state
  } finally {
    publicPlansLoading.value = false
  }
}

const publicMonthlyPlans = computed(() => publicPlans.value.filter(p => p.quota_reset_period !== 'never').sort((a, b) => (a.sort_order ?? 99) - (b.sort_order ?? 99)))
const publicTokenPlans = computed(() => publicPlans.value.filter(p => p.quota_reset_period === 'never').sort((a, b) => (a.sort_order ?? 99) - (b.sort_order ?? 99)))

async function toggleModelActive(row: AdminModelRow) {
  if (!adminToken.value) return
  const nextActive = row.status !== 1
  try {
    await setModelActive(adminToken.value, row.model_name, nextActive)
    row.status = nextActive ? 1 : 0
    if (adminModels.value) {
      adminModels.value.activeCount = adminModels.value.items.filter(m => m.status === 1).length
    }
    notify('ok', nextActive ? `Đã bật ${row.model_name}` : `Đã tắt ${row.model_name}`, nextActive ? 'Model hiển thị cho user.' : 'Model ẩn khỏi user.')
  } catch (err) {
    notify('err', `Không đổi trạng thái ${row.model_name}`, err instanceof Error ? err.message : String(err))
  }
}

async function loadAdminChannels() {
  if (!adminToken.value || adminChannelsLoading.value) return
  adminChannelsLoading.value = true
  try {
    adminChannels.value = await getAdminChannels(adminToken.value, adminChannelsFilter.value)
  } catch (err) {
    notify('err', 'Không tải được channels', err instanceof Error ? err.message : String(err))
  } finally {
    adminChannelsLoading.value = false
  }
}

function openEditChannel(row: AdminChannelRow) {
  adminChannelEditing.value = Number(row.id)
  adminChannelForm.value = {
    name: String(row.name || ''),
    status: Number(row.status ?? 1),
    baseUrl: String(row.base_url || ''),
    group: String(row.group || ''),
    models: String(row.models || ''),
    weight: Number(row.weight || 0),
    priority: Number(row.priority || 0),
  }
}

async function saveAdminChannel() {
  if (!adminToken.value || adminChannelEditing.value == null) return
  try {
    await updateAdminChannel(adminToken.value, adminChannelEditing.value, { ...adminChannelForm.value })
    adminChannelEditing.value = null
    notify('ok', 'Đã cập nhật channel', 'Metadata channel đã được lưu vào New API.')
    await loadAdminChannels()
  } catch (err) {
    notify('err', 'Không lưu được channel', err instanceof Error ? err.message : String(err))
  }
}

async function checkChannelCredit(row: AdminChannelRow) {
  if (!adminToken.value) return
  const id = Number(row.id)
  adminChannelChecking.value.add(id)
  try {
    const result = await checkAdminChannelCredit(adminToken.value, id)
    adminChannelCredit.value = { ...adminChannelCredit.value, [id]: result }
    const idx = adminChannels.value.findIndex(c => Number(c.id) === id)
    if (idx >= 0 && result.total_available != null) adminChannels.value[idx].balance = Number(result.total_available)
    notify('ok', `Đã check ${row.name}`, `Remain quota: ${fmt(result.total_available)}`)
  } catch (err) {
    notify('err', `Không check được ${row.name}`, err instanceof Error ? err.message : String(err))
  } finally {
    adminChannelChecking.value.delete(id)
    adminChannelChecking.value = new Set(adminChannelChecking.value)
  }
}

async function loadAdmin() {
  if (!userId.value || !adminToken.value || adminReloading.value) return
  adminReloading.value = true
  try {
    adminPlans.value = await getAdminPlans(adminToken.value)
    provisionedUsers.value = await getProvisionedUsers(adminToken.value)
    await loadAdminChannels()
  } finally {
    adminReloading.value = false
  }
}

async function reloadAdmin() {
  try {
    await loadAdmin()
    adminLoginStatus.value = ''
  } catch (err) {
    adminLoginStatus.value = err instanceof Error ? err.message : String(err)
  }
}

function openCreateUserModal() {
  const firstPlan = adminPlans.value[0]
  createUserForm.value = { username: '', planId: firstPlan ? Number(firstPlan.id) : 0 }
  createUserStatus.value = ''
  createUserKind.value = ''
  showCreateUserModal.value = true
}
function closeCreateUserModal() {
  showCreateUserModal.value = false
  createUserStatus.value = ''
  createUserKind.value = ''
}
async function submitCreateUser() {
  if (createUserSubmitting.value) return
  const username = createUserForm.value.username.trim()
  if (!username) {
    createUserStatus.value = 'Vui lòng nhập username.'
    createUserKind.value = 'err'
    return
  }
  if (!createUserForm.value.planId) {
    createUserStatus.value = 'Vui lòng chọn gói.'
    createUserKind.value = 'err'
    return
  }
  createUserSubmitting.value = true
  createUserStatus.value = 'Đang tạo / cập nhật user...'
  createUserKind.value = ''
  try {
    await provisionUser(adminToken.value, { username, planId: Number(createUserForm.value.planId) })
    createUserStatus.value = 'Đã tạo / cập nhật user.'
    createUserKind.value = 'ok'
    await loadAdmin()
    setTimeout(closeCreateUserModal, 600)
  } catch (err) {
    createUserStatus.value = err instanceof Error ? err.message : String(err)
    createUserKind.value = 'err'
  } finally {
    createUserSubmitting.value = false
  }
}

async function fetchAndCopyToken(userId: number, username: string) {
  try {
    const r = await getUserToken(adminToken.value, { userId: userId > 0 ? userId : undefined, username: username || undefined })
    await navigator.clipboard.writeText(r.apiKey)
    notify('ok', `Đã copy token cho ${username}`, r.keyMasked)
  } catch (err) {
    notify('err', `Không lấy được token cho ${username}`, err instanceof Error ? err.message : String(err))
  }
}

function openGrantQuotaModal(userId: number, username: string) {
  grantQuotaForm.value = { userId, username, amount: 10_000_000 }
  grantQuotaStatus.value = ''
  grantQuotaKind.value = ''
  grantQuotaResult.value = null
  showGrantQuotaModal.value = true
}
function closeGrantQuotaModal() {
  showGrantQuotaModal.value = false
  grantQuotaStatus.value = ''
  grantQuotaKind.value = ''
  grantQuotaResult.value = null
}
async function submitGrantQuota() {
  if (grantQuotaSubmitting.value) return
  const targetUserId = Number(grantQuotaForm.value.userId || 0)
  const amount = Number(grantQuotaForm.value.amount || 0)
  if (targetUserId <= 0) {
    grantQuotaStatus.value = 'Vui lòng nhập User ID.'
    grantQuotaKind.value = 'err'
    return
  }
  if (amount <= 0) {
    grantQuotaStatus.value = 'Số quota cấp thêm phải lớn hơn 0.'
    grantQuotaKind.value = 'err'
    return
  }
  grantQuotaSubmitting.value = true
  grantQuotaStatus.value = 'Đang cấp thêm quota cho hôm nay...'
  grantQuotaKind.value = ''
  try {
    grantQuotaResult.value = await grantDailyExtraQuota(adminToken.value, { userId: targetUserId, amount })
    const isToken = String(grantQuotaResult.value?.planType || '') === 'token'
    grantQuotaStatus.value = isToken
      ? 'Đã cấp thêm token (vĩnh viễn, không reset).'
      : 'Đã cấp thêm quota cho hôm nay. Qua ngày quota sẽ reset về gói.'
    grantQuotaKind.value = 'ok'
    await loadAdmin()
    setTimeout(closeGrantQuotaModal, 900)
  } catch (err) {
    grantQuotaStatus.value = err instanceof Error ? err.message : String(err)
    grantQuotaKind.value = 'err'
  } finally {
    grantQuotaSubmitting.value = false
  }
}

// ---- plan management (token pack + monthly) ----

function openCreatePlanModal() {
  planForm.value = { id: 0, title: '', subtitle: '', priceAmount: 0, totalAmount: 20_000_000, quotaResetPeriod: 'never', upgradeGroup: '', sortOrder: 50, modelList: '' }
  planFormSelectedModels.value = []
  planFormModelSearch.value = ''
  if (!availableModels.value.length) void loadAvailableModels()
  planFormStatus.value = ''
  planFormKind.value = ''
  planFormEditing.value = false
  showPlanModal.value = true
}
function openEditPlanModal(plan: AdminPlanRow) {
  const ml = plan.model_list ? String(plan.model_list) : ''
  planForm.value = {
    id: Number(plan.id),
    title: String(plan.title || ''),
    subtitle: String(plan.subtitle || ''),
    priceAmount: Number(plan.price_amount || 0),
    totalAmount: Number(plan.total_amount || 0),
    quotaResetPeriod: String(plan.quota_reset_period || 'daily') === 'never' ? 'never' : 'daily',
    upgradeGroup: String(plan.upgrade_group || ''),
    sortOrder: Number(plan.sort_order || 50),
    modelList: ml,
  }
  planFormSelectedModels.value = ml ? ml.split(',').map(s => s.trim()).filter(Boolean) : []
  planFormModelSearch.value = ''
  if (!availableModels.value.length) void loadAvailableModels()
  planFormStatus.value = ''
  planFormKind.value = ''
  planFormEditing.value = true
  showPlanModal.value = true
}
function closePlanModal() {
  showPlanModal.value = false
  planFormStatus.value = ''
  planFormKind.value = ''
}
async function submitPlan() {
  if (planFormSubmitting.value) return
  const title = planForm.value.title.trim()
  if (!title) { planFormStatus.value = 'Vui lòng nhập tên gói.'; planFormKind.value = 'err'; return }
  if (planForm.value.totalAmount <= 0) { planFormStatus.value = 'Số token phải lớn hơn 0.'; planFormKind.value = 'err'; return }
  planFormSubmitting.value = true
  planFormStatus.value = planFormEditing.value ? 'Đang cập nhật gói...' : 'Đang tạo gói...'
  planFormKind.value = ''
  try {
    const payload: PlanPayload = {
      title,
      subtitle: planForm.value.subtitle,
      priceAmount: planForm.value.priceAmount,
      totalAmount: planForm.value.totalAmount,
      quotaResetPeriod: planForm.value.quotaResetPeriod,
      upgradeGroup: planForm.value.upgradeGroup,
      sortOrder: planForm.value.sortOrder,
      modelList: planFormSelectedModels.value.length ? planFormSelectedModels.value.join(',') : null,
    }
    if (planFormEditing.value && planForm.value.id) {
      await updatePlan(adminToken.value, planForm.value.id, payload)
    } else {
      await createPlan(adminToken.value, payload)
    }
    planFormStatus.value = planFormEditing.value ? 'Đã cập nhật gói.' : 'Đã tạo gói.'
    planFormKind.value = 'ok'
    adminPlans.value = await getAdminPlans(adminToken.value)
    setTimeout(closePlanModal, 600)
  } catch (err) {
    planFormStatus.value = err instanceof Error ? err.message : String(err)
    planFormKind.value = 'err'
  } finally {
    planFormSubmitting.value = false
  }
}

async function runGetToken() {
  tokenFetchStatus.value = 'Đang lấy token...'
  tokenFetchResult.value = null
  try {
    const username = tokenFetchForm.value.username.trim()
    const userId = Number(tokenFetchForm.value.userId || 0)
    if (!username && !userId) throw new Error('Vui lòng nhập username hoặc userId.')
    tokenFetchResult.value = await getUserToken(adminToken.value, { userId: userId > 0 ? userId : undefined, username: username || undefined })
    tokenFetchStatus.value = 'Đã lấy token. Copy cho user.'
    tokenFetchKind.value = 'ok'
    await loadAdmin()
  } catch (err) {
    tokenFetchStatus.value = err instanceof Error ? err.message : String(err)
    tokenFetchKind.value = 'err'
  }
}

onMounted(async () => {
  try {
    applyTheme(themeMode.value)
    try { health.value = await getHealth(); apiHealthy.value = true; healthLastCheckedAt.value = Date.now() } catch { apiHealthy.value = false; healthLastCheckedAt.value = Date.now() }
    portalConfig.value = await getPortalConfig()
    void loadPublicPlans()
    if (window.location.pathname === '/admin') { activeMenu.value = 'admin'; isAdminRoute.value = true }
    if (apiKey.value && window.location.pathname !== '/admin') await login()
    if (window.location.pathname === '/admin') { activeMenu.value = 'admin'; isAdminRoute.value = true; await loadAdmin(); if (adminLoggedIn.value) startAdminAutoReload() }
  } catch (err) { error.value = err instanceof Error ? err.message : String(err) }
  window.addEventListener('scroll', onScroll, { passive: true })
  window.addEventListener('popstate', onPopState)
  onScroll()
})

onUnmounted(() => { stopDashboardAutoReload(); stopAdminAutoReload(); window.removeEventListener('scroll', onScroll); window.removeEventListener('popstate', onPopState) })

watch(adminMenu, (menu) => {
  if (menu === 'logs' && adminLoggedIn.value && !adminLogs.value.length) void loadAdminLogs(1)
  if (menu === 'models' && adminLoggedIn.value && !adminModels.value) void loadAdminModelsList()
})
</script>

<template>
  <LandingPage v-if="!loggedIn && !isAdminRoute" @login="onLandingLogin" @go-admin="onLandingGoAdmin" />
  <template v-else>
  <header v-if="!isAdminRoute" class="topbar" :class="{ 'is-scrolled': navScrolled }">
    <div class="brand">
      <h1><span class="logo-mark">1</span>API</h1>
      <span class="brand-pill">POTAL</span>
    </div>
    <nav class="menu top-menu" aria-label="Dashboard">
      <button :class="{ active: activeMenu === 'overview' }" @click="activeMenu = 'overview'">TỔNG QUAN</button>
      <button :class="{ active: activeMenu === 'pricing' }" @click="activeMenu = 'pricing'">GÓI</button>
      <button :class="{ active: activeMenu === 'models' }" @click="activeMenu = 'models'">MODELS</button>
      <button :class="{ active: activeMenu === 'logs' }" @click="activeMenu = 'logs'">LOGS</button>
    </nav>
    <div class="topbar-cta">
      <button type="button" class="lp-status" :class="healthStatusClass" :title="healthStatusTitle" :disabled="healthChecking" @click="refreshHealth">
        <span class="dot" aria-hidden="true"></span>{{ healthStatusLabel }}
      </button>
      <span v-if="loggedIn && accountName" class="topbar-user" :title="accountName"><span class="topbar-user-dot" aria-hidden="true"></span>{{ accountName }}</span>
      <button v-if="loggedIn && apiKey" class="topbar-logout topbar-copykey" @click="copyApiKey" :title="maskedKey" aria-label="Copy API key">COPY KEY</button>
      <button class="topbar-logout" @click="logout" aria-label="Đăng xuất">LOGOUT</button>
    </div>
  </header>
  <main v-if="!isAdminRoute">
      <section v-if="activeMenu === 'overview'" class="overview-stack"><div class="cards"><div class="card"><span>Gói hiện tại</span><strong>{{ currentSub?.plan_title || 'Không có gói' }}</strong><p>Active: {{ fmtDate(currentSub?.start_time) }}</p><p>Hết hạn: {{ currentSubIsTokenPack ? 'Không giới hạn' : fmtDate(currentSub?.end_time) }}</p><p v-if="!currentSubIsTokenPack">Reset kế tiếp: {{ fmtDate(currentSub?.next_reset_time) }}</p><p v-else class="muted-note">Gói token — dùng đến khi hết</p></div><div class="card"><span>{{ currentSubIsTokenPack ? 'Token credit còn lại' : 'Token credit hôm nay' }}</span><strong>{{ fmt(currentSub?.amount_left) }}</strong><p>Đã dùng: {{ fmt(currentSub?.amount_used) }} / {{ fmt(currentSub?.amount_total) }}</p><p class="muted-note">Token credit được trừ theo input/output và hệ số từng model.</p></div><div class="card"><span>Backend</span><strong>1API</strong><div class="backend-url-row"><code class="backend-url">{{ health?.newApiPublicBaseUrl || health?.newApiBaseUrl }}</code><button class="small copy-btn-inline" @click="copyBackendUrl" title="Copy URL">Copy</button></div></div><div class="card refund-card"><span>Hoàn tiền dự kiến</span><strong>{{ fmtMoney(refundEstimate) }}</strong><p>Gói hiện tại: {{ fmtMoney(refundPlanPrice) }}</p><p>Còn lại: {{ fmt(refundDaysLeft) }} ngày · Mỗi ngày: {{ fmtMoney(refundDailyValue) }}</p><p class="muted-note">Tính theo công thức giá gói / 30 ngày × số ngày còn lại.</p></div></div><div class="card trust-card"><span class="trust-card-icon">🛡️</span><strong class="trust-card-title">Cam kết hoàn tiền</strong><p class="trust-card-line">Không hài lòng? Hoàn tiền ngay — chỉ tính phí theo thời gian đã sử dụng thực tế.</p><p class="trust-card-line">Hệ thống gặp sự cố? Hoặc bù ngày sử dụng.</p></div><div class="analytics-grid"><section class="card analytics-card"><div class="analytics-head"><h2>Request 24h</h2><span>Tổng {{ fmt(request24hStats.total) }} req</span></div><div class="mini-chart" aria-label="Request 24h chart"><div v-for="bucket in request24hStats.buckets" :key="bucket.label" class="chart-bar-wrap" :title="`${bucket.count} request`" :aria-label="`${bucket.count} request`"><div class="chart-tooltip">{{ bucket.count }} req</div><div class="chart-bar" :style="{ height: `${Math.max(8, (bucket.count / request24hStats.max) * 92)}px` }"></div><span>{{ bucket.count || '00' }}</span></div></div></section><section class="card analytics-card"><div class="analytics-head"><h2>Top model</h2><span>{{ fmt(topModelStats.total) }} req</span></div><div class="model-rank"><div v-for="item in topModelStats.items" :key="item.model" class="rank-row" :title="`${item.model}: ${item.count} request`"><div class="rank-line"><strong>{{ item.model }}</strong><span>{{ fmt(item.count) }}</span></div><div class="rank-track"><div class="rank-fill" :style="{ width: `${Math.max(3, (item.count / topModelStats.max) * 100)}%` }"></div></div></div><p v-if="!topModelStats.items.length" class="muted-note">Chưa có request trong 24h.</p></div></section></div></section>
      <section v-if="activeMenu === 'pricing'" class="card stack pricing-section">
        <div class="section-title">
          <h2>Bảng giá</h2>
          <p v-if="publicPlansLoading">Đang tải gói…</p>
          <p v-else-if="publicMonthlyPlans.length">Gói subscription theo tháng — token reset mỗi ngày lúc 00:00.</p>
          <p v-else>Chưa có gói nào được cấu hình.</p>
        </div>
        <div v-if="publicMonthlyPlans.length" class="pricing-grid">
          <article v-for="(plan, idx) in publicMonthlyPlans" :key="plan.id" class="pricing-card" :class="{ featured: idx === 1 }">
            <div class="pricing-head">
              <span v-if="idx === 1" class="badge">Khuyến nghị</span>
              <h3>{{ plan.title }}</h3>
              <strong>{{ Number(plan.price_amount || 0).toLocaleString('vi-VN') }}đ<small>/ tháng</small></strong>
            </div>
            <ul class="pricing-quota">
              <li>{{ fmtQuota(plan.total_amount) }} token / ngày</li>
            </ul>
            <ul>
              <li>Reset token hằng ngày</li>
              <li v-if="plan.subtitle">{{ plan.subtitle }}</li>
            </ul>
          </article>
        </div>
        <div v-if="publicTokenPlans.length" class="section-title" style="margin-top:2.5rem">
          <h2>Gói token (One-time)</h2>
          <p>Mua 1 lần, dùng đến khi hết — không giới hạn thời gian, stack được với gói tháng.</p>
        </div>
        <div v-if="publicTokenPlans.length" class="pricing-grid">
          <article v-for="(plan, idx) in publicTokenPlans" :key="plan.id" class="pricing-card" :class="{ featured: idx === 1 }">
            <div class="pricing-head">
              <span v-if="idx === 1" class="badge">Phổ biến</span>
              <h3>{{ plan.title }}</h3>
              <strong>{{ Number(plan.price_amount || 0).toLocaleString('vi-VN') }}đ<small> / 1 lần</small></strong>
            </div>
            <ul class="pricing-quota">
              <li>{{ fmtQuota(plan.total_amount) }} token</li>
            </ul>
            <ul>
              <li>Dùng đến khi hết</li>
              <li>Không giới hạn thời gian</li>
              <li>Stack với gói tháng</li>
            </ul>
          </article>
        </div>
        <p class="muted-note">Gói token dùng chung token credit với gói tháng — billing ưu tiên gói hết hạn sớm nhất trước. Liên hệ admin để mua gói token.</p>
        <p class="muted-note">Token credit được trừ theo input/output và hệ số từng model. Một số model cao cấp có token trả lời tính cao hơn token đầu vào — xem chi tiết tại tab <strong>Models</strong>.</p>
        <div class="trust-card pricing-trust-card">
          <span class="trust-card-icon">🛡️</span>
          <strong class="trust-card-title">Cam kết hoàn tiền</strong>
          <p class="trust-card-line">Không hài lòng? Hoàn tiền ngay — chỉ tính phí theo thời gian đã sử dụng thực tế.</p>
          <p class="trust-card-line">Hệ thống gặp sự cố? Hoặc bù ngày sử dụng.</p>
        </div>
      </section>
      <section v-if="activeMenu === 'models'" class="card stack">
        <div class="section-title">
          <h2>Models & Token Usage</h2>
          <p>Người dùng nhìn thấy token credit; hệ thống trừ theo token đầu vào, token trả lời và hệ số từng model.</p>
          <p class="muted-note">Formula: <code>token_credit = round(input_tokens × input_rate + output_tokens × output_rate)</code></p>
          <p class="muted-note">Model cao cấp có thể trừ token trả lời nhiều hơn token đầu vào. Model tiết kiệm dùng ít token credit hơn.</p>
        </div>
        <div class="admin-table-wrap">
          <table>
            <thead>
              <tr>
                <th>Model</th>
                <th>Token credit rate</th>
                <th>Cách tính</th>
                <th>Ưu đãi theo gói</th>
                <th>Example token charge<br/><span class="muted-note">1K in + 500 out</span></th>
                <th>Plus</th>
                <th>Pro</th>
                <th>Ultra</th>
                <th>Max</th>
                <th>Test</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in visibleModelRows" :key="row.model">
                <td data-label="Model"><strong>{{ row.model }}</strong><br /><span class="muted-note">{{ row.note }}</span></td>
                <td data-label="Hệ số"><strong>{{ modelQuotaRateFor(row.model) }}</strong><br /><span class="muted-note">{{ quotaPolicyFor(row.model).tier }}</span></td>
                <td data-label="Credit">{{ modelCreditRateFor(row.model) }}</td>
                <td data-label="Lợi ích"><span class="muted-note">{{ modelBenefitFor(row.model) }}</span></td>
                <td data-label="Công thức" class="quota-formula-cell"><span class="quota-calc">{{ quotaExampleFor(row.model) }}</span></td>
                <td data-label="Plus">{{ row.plus }}</td>
                <td data-label="Pro">{{ row.pro }}</td>
                <td data-label="Ultra">{{ row.ultra }}</td>
                <td data-label="Max">{{ row.max || 'Không giới hạn' }}</td>
                <td data-label="Action"><button class="small model-test-btn" :disabled="testingModels.has(row.model)" @click="quickTestModel(row.model)">{{ testingModels.has(row.model) ? '…' : 'Test' }}</button></td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
      <section v-if="activeMenu === 'logs'" class="card stack user-logs-section">
        <div class="section-title"><h2>Logs 24h</h2><p>Theo dõi usage, phát hiện lỗi và phân tích theo model.</p></div>
        <div class="user-logs-stats">
          <div class="user-logs-card user-logs-card-models">
            <header class="user-logs-card-head">
              <h3>Sử dụng theo model</h3>
              <span class="muted-note">{{ userLogsModelUsage.length }} model</span>
            </header>
            <div v-if="userLogsModelUsage.length" class="user-logs-model-bars">
              <div v-for="m in userLogsModelUsage" :key="m.model" class="ul-model-row">
                <span class="ul-model-name">{{ m.model }}</span>
                <div class="ul-bar-track" :title="`${m.count} req · ${fmt(m.quota)} token credit`"><div class="ul-bar-fill" :style="{ width: m.pct + '%' }"></div></div>
                <span class="ul-model-meta"><strong>{{ m.count }}</strong> req · {{ fmt(m.quota) }} token credit</span>
              </div>
            </div>
            <p v-else class="muted-note user-logs-empty">Chưa có log nào.</p>
          </div>
        </div>
        <div class="user-logs-filter">
          <label class="user-logs-filter-item">Model
            <select v-model="userLogsFilter.model">
              <option value="">Tất cả</option>
              <option v-for="m in userLogsAvailableModels" :key="m" :value="m">{{ m }}</option>
            </select>
          </label>
          <label class="user-logs-filter-item">Trạng thái
            <select v-model="userLogsFilter.status">
              <option value="">Tất cả</option>
              <option value="ok">Thành công</option>
              <option value="error">Lỗi</option>
            </select>
          </label>
          <label class="user-logs-filter-item">Từ ngày
            <input v-model="userLogsFilter.startDate" type="date" />
          </label>
          <label class="user-logs-filter-item">Đến ngày
            <input v-model="userLogsFilter.endDate" type="date" />
          </label>
          <div class="user-logs-filter-actions">
            <button class="primary" @click="applyUserLogsFilter">Tìm kiếm</button>
            <button @click="resetUserLogsFilter">Reset</button>
          </div>
        </div>
        <div class="user-logs-meta">
          <span>Hiển thị <strong>{{ fmt(filteredLogsTotal) }}</strong> / {{ fmt(overviewLogs.length) }} logs<span v-if="hasActiveFilter" class="muted-note"> (đang lọc)</span></span>
          <span class="muted-note">{{ logsPageSize }} per page · Page {{ logsPage }} / {{ filteredLogsTotalPages }}</span>
        </div>
        <div class="admin-table-wrap">
          <table class="logs-table">
            <thead>
              <tr><th>Time</th><th>ID</th><th>Model</th><th>Status</th><th>Tokens (in / out)</th><th>Token charge</th><th>Cache</th><th>Channel</th></tr>
            </thead>
            <tbody>
              <tr v-for="l in paginatedFilteredLogs" :key="String(l.id)">
                <td data-label="Time" class="time-cell">{{ fmtDateTime(l.created_at) }}</td>
                <td data-label="ID"><span class="muted-note">#{{ l.id }}</span></td>
                <td data-label="Model">{{ l.model_name }}</td>
                <td data-label="Status"><span class="status-pill" :class="isLogError(l) ? 'err' : 'ok'">{{ isLogError(l) ? 'Lỗi' : 'OK' }}</span></td>
                <td data-label="Tokens"><span class="token-detail">{{ fmt(l.prompt_tokens) }} / {{ fmt(l.completion_tokens) }}</span></td>
                <td data-label="Token charge"><strong>{{ fmt(l.quota) }} token credit</strong><br /><span class="muted-note">{{ logQuotaFormula(l) }}</span></td>
                <td data-label="Cache"><template v-if="logCacheReadTokens(l) || logCacheWriteTokens(l)"><span v-if="logCacheReadTokens(l)">R: {{ fmt(logCacheReadTokens(l)) }}</span><br v-if="logCacheReadTokens(l) && logCacheWriteTokens(l)" /><span v-if="logCacheWriteTokens(l)">W: {{ fmt(logCacheWriteTokens(l)) }}</span></template><span v-else class="muted-note">—</span></td>
                <td data-label="Channel" class="muted-note">{{ l.channel_name || '—' }}</td>
              </tr>
            </tbody>
          </table>
          <div v-if="!paginatedFilteredLogs.length" class="admin-app-empty-state"><div class="icon" aria-hidden="true">∅</div><div class="title">Không có log khớp filter</div><div class="desc">Thử điều chỉnh Model, Trạng thái hoặc khoảng ngày, rồi bấm Tìm kiếm.</div></div>
        </div>
        <div class="actions pager"><button :disabled="logsPage <= 1" @click="changeLogsPage(logsPage - 1)">← Trước</button><span>Trang {{ logsPage }} / {{ filteredLogsTotalPages }}</span><button :disabled="logsPage >= filteredLogsTotalPages" @click="changeLogsPage(logsPage + 1)">Sau →</button><button @click="loadOverviewLogs">Reload</button></div>
      </section>
      <section v-if="activeMenu === 'docs'" class="card stack docs"><div class="section-title"><h2>Tài liệu</h2><p>Cấu hình tool AI dev trỏ về 1API theo config backend Java.</p></div><div class="doc-grid"><div class="doc-card"><div class="doc-head"><h3>Base URL</h3><button class="small" @click="copyText(newApiPublicBaseUrl)">Copy</button></div><code class="code-block">{{ newApiPublicBaseUrl }}</code><p>Anthropic-compatible tools tự append <span class="inline-code">/v1/messages</span>.</p></div><div class="doc-card"><div class="doc-head"><h3>OpenAI Base URL</h3><button class="small" @click="copyText(openAiBaseUrl)">Copy</button></div><code class="code-block">{{ openAiBaseUrl }}</code><p>Dùng cho Chat Completions / Responses / OpenAI-compatible tools.</p></div></div><div class="doc-head"><h3>Test nhanh cURL</h3><button class="small" @click="copyText(curlSample)">Copy</button></div><pre class="result">{{ curlSample }}</pre><div class="doc-grid"><div class="doc-card"><div class="doc-head"><h3>Claude Code</h3><button class="small" @click="copyText(claudeCodeConfig)">Copy</button></div><pre class="result">{{ claudeCodeConfig }}</pre></div><div class="doc-card"><div class="doc-head"><h3>Codex CLI</h3><button class="small" @click="copyText(codexConfig)">Copy</button></div><pre class="result">{{ codexConfig }}</pre></div><div class="doc-card"><div class="doc-head"><h3>OpenCode</h3><button class="small" @click="copyText(openCodeConfig)">Copy</button></div><pre class="result">{{ openCodeConfig }}</pre></div><div class="doc-card"><div class="doc-head"><h3>Roo Code / OpenAI Compatible</h3><button class="small" @click="copyText(rooCodeConfig)">Copy</button></div><pre class="result">{{ rooCodeConfig }}</pre></div></div><p class="muted-note">Lưu ý: dùng key trong mục Tài khoản ở Tổng quan. Không commit key thật vào source.</p></section>
  </main>
  <AdminPortal
    v-if="isAdminRoute"
    v-model:adminMenu="adminMenu"
    :admin-logged-in="adminLoggedIn"
    :login-form="adminLoginForm"
    :login-status="adminLoginStatus"
    :login-kind="adminLoginKind"
    :menu-items="adminMenuItems"
    :current-item="currentAdminItem"
    :masked-admin-token="maskedAdminToken"
    :shell-health="adminShellHealth"
    :health-checking="healthChecking"
    :admin-reloading="adminReloading"
    @login="loginAdminAccount"
    @refresh-health="refreshHealth"
    @reload-admin="reloadAdmin"
    @logout="logout"
  >

            <AdminDashboard
              v-if="adminMenu === 'dashboard'"
              :admin-stats="adminStats"
              :top-users-by-usage="topUsersByUsage"
              :admin-clock="adminClock"
              :fmt="fmt"
              @set-menu="adminMenu = $event"
              @open-create-user="openCreateUserModal"
            />

            <div v-if="adminMenu !== 'logs' && adminMenu !== 'dashboard'" class="admin-metric-list admin-metric-list-compact fitness-reveal" aria-label="Chỉ số vận hành">
              <div class="admin-metric-row"><span class="admin-metric-label">Tổng user</span><strong>{{ fmt(adminStats.totalUsers) }}</strong></div>
              <div class="admin-metric-row"><span class="admin-metric-label">Gói active</span><strong>{{ fmt(adminStats.activeSubs) }}</strong></div>
              <div class="admin-metric-row"><span class="admin-metric-label">Tổng quota cấp</span><strong>{{ fmt(adminStats.totalQuota) }}</strong></div>
              <div class="admin-metric-row"><span class="admin-metric-label">Extra hôm nay</span><strong>{{ fmt(adminStats.extraToday) }}</strong></div>
            </div>

            <section v-if="adminMenu === 'users'" class="admin-app-data-panel stack fitness-reveal" :aria-busy="adminReloading">
              <div class="section-title admin-app-panel-head">
                <div>
                  <h2>Người dùng</h2>
                  <p>Danh sách user đã provision — bấm <strong>Lấy token</strong> để copy token trực tiếp.</p>
                </div>
                <button class="primary admin-add-user-btn" @click="openCreateUserModal">
                  <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>
                  Thêm người dùng
                </button>
              </div>
              <div v-if="adminReloading && !provisionedUsers.length" class="admin-skeleton" aria-label="Đang tải danh sách user">
                <div class="row" v-for="i in 7" :key="i"></div>
              </div>
              <div v-else class="admin-table-wrap">
                <table>
                  <caption class="sr-only">Danh sách user đã provision</caption>
                  <thead><tr><th scope="col">User</th><th scope="col">Token</th><th scope="col">Plan</th><th scope="col">Loại</th><th scope="col">Active</th><th scope="col">Hết hạn</th><th scope="col">Reset</th><th scope="col">Used</th><th scope="col">Extra hôm nay</th><th scope="col">Left</th><th scope="col">Action</th></tr></thead>
                  <tbody>
                    <tr v-for="u in provisionedUsers" :key="String(u.subscription_id || u.user_id)">
                      <td data-label="User">{{ u.username }}<br /><small>#{{ u.user_id }}</small></td>
                      <td data-label="Token"><code>{{ u.key_masked || '-' }}</code><br /><small>{{ u.token_name || '-' }}</small></td>
                      <td data-label="Plan">{{ u.plan_title || '-' }}</td>
                      <td data-label="Loại"><span class="status-pill" :class="isTokenPackRow(u) ? 'token' : 'ok'">{{ isTokenPackRow(u) ? 'Token' : 'Tháng' }}</span></td>
                      <td data-label="Active">{{ fmtDate(u.start_time) }}</td>
                      <td data-label="Hết hạn">{{ isTokenPackRow(u) ? 'Không giới hạn' : fmtDate(u.end_time) }}</td>
                      <td data-label="Reset">{{ isTokenPackRow(u) ? '—' : fmtDate(u.next_reset_time) }}</td>
                      <td data-label="Used">{{ fmt(u.amount_used) }}</td>
                      <td data-label="Extra hôm nay">{{ isTokenPackRow(u) ? '—' : fmt(u.daily_extra_quota) }}</td>
                      <td data-label="Left">{{ fmt(u.amount_left) }}</td>
                      <td data-label="Action" class="admin-row-actions">
                        <button class="small admin-action-token" @click="fetchAndCopyToken(Number(u.user_id), String(u.username || ''))" :title="`Copy API key cho ${u.username}`">Lấy token</button>
                        <button class="small admin-action-quota" @click="openGrantQuotaModal(Number(u.user_id), String(u.username || ''))">Cấp thêm</button>
                      </td>
                    </tr>
                    <tr v-if="!provisionedUsers.length"><td colspan="11" class="admin-app-empty-cell">Chưa có user nào được provision.</td></tr>
                  </tbody>
                </table>
              </div>
            </section>

            <section v-if="adminMenu === 'plans'" class="admin-app-data-panel stack fitness-reveal" :aria-busy="adminReloading">
              <div class="section-title admin-app-panel-head">
                <div>
                  <h2>Quản lý gói</h2>
                  <p>Tạo và sửa gói subscription — gói tháng (reset daily) và gói token (dùng đến khi hết).</p>
                </div>
                <button class="primary admin-add-user-btn" @click="openCreatePlanModal">
                  <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>
                  Thêm gói
                </button>
              </div>
              <div v-if="adminReloading && !adminPlans.length" class="admin-skeleton" aria-label="Đang tải danh sách gói">
                <div class="row" v-for="i in 5" :key="i"></div>
              </div>
              <div v-else class="admin-table-wrap">
                <table>
                  <caption class="sr-only">Danh sách gói subscription</caption>
                  <thead><tr><th scope="col">ID</th><th scope="col">Tên gói</th><th scope="col">Loại</th><th scope="col">Giá</th><th scope="col">Token</th><th scope="col">Group</th><th scope="col">Sort</th><th scope="col">Action</th></tr></thead>
                  <tbody>
                    <tr v-for="plan in adminPlans" :key="plan.id">
                      <td data-label="ID"><small>#{{ plan.id }}</small></td>
                      <td data-label="Tên gói"><strong>{{ plan.title }}</strong><br /><small class="muted-note">{{ plan.subtitle || '—' }}</small></td>
                      <td data-label="Loại"><span class="status-pill" :class="String(plan.quota_reset_period || 'daily') === 'never' ? 'token' : 'ok'">{{ String(plan.quota_reset_period || 'daily') === 'never' ? 'Token' : 'Tháng' }}</span></td>
                      <td data-label="Giá">{{ Number(plan.price_amount || 0).toLocaleString('vi-VN') }}đ</td>
                      <td data-label="Token">{{ fmtQuota(plan.total_amount) }}</td>
                      <td data-label="Group">{{ plan.upgrade_group || '—' }}</td>
                      <td data-label="Sort">{{ plan.sort_order ?? '—' }}</td>
                      <td data-label="Action"><button class="small" @click="openEditPlanModal(plan)">Sửa</button></td>
                    </tr>
                    <tr v-if="!adminPlans.length"><td colspan="8" class="admin-app-empty-cell">Chưa có gói nào.</td></tr>
                  </tbody>
                </table>
              </div>
            </section>

            <section v-if="adminMenu === 'models'" class="admin-app-data-panel stack fitness-reveal" :aria-busy="adminModelsLoading">
              <div class="section-title">
                <div>
                  <h2>Quản lý Model</h2>
                  <p>Model được lấy tự động từ cấu hình channel trong New API. Bật/tắt từng model để kiểm soát model hiển thị cho user.</p>
                </div>
              </div>
              <p v-if="adminModelsError" class="admin-banner err" role="status">{{ adminModelsError }}</p>
              <div v-if="adminModelsLoading && !adminModels" class="admin-skeleton" aria-label="Đang tải"><div class="row" v-for="i in 6" :key="i"></div></div>
              <div v-else-if="adminModels" class="admin-app-screen-meta">
                <span>Tổng <strong>{{ adminModels.total }}</strong> model · <strong>{{ adminModels.activeCount }}</strong> đang bật</span>
                <span class="muted-note">Bật/tắt để ẩn/hiện model cho user. Model đến từ channel của New API — không cần đồng bộ thủ công.</span>
              </div>
              <div class="admin-table-wrap" v-if="adminModels">
                <table>
                  <caption class="sr-only">Danh sách model quản lý</caption>
                  <thead><tr><th scope="col">Model</th><th scope="col">Channel</th><th scope="col">Hiển thị</th></tr></thead>
                  <tbody>
                    <tr v-for="m in adminModels.items" :key="m.model_name">
                      <td data-label="Model"><strong>{{ m.model_name }}</strong></td>
                      <td data-label="Channel"><span class="muted-note">{{ m.channels || '—' }}</span></td>
                      <td data-label="Hiển thị">
                        <label class="switch" :title="m.status === 1 ? 'Đang hiển cho user' : 'Đang ẩn khỏi user'">
                          <input type="checkbox" :checked="m.status === 1" @change="toggleModelActive(m)" />
                          <span class="switch-track"><span class="switch-thumb"></span></span>
                        </label>
                      </td>
                    </tr>
                    <tr v-if="!adminModels.items.length"><td colspan="3" class="admin-app-empty-state">Chưa có model nào. Tạo channel trong New API để thêm model.</td></tr>
                  </tbody>
                </table>
              </div>
            </section>

            <section v-if="adminMenu === 'channels'" class="admin-app-data-panel stack fitness-reveal" :aria-busy="adminChannelsLoading">
              <div class="section-title admin-app-panel-head">
                <div>
                  <h2>New API Channels</h2>
                  <p>Quản lý metadata channel và kiểm tra VietAPI remain quota theo từng upstream account.</p>
                </div>
                <button class="primary admin-add-user-btn" @click="loadAdminChannels" :disabled="adminChannelsLoading">{{ adminChannelsLoading ? 'Đang tải…' : 'Reload channels' }}</button>
              </div>
              <div class="admin-app-filter-bar">
                <label class="admin-app-filter-item">Tìm channel
                  <input v-model="adminChannelsFilter.q" placeholder="name, tag, id…" @keyup.enter="loadAdminChannels" />
                </label>
                <label class="admin-app-filter-item">Status
                  <select v-model="adminChannelsFilter.status">
                    <option value="">Tất cả</option>
                    <option :value="1">Enabled</option>
                    <option :value="2">Disabled</option>
                    <option :value="0">Unknown</option>
                  </select>
                </label>
                <div class="admin-app-filter-actions">
                  <button class="primary" @click="loadAdminChannels" :disabled="adminChannelsLoading">Tìm kiếm</button>
                  <button @click="adminChannelsFilter = { q: '', status: '' }; loadAdminChannels()">Reset</button>
                </div>
              </div>
              <div v-if="adminChannelsLoading && !adminChannels.length" class="admin-skeleton" aria-label="Đang tải danh sách channel">
                <div class="row" v-for="i in 6" :key="i"></div>
              </div>
              <div v-else class="admin-table-wrap">
                <table>
                  <caption class="sr-only">Danh sách New API channels</caption>
                  <thead><tr><th>ID</th><th>Channel</th><th>Upstream</th><th>Key</th><th>Models</th><th>Quota</th><th>Routing</th><th>Action</th></tr></thead>
                  <tbody>
                    <tr v-for="c in adminChannels" :key="c.id">
                      <td data-label="ID"><small>#{{ c.id }}</small></td>
                      <td data-label="Channel"><strong>{{ c.name }}</strong><br /><span class="status-pill" :class="Number(c.status) === 1 ? 'ok' : 'token'">{{ Number(c.status) === 1 ? 'Enabled' : 'Disabled' }}</span></td>
                      <td data-label="Upstream"><code>{{ c.base_url || '—' }}</code><br /><small>group: {{ c.group || 'default' }}</small></td>
                      <td data-label="Key"><code>{{ c.key_masked || '—' }}</code><br /><small>{{ fmt(c.token_count) }} token</small></td>
                      <td data-label="Models" class="muted-note">{{ String(c.models || '—').slice(0, 120) }}{{ String(c.models || '').length > 120 ? '…' : '' }}</td>
                      <td data-label="Quota">
                        <strong>{{ fmtCorn(adminChannelCredit[Number(c.id)]?.total_available ?? c.balance) }}</strong><br />
                        <small>raw: {{ fmt(adminChannelCredit[Number(c.id)]?.total_available ?? c.balance) }}</small><br />
                        <small>used: {{ fmtCorn(adminChannelCredit[Number(c.id)]?.total_used ?? c.used_quota) }}</small><br />
                        <small v-if="adminChannelCredit[Number(c.id)]?.daily_cap">hạn ngày: {{ fmtCorn(adminChannelCredit[Number(c.id)]?.daily_cap) }}</small><br v-if="adminChannelCredit[Number(c.id)]?.daily_cap" />
                        <small v-if="adminChannelCredit[Number(c.id)]?.expire_time">hạn: {{ fmtUnixSeconds(adminChannelCredit[Number(c.id)]?.expire_time) }}</small>
                      </td>
                      <td data-label="Routing">W {{ fmt(c.weight) }}<br /><small>P {{ fmt(c.priority) }}</small></td>
                      <td data-label="Action" class="admin-row-actions">
                        <button class="small" @click="checkChannelCredit(c)" :disabled="adminChannelChecking.has(Number(c.id))">{{ adminChannelChecking.has(Number(c.id)) ? 'Checking…' : 'Check credit' }}</button>
                        <button class="small" @click="openEditChannel(c)">Sửa</button>
                      </td>
                    </tr>
                    <tr v-if="!adminChannels.length"><td colspan="8" class="admin-app-empty-cell">Chưa có channel nào.</td></tr>
                  </tbody>
                </table>
              </div>
              <section v-if="adminChannelEditing !== null" class="card stack admin-channel-edit">
                <div class="section-title"><h3>Sửa channel #{{ adminChannelEditing }}</h3><p>Không hiển thị hoặc sửa secret key trong portal.</p></div>
                <div class="grid two">
                  <label>Name<input v-model="adminChannelForm.name" /></label>
                  <label>Status<select v-model.number="adminChannelForm.status"><option :value="1">Enabled</option><option :value="2">Disabled</option><option :value="0">Unknown</option></select></label>
                  <label>Base URL<input v-model="adminChannelForm.baseUrl" placeholder="https://api.vietapi.tech" /></label>
                  <label>Group<input v-model="adminChannelForm.group" placeholder="default" /></label>
                  <label>Weight<input v-model.number="adminChannelForm.weight" type="number" min="0" /></label>
                  <label>Priority<input v-model.number="adminChannelForm.priority" type="number" /></label>
                </div>
                <label>Models<textarea v-model="adminChannelForm.models" rows="5" placeholder="model-a,model-b"></textarea></label>
                <div class="actions"><button class="primary" @click="saveAdminChannel">Lưu channel</button><button @click="adminChannelEditing = null">Hủy</button></div>
              </section>
            </section>

            <section v-if="adminMenu === 'logs'" class="admin-logs-section admin-app-data-panel fitness-reveal" :aria-busy="adminLogsLoading || adminLogsStatsLoading">
              <div class="admin-app-filter-bar">
                <label class="admin-app-filter-item">User
                  <input v-model="adminLogsFilter.username" placeholder="username…" @keyup.enter="applyAdminLogsFilter" />
                </label>
                <label class="admin-app-filter-item">Model
                  <input v-model="adminLogsFilter.modelName" placeholder="model…" @keyup.enter="applyAdminLogsFilter" />
                </label>
                <label class="admin-app-filter-item">Từ ngày
                  <input v-model="adminLogsFilter.startDate" type="date" />
                </label>
                <label class="admin-app-filter-item">Đến ngày
                  <input v-model="adminLogsFilter.endDate" type="date" />
                </label>
                <div class="admin-app-filter-actions">
                  <button class="primary" @click="applyAdminLogsFilter" :disabled="adminLogsLoading">{{ adminLogsLoading ? 'Đang tải…' : 'Tìm kiếm' }}</button>
                  <button @click="adminLogsFilter = { username: '', modelName: '', startDate: '', endDate: '' }; applyAdminLogsFilter()">Reset</button>
                </div>
              </div>

              <div v-if="adminLogsStats && adminLogsStats.byModel.length" class="admin-logs-stats-card">
                <header class="admin-logs-stats-head admin-logs-stats-head-clickable" @click="adminModelUsageOpen = !adminModelUsageOpen">
                  <h3>Sử dụng theo model <span class="collapse-arrow" :class="{ open: adminModelUsageOpen }">▾</span></h3>
                  <span class="muted-note">{{ adminLogsStats.byModel.length }} model · {{ fmt(adminLogsStats.totals.req_count) }} req</span>
                </header>
                <div v-show="adminModelUsageOpen" class="admin-logs-stats-grid">
                  <div class="admin-logs-stats-totals">
                    <div class="als-totals-row"><span>Request</span><strong>{{ fmt(adminLogsStats.totals.req_count) }}</strong></div>
                    <div class="als-totals-row"><span>Quota</span><strong>{{ fmt(adminLogsStats.totals.total_quota) }}</strong></div>
                    <div class="als-totals-row"><span>Tokens in</span><strong>{{ fmt(adminLogsStats.totals.tokens_in) }}</strong></div>
                    <div class="als-totals-row"><span>Tokens out</span><strong>{{ fmt(adminLogsStats.totals.tokens_out) }}</strong></div>
                    <div class="als-totals-row"><span>Lỗi (use_time=0)</span><strong class="als-error">{{ fmt(adminLogsStats.totals.error_count) }}</strong></div>
                  </div>
                  <div class="admin-logs-stats-models">
                    <div v-for="m in adminLogsStats.byModel" :key="m.model" class="als-model-row">
                      <span class="als-model-name">{{ m.model }}</span>
                      <div class="als-bar-track" :title="`${fmt(m.req_count)} req · ${fmt(m.total_quota)} quota`">
                        <div class="als-bar-fill" :style="{ width: Math.max(3, Math.round((Number(m.total_quota) / adminLogsMaxModelQuota) * 100)) + '%' }"></div>
                      </div>
                      <span class="als-model-meta">
                        <strong>{{ fmt(m.req_count) }}</strong>
                        <span class="muted-note"> req</span>
                        <span class="als-dot">·</span>
                        <span>{{ fmt(m.total_quota) }}</span>
                      </span>
                    </div>
                  </div>
                </div>
              </div>
              <p v-else-if="adminLogsStatsLoading" class="muted-note admin-app-state-note">Đang tổng hợp stats…</p>
              <p v-else-if="adminLogsStats === null && !adminLogsLoading" class="muted-note admin-app-state-note">Bấm Tìm kiếm để xem tổng hợp.</p>

              <div class="admin-app-screen-meta">
                <span v-if="!adminLogsLoading">{{ fmt(adminLogsTotal) }} logs</span>
                <span v-else class="muted-note">Đang tải logs…</span>
                <span class="muted-note">{{ adminLogsPageSize }} per page · Page {{ adminLogsPage }} / {{ adminLogsTotalPages }}</span>
              </div>
              <div class="admin-logs-card">
                <div class="admin-table-wrap">
                  <div v-if="adminLogsLoading && !adminLogs.length" class="admin-skeleton" aria-label="Đang tải">
                    <div class="row" v-for="i in 8" :key="i"></div>
                  </div>
                  <table v-else class="admin-logs-table">
                    <caption class="sr-only">Usage logs toàn bộ user</caption>
                    <thead>
                      <tr>
                        <th scope="col">Time</th>
                        <th scope="col">User</th>
                        <th scope="col">Model</th>
                        <th scope="col">Type</th>
                        <th scope="col">Tokens (in / out)</th>
                        <th scope="col">Cache</th>
                        <th scope="col">Quota</th>
                        <th scope="col">Channel</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr v-for="l in adminLogs" :key="String(l.id)">
                        <td data-label="Time" class="time-cell">{{ fmtDateTime(l.created_at) }}</td>
                        <td data-label="User"><span class="admin-logs-user">{{ l.username }}</span><br /><small class="muted-note">#{{ l.user_id }}</small></td>
                        <td data-label="Model">{{ l.model_name }}</td>
                        <td data-label="Type">{{ l.type }}</td>
                        <td data-label="Tokens"><span class="token-detail">{{ fmt(l.prompt_tokens) }} / {{ fmt(l.completion_tokens) }}</span></td>
                        <td data-label="Cache">
                          <template v-if="logCacheReadTokens(l) || logCacheWriteTokens(l)">
                            <span v-if="logCacheReadTokens(l)">R: {{ fmt(logCacheReadTokens(l)) }}</span>
                            <br v-if="logCacheReadTokens(l) && logCacheWriteTokens(l)" />
                            <span v-if="logCacheWriteTokens(l)">W: {{ fmt(logCacheWriteTokens(l)) }}</span>
                          </template>
                          <span v-else class="muted-note">—</span>
                        </td>
                        <td data-label="Quota"><strong>{{ fmt(l.quota) }}</strong><br /><span class="muted-note">{{ logQuotaFormula(l) }}</span></td>
                        <td data-label="Channel" class="muted-note">{{ l.channel_name || '—' }}</td>
                      </tr>
                    </tbody>
                  </table>
                  <div v-if="!adminLogsLoading && !adminLogs.length" class="admin-app-empty-state">
                    <div class="icon" aria-hidden="true">∅</div>
                    <div class="title">Chưa có log nào</div>
                    <div class="desc">Thử điều chỉnh filter (username, model, khoảng ngày) rồi bấm Tìm kiếm.</div>
                  </div>
                </div>
                <div class="admin-logs-pager">
                  <button @click="changeAdminLogsPage(adminLogsPage - 1)" :disabled="adminLogsPage <= 1 || adminLogsLoading">← Trước</button>
                  <span class="page-info">Trang {{ adminLogsPage }} / {{ adminLogsTotalPages }}</span>
                  <button @click="changeAdminLogsPage(adminLogsPage + 1)" :disabled="adminLogsPage >= adminLogsTotalPages || adminLogsLoading">Sau →</button>
                  <button @click="loadAdminLogs(adminLogsPage)" :disabled="adminLogsLoading">{{ adminLogsLoading ? 'Đang tải…' : 'Reload' }}</button>
                </div>
              </div>
            </section>
    <template #modals>
        <transition name="admin-modal">
          <div v-if="showCreateUserModal" class="admin-modal-backdrop" @click.self="closeCreateUserModal" @keyup.esc="closeCreateUserModal">
            <div class="admin-modal card" role="dialog" aria-modal="true" aria-label="Thêm người dùng mới">
              <div class="admin-modal-head">
                <div>
                  <h3>Thêm người dùng</h3>
                  <p>Tạo mới hoặc cập nhật user + gán gói quota.</p>
                </div>
                <button class="theme-toggle" aria-label="Đóng" @click="closeCreateUserModal">×</button>
              </div>
              <div class="stack">
                <label>Username
                  <input v-model="createUserForm.username" placeholder="vd: customer_a" @keyup.enter="submitCreateUser" autofocus />
                </label>
                <label>Gói
                  <select v-model.number="createUserForm.planId">
                    <option v-for="plan in adminPlans" :key="plan.id" :value="plan.id">{{ String(plan.quota_reset_period || 'daily') === 'never' ? '[Token] ' : '[Tháng] ' }}{{ plan.title }} — {{ fmtQuota(plan.total_amount) }} token</option>
                  </select>
                </label>
                <p v-if="createUserStatus" class="admin-banner" :class="createUserKind" role="status">{{ createUserStatus }}</p>
              </div>
              <div class="admin-modal-foot">
                <button @click="closeCreateUserModal" :disabled="createUserSubmitting">Hủy</button>
                <button class="primary" @click="submitCreateUser" :disabled="createUserSubmitting">
                  {{ createUserSubmitting ? 'Đang tạo…' : 'Tạo / cập nhật' }}
                </button>
              </div>
            </div>
          </div>
        </transition>

        <transition name="admin-modal">
          <div v-if="showGrantQuotaModal" class="admin-modal-backdrop" @click.self="closeGrantQuotaModal" @keyup.esc="closeGrantQuotaModal">
            <div class="admin-modal card" role="dialog" aria-modal="true" aria-label="Cấp thêm quota cho user">
              <div class="admin-modal-head">
                <div>
                  <h3>Cấp thêm quota</h3>
                  <p v-if="grantQuotaForm.username">Bonus quota hôm nay cho <strong>{{ grantQuotaForm.username }}</strong> <span class="muted-note">(#{{ grantQuotaForm.userId }})</span></p>
                  <p v-else>Bonus quota cho user — nhập User ID.</p>
                </div>
                <button class="theme-toggle" aria-label="Đóng" @click="closeGrantQuotaModal">×</button>
              </div>
              <div class="stack">
                <label v-if="!grantQuotaForm.username">User ID
                  <input type="text" inputmode="numeric" :value="fmtAmountInput(grantQuotaForm.userId)" @input="onAmountInput('userId', $event)" placeholder="3" @keyup.enter="submitGrantQuota" autofocus />
                </label>
                <label>Số quota cấp thêm
                  <input type="text" inputmode="numeric" :value="fmtAmountInput(grantQuotaForm.amount)" @input="onAmountInput('amount', $event)" placeholder="10,000,000" @keyup.enter="submitGrantQuota" />
                </label>
                <p class="muted-note">Sang ngày mới quota reset về đúng gói, phần cấp thêm không cộng dồn.</p>
                <p v-if="grantQuotaStatus" class="admin-banner" :class="grantQuotaKind" role="status">{{ grantQuotaStatus }}</p>
                <div v-if="grantQuotaResult" class="result-card">
                  <div><span>Đã cấp thêm</span><code>{{ fmt(grantQuotaResult.grantedAmount) }}</code></div>
                  <div v-if="String(grantQuotaResult.planType || '') !== 'token'"><span>Tổng extra hôm nay</span><code>{{ fmt(grantQuotaResult.dailyExtraQuota) }}</code></div>
                  <div><span>{{ String(grantQuotaResult.planType || '') === 'token' ? 'Token còn lại' : 'Còn lại hôm nay' }}</span><code>{{ fmt(grantQuotaResult.amountLeft) }}</code></div>
                </div>
              </div>
              <div class="admin-modal-foot">
                <button @click="closeGrantQuotaModal" :disabled="grantQuotaSubmitting">Hủy</button>
                <button class="primary" @click="submitGrantQuota" :disabled="grantQuotaSubmitting">
                  {{ grantQuotaSubmitting ? 'Đang cấp…' : 'Cấp thêm cho hôm nay' }}
                </button>
              </div>
            </div>
          </div>
        </transition>

        <transition name="admin-modal">
          <div v-if="showPlanModal" class="admin-modal-backdrop" @click.self="closePlanModal" @keyup.esc="closePlanModal">
            <div class="admin-modal card" role="dialog" aria-modal="true" aria-label="Quản lý gói subscription">
              <div class="admin-modal-head">
                <div>
                  <h3>{{ planFormEditing ? 'Sửa gói' : 'Thêm gói' }}</h3>
                  <p>Cấu hình gói subscription.</p>
                </div>
                <button class="theme-toggle" aria-label="Đóng" @click="closePlanModal">×</button>
              </div>
              <div class="stack">
                <label>Tên gói
                  <input v-model="planForm.title" placeholder="vd: Pro Token 100M" @keyup.enter="submitPlan" autofocus />
                </label>
                <label>Mô tả
                  <input v-model="planForm.subtitle" placeholder="vd: 100M quota, dùng đến khi hết" />
                </label>
                <label>Loại gói
                  <select v-model="planForm.quotaResetPeriod">
                    <option value="never">Gói token (dùng đến khi hết, không reset)</option>
                    <option value="daily">Gói tháng (reset quota mỗi ngày)</option>
                  </select>
                </label>
                <label>Giá (VND)
                  <input type="text" inputmode="numeric" :value="fmtAmountInput(planForm.priceAmount)" @input="planForm.priceAmount = parseAmountInput(($event.target as HTMLInputElement).value)" placeholder="400000" @keyup.enter="submitPlan" />
                </label>
                <label>Số token (quota)
                  <input type="text" inputmode="numeric" :value="fmtAmountInput(planForm.totalAmount)" @input="planForm.totalAmount = parseAmountInput(($event.target as HTMLInputElement).value)" placeholder="100000000" @keyup.enter="submitPlan" />
                </label>
                <label>Upgrade group <span class="muted-note">(tuỳ chọn — vd: pro, max)</span>
                  <input v-model="planForm.upgradeGroup" placeholder="pro" />
                </label>
                <label>Sort order
                  <input type="number" v-model.number="planForm.sortOrder" placeholder="50" />
                </label>
                <div class="plan-model-select">
                  <div class="plan-model-select-head">
                    <span>Model áp dụng <span class="muted-note">(để trống = tất cả model từ channel)</span></span>
                    <span class="muted-note">{{ planFormSelectedModels.length ? `${planFormSelectedModels.length} model đã chọn` : 'Tất cả model' }}</span>
                  </div>
                  <input v-model="planFormModelSearch" placeholder="Tìm model…" class="plan-model-search" />
                  <div class="plan-model-list">
                    <label v-for="name in planFormFilteredModels" :key="name" class="plan-model-item">
                      <input type="checkbox" :checked="planFormSelectedModels.includes(name)" @change="togglePlanModel(name)" />
                      <span>{{ name }}</span>
                    </label>
                    <p v-if="!planFormFilteredModels.length" class="muted-note">Chưa có model nào. Tạo channel trong New API trước.</p>
                  </div>
                  <div v-if="planFormSelectedModels.length" class="plan-model-chips">
                    <span v-for="name in planFormSelectedModels" :key="name" class="plan-model-chip" @click="togglePlanModel(name)">{{ name }} ×</span>
                  </div>
                </div>
                <p v-if="planFormStatus" class="admin-banner" :class="planFormKind" role="status">{{ planFormStatus }}</p>
              </div>
              <div class="admin-modal-foot">
                <button @click="closePlanModal" :disabled="planFormSubmitting">Hủy</button>
                <button class="primary" @click="submitPlan" :disabled="planFormSubmitting">
                  {{ planFormSubmitting ? 'Đang lưu…' : (planFormEditing ? 'Cập nhật' : 'Tạo gói') }}
                </button>
              </div>
            </div>
          </div>
        </transition>
    </template>
  </AdminPortal>
    <Teleport to="body">
      <div class="toast-stack" role="status" aria-live="polite">
        <transition-group name="toast">
          <div v-for="n in notifications" :key="n.id" class="toast" :class="['toast-' + n.type]" @click="dismissNotification(n.id)">
            <div class="toast-icon" aria-hidden="true">
              <span v-if="n.type === 'ok'">✓</span>
              <span v-else-if="n.type === 'err'">!</span>
              <span v-else>·</span>
            </div>
            <div class="toast-body">
              <div class="toast-title">{{ n.title }}</div>
              <div v-if="n.message" class="toast-message">{{ n.message }}</div>
            </div>
          </div>
        </transition-group>
      </div>
    </Teleport>
  </template>
</template>
