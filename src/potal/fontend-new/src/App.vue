<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  getAdminChannels,
  getAdminLogs,
  getAdminLogsStats,
  getAdminModels,
  getAdminPlans,
  getHealth,
  getProvisionedUsers,
  getUserToken,
  grantDailyExtraQuota,
  loginAdmin,
  setModelActive,
  testDashboard,
  type AdminChannelRow,
  type AdminLogStatsResponse,
  type AdminModelsResponse,
  type AdminPlanRow,
  type DailyExtraQuotaResult,
  type HealthResponse,
  type LogRow,
  type ProvisionedUserRow,
  type UserTokenResult,
} from './services/api'

type MenuKey = 'dashboard' | 'users' | 'models' | 'channels' | 'logs'
type NoticeTone = 'ok' | 'err' | 'info'

type MenuItem = {
  key: MenuKey
  label: string
  desc: string
  section: 'main' | 'organization'
  icon: string[]
}

const menuItems: MenuItem[] = [
  {
    key: 'dashboard',
    label: 'Tổng quan',
    desc: 'Tổng quan vận hành',
    section: 'main',
    icon: ['M3 10.5 12 3l9 7.5', 'M5 10v10h14V10', 'M9 20v-6h6v6'],
  },
  {
    key: 'logs',
    label: 'Nhật ký',
    desc: 'Nhật ký yêu cầu admin',
    section: 'main',
    icon: ['M4 19V5', 'M8 19v-7', 'M12 19V8', 'M16 19v-4', 'M20 19V9'],
  },
  {
    key: 'channels',
    label: 'Kênh',
    desc: 'Định tuyến & tín dụng',
    section: 'main',
    icon: ['M3 7h7l2 2h9v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z'],
  },
  {
    key: 'users',
    label: 'Người dùng',
    desc: 'Người dùng được cấp phép',
    section: 'organization',
    icon: ['M16 11a4 4 0 1 0-8 0', 'M3 21a7 7 0 0 1 14 0', 'M18 8a3 3 0 0 1 0 6', 'M21 21a5 5 0 0 0-3-4.58'],
  },
  {
    key: 'models',
    label: 'Mô hình',
    desc: 'Trạng thái đồng bộ mô hình',
    section: 'organization',
    icon: ['M12 15.5A3.5 3.5 0 1 0 12 8a3.5 3.5 0 0 0 0 7.5z', 'M19.4 15a1.8 1.8 0 0 0 .36 1.98l.04.05a2 2 0 1 1-2.83 2.83l-.05-.04a1.8 1.8 0 0 0-1.98-.36 1.8 1.8 0 0 0-1.1 1.65V21a2 2 0 1 1-4 0v-.07a1.8 1.8 0 0 0-1.1-1.65 1.8 1.8 0 0 0-1.98.36l-.05.04a2 2 0 1 1-2.83-2.83l.04-.05A1.8 1.8 0 0 0 4.6 15a1.8 1.8 0 0 0-1.65-1.1H3a2 2 0 1 1 0-4h.07A1.8 1.8 0 0 0 4.72 8.8a1.8 1.8 0 0 0-.36-1.98l-.04-.05a2 2 0 1 1 2.83-2.83l.05.04a1.8 1.8 0 0 0 1.98.36h.02A1.8 1.8 0 0 0 10.3 2.7V3a2 2 0 1 1 4 0v-.07a1.8 1.8 0 0 0 1.1 1.65 1.8 1.8 0 0 0 1.98-.36l.05-.04a2 2 0 1 1 2.83 2.83l-.04.05a1.8 1.8 0 0 0-.36 1.98v.02a1.8 1.8 0 0 0 1.65 1.1H21a2 2 0 1 1 0 4h-.07A1.8 1.8 0 0 0 19.4 15z'],
  },
]

const adminToken = ref(localStorage.getItem('newApiPotalAdminToken') || '')
const adminUser = ref(localStorage.getItem('newApiPotalAdminUser') || 'admin')
const loginForm = ref({ username: 'admin', password: '' })
const activeMenu = ref<MenuKey>('dashboard')
const loading = ref(false)
const booted = ref(false)
const notice = ref<{ tone: NoticeTone; text: string }>({ tone: 'info', text: 'Đăng nhập để tải dữ liệu quản trị.' })
const health = ref<HealthResponse | null>(null)
const plans = ref<AdminPlanRow[]>([])
const users = ref<ProvisionedUserRow[]>([])
const models = ref<AdminModelsResponse | null>(null)
const channels = ref<AdminChannelRow[]>([])
const logs = ref<LogRow[]>([])
const logStats = ref<AdminLogStatsResponse | null>(null)

// Grant dialog state
const grantDialogVisible = ref(false)
const grantUser = ref<ProvisionedUserRow | null>(null)
const grantAmount = ref(10000)
const grantLoading = ref(false)
const grantResult = ref<DailyExtraQuotaResult | null>(null)

// Copy token loading state (track which user's copy is in progress)
const copyLoadingUserId = ref<number | null>(null)

// Filter state
function todayStr(): string {
  const d = new Date()
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

const today = todayStr()
const channelsFilter = ref({ q: '', status: '' })
const logsFilter = ref({ username: '', modelName: '', status: '', startDate: today, endDate: today })
const channelsFilterOpen = ref(true)
const logsFilterOpen = ref(true)
const logsPage = ref(1)
const logsPageSize = 15
const logsTotal = ref(0)
const logsLoading = ref(false)

// Test dialog
const testDialogVisible = ref(false)
const testDialogModel = ref('')
const testPrompt = ref('Xin chào, hãy giới thiệu về bạn.')
const testResult = ref('')
const testLoading = ref(false)

const loggedIn = computed(() => Boolean(adminToken.value))
const currentItem = computed(() => menuItems.find(item => item.key === activeMenu.value) || menuItems[0])
const enabledPlans = computed(() => plans.value.filter(plan => plan.enabled !== false).length)
const activeUsers = computed(() => users.value.filter(user => Number(user.amount_left || 0) > 0).length)
const activeModels = computed(() => models.value?.activeCount ?? models.value?.items?.filter(model => model.status === 1).length ?? 0)
const activeChannels = computed(() => channels.value.filter(channel => channel.status === 1).length)
const requestCount = computed(() => logStats.value?.totals.req_count ?? logs.value.length)
const errorCount = computed(() => logStats.value?.totals.error_count ?? 0)
const topUsers = computed(() => (logStats.value?.byUser || []).slice(0, 5))
const topUserCards = computed(() => topUsers.value.map(topUser => {
  const userId = Number((topUser as Record<string, unknown>).user_id)
  const username = String((topUser as Record<string, unknown>).username || '')
  const matched = users.value.find(user => Number(user.user_id) === userId || user.username === username)
  return {
    ...topUser,
    planTitle: matched?.plan_title || 'Chưa có gói',
    amountLeft: matched?.amount_left ?? 0,
  }
}))
const healthTone = computed(() => (health.value?.success === false ? 'err' : health.value ? 'ok' : 'info'))
const healthLabel = computed(() => (health.value?.success === false ? 'API ngoại tuyến' : health.value ? 'API trực tuyến' : 'API đang chờ'))
const maskedToken = computed(() => adminToken.value.length > 14 ? `${adminToken.value.slice(0, 7)}••••${adminToken.value.slice(-5)}` : '••••••••')

function formatNumber(value: unknown): string {
  const number = Number(value || 0)
  return Number.isFinite(number) ? new Intl.NumberFormat('vi-VN').format(number) : '0'
}

function formatMoney(value: unknown): string {
  const number = Number(value || 0)
  return Number.isFinite(number) ? new Intl.NumberFormat('vi-VN').format(number) : '0'
}

function statusText(value: unknown): string {
  return Number(value) === 1 ? 'Hoạt động' : 'Không hoạt động'
}

function formatDate(ts: unknown): string {
  if (!ts) return '—'
  try {
    const d = new Date(ts as string | number | Date)
    if (isNaN(d.getTime())) {
      // try unix seconds
      const n = Number(ts)
      const ms = n > 1e12 ? n : n * 1000
      if (!Number.isFinite(ms)) return '—'
      return new Date(ms).toLocaleString('vi-VN')
    }
    return d.toLocaleString('vi-VN')
  } catch {
    return '—'
  }
}

function formatLogStatus(log: Record<string, unknown>): string {
  const requestStatus = String(log.request_status || '').toLowerCase()
  const sc = log.status_code
  const st = log.status
  if (requestStatus === 'error') return sc ? `Lỗi ${sc}` : 'Lỗi'
  if (requestStatus === 'success') return 'Thành công'
  if (sc !== undefined && sc !== null && sc !== '') {
    const code = Number(sc)
    return code >= 400 ? `Lỗi ${sc}` : String(sc)
  }
  if (st !== undefined && st !== null) return Number(st) === 1 ? 'Thành công' : 'Thất bại'
  return '—'
}

function formatCompactDate(ts: unknown): string {
  if (!ts) return '—'
  try {
    const d = new Date(ts as string | number | Date)
    if (isNaN(d.getTime())) return formatDate(ts)
    const day = String(d.getDate()).padStart(2, '0')
    const month = String(d.getMonth() + 1).padStart(2, '0')
    const hour = String(d.getHours()).padStart(2, '0')
    const minute = String(d.getMinutes()).padStart(2, '0')
    return `${day}/${month} ${hour}:${minute}`
  } catch {
    return formatDate(ts)
  }
}

function logStatusShort(log: Record<string, unknown>): string {
  const status = formatLogStatus(log)
  if (status === 'Thành công') return 'OK'
  if (status === 'Thất bại') return 'Fail'
  return status.replace('Lỗi ', 'E')
}

function logQuotaShort(value: unknown): string {
  const n = Number(value || 0)
  if (!Number.isFinite(n)) return '0'
  if (Math.abs(n) >= 1_000_000) return `${Math.round(n / 1_000_000)}M`
  if (Math.abs(n) >= 1_000) return `${Math.round(n / 1_000)}K`
  return formatNumber(n)
}

function logTokensShort(log: Record<string, unknown>): string {
  const ti = Number(log.tokens_in || log.prompt_tokens || 0)
  const to = Number(log.tokens_out || log.completion_tokens || 0)
  const short = (v: number) => Number.isFinite(v) && Math.abs(v) >= 1000 ? `${Math.round(v / 1000)}K` : formatNumber(v)
  return `${short(ti)}/${short(to)}`
}

function logStatusClass(log: Record<string, unknown>): Record<string, boolean> {
  const requestStatus = String(log.request_status || '').toLowerCase()
  const sc = Number(log.status_code)
  const st = Number(log.status)
  const ok = requestStatus === 'success' || (Number.isFinite(sc) && sc < 400) || st === 1
  return { 'status-on': ok, 'status-off': !ok }
}

function formatTokens(log: Record<string, unknown>): string {
  const ti = log.tokens_in || log.prompt_tokens || 0
  const to = log.tokens_out || log.completion_tokens || 0
  return `${formatNumber(ti)}/${formatNumber(to)}`
}

async function copyText(text: string) {
  try {
    await navigator.clipboard.writeText(text)
  } catch {
    // fallback
    const ta = document.createElement('textarea')
    ta.value = text
    ta.style.position = 'fixed'
    ta.style.opacity = '0'
    document.body.appendChild(ta)
    ta.select()
    document.execCommand('copy')
    document.body.removeChild(ta)
  }
}

async function fetchAndCopyToken(user: ProvisionedUserRow) {
  if (!adminToken.value || !user.user_id) return
  copyLoadingUserId.value = user.user_id
  try {
    const result = await getUserToken(adminToken.value, { userId: user.user_id })
    await copyText(result.apiKey)
    notice.value = { tone: 'ok', text: `Đã sao chép token của ${user.username}` }
  } catch (err) {
    notice.value = { tone: 'err', text: err instanceof Error ? err.message : 'Không thể lấy token.' }
  } finally {
    copyLoadingUserId.value = null
  }
}

function openGrantDialog(user: ProvisionedUserRow) {
  grantUser.value = user
  grantAmount.value = 10000
  grantResult.value = null
  grantDialogVisible.value = true
}

function closeGrantDialog() {
  grantDialogVisible.value = false
  grantUser.value = null
  grantAmount.value = 10000
  grantResult.value = null
  grantLoading.value = false
}

async function submitGrant() {
  if (!adminToken.value || !grantUser.value || grantAmount.value <= 0) return
  grantLoading.value = true
  grantResult.value = null
  try {
    const result = await grantDailyExtraQuota(adminToken.value, {
      userId: grantUser.value.user_id,
      amount: grantAmount.value,
    })
    grantResult.value = result
    notice.value = { tone: 'ok', text: `Đã cấp thêm ${formatNumber(grantAmount.value)} cho ${grantUser.value.username}` }
    // Refresh user data
    await loadWorkspace()
  } catch (err) {
    notice.value = { tone: 'err', text: err instanceof Error ? err.message : 'Không thể cấp thêm hạn mức.' }
  } finally {
    grantLoading.value = false
  }
}

async function signIn() {
  loading.value = true
  notice.value = { tone: 'info', text: 'Đang đăng nhập quản trị…' }
  try {
    const result = await loginAdmin(loginForm.value)
    adminToken.value = result.adminToken
    adminUser.value = result.user.displayName || result.user.username
    localStorage.setItem('newApiPotalAdminToken', result.adminToken)
    localStorage.setItem('newApiPotalAdminUserId', String(result.user.id))
    localStorage.setItem('newApiPotalAdminUser', adminUser.value)
    notice.value = { tone: 'ok', text: 'Đăng nhập thành công.' }
    await loadWorkspace()
  } catch (err) {
    notice.value = { tone: 'err', text: err instanceof Error ? err.message : 'Không thể đăng nhập quản trị.' }
  } finally {
    loading.value = false
  }
}

function logout() {
  adminToken.value = ''
  localStorage.removeItem('newApiPotalAdminToken')
  localStorage.removeItem('newApiPotalAdminUserId')
  notice.value = { tone: 'info', text: 'Đã đăng xuất.' }
}

async function loadAdminChannels() {
  if (!adminToken.value) return
  const token = adminToken.value
  const params: Record<string, string | number> = {}
  if (channelsFilter.value.q) params.q = channelsFilter.value.q
  if (channelsFilter.value.status !== '') params.status = channelsFilter.value.status
  channels.value = await getAdminChannels(token, params)
}

async function applyChannelsFilter() {
  await loadAdminChannels()
}

function resetChannelsFilter() {
  channelsFilter.value = { q: '', status: '' }
  void loadAdminChannels()
}

async function toggleModelActive(modelName: string, currentStatus: number) {
  if (!adminToken.value) return
  const active = Number(currentStatus) !== 1
  try {
    await setModelActive(adminToken.value, modelName, active)
    await loadWorkspace()
  } catch (err) {
    notice.value = { tone: 'err', text: err instanceof Error ? err.message : 'Không thể cập nhật mô hình.' }
  }
}

async function testModel(modelName: string) {
  if (!adminToken.value) return
  testDialogModel.value = modelName
  testPrompt.value = 'Xin chào, hãy giới thiệu về bạn.'
  testResult.value = ''
  testDialogVisible.value = true
}

async function sendTestRequest() {
  if (!adminToken.value || !testDialogModel.value) return
  testLoading.value = true
  testResult.value = ''
  try {
    const res = await testDashboard(adminToken.value, {
      model: testDialogModel.value,
      prompt: testPrompt.value,
      maxTokens: 512,
    })
    testResult.value = typeof res === 'string' ? res : JSON.stringify(res, null, 2)
  } catch (err) {
    testResult.value = err instanceof Error ? err.message : 'Lỗi không xác định'
  } finally {
    testLoading.value = false
  }
}

function closeTestDialog() {
  testDialogVisible.value = false
  testDialogModel.value = ''
  testPrompt.value = ''
  testResult.value = ''
}

async function loadAdminLogs(page = logsPage.value) {
  if (!adminToken.value || logsLoading.value) return
  logsLoading.value = true
  try {
    const f = logsFilter.value
    const startTime = f.startDate ? Math.floor(new Date(f.startDate).getTime() / 1000) : undefined
    const endTime = f.endDate ? Math.floor(new Date(f.endDate + 'T23:59:59').getTime() / 1000) : undefined
    const filterParams = {
      username: f.username.trim() || undefined,
      modelName: f.modelName.trim() || undefined,
      status: f.status || undefined,
      startTime,
      endTime,
    }
    const [result, stats] = await Promise.all([
      getAdminLogs(adminToken.value, { page, size: logsPageSize, ...filterParams }),
      getAdminLogsStats(adminToken.value, filterParams).catch(() => null),
    ])
    logs.value = result.items || []
    logsPage.value = Number(result.page || page)
    logsTotal.value = Number(result.total || 0)
    logStats.value = stats
  } finally {
    logsLoading.value = false
  }
}

async function applyLogsFilter() {
  logsPage.value = 1
  await loadAdminLogs(1)
}

function resetLogsFilter() {
  logsFilter.value = { username: '', modelName: '', status: '', startDate: today, endDate: today }
  logsPage.value = 1
  void loadAdminLogs(1)
}

const logsTotalPages = computed(() => Math.max(1, Math.ceil(logsTotal.value / logsPageSize)))

async function changeLogsPage(page: number) {
  await loadAdminLogs(Math.min(logsTotalPages.value, Math.max(1, page)))
}

async function loadWorkspace() {
  if (!adminToken.value) return
  loading.value = true
  try {
    const token = adminToken.value
    const [healthRes, plansRes, usersRes, modelsRes] = await Promise.all([
      getHealth().catch(() => null),
      getAdminPlans(token),
      getProvisionedUsers(token),
      getAdminModels(token, { showAll: true }),
    ])
    health.value = healthRes
    plans.value = plansRes
    users.value = usersRes
    models.value = modelsRes
    await Promise.all([
      loadAdminChannels(),
      loadAdminLogs(1),
    ])
    booted.value = true
  } catch (err) {
    notice.value = { tone: 'err', text: err instanceof Error ? err.message : 'Không thể tải dữ liệu.' }
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  if (adminToken.value) void loadWorkspace()
})
</script>

<template>
  <main class="admin-new-app" data-admin-ui="appshell-with-banner">
    <section v-if="!loggedIn" class="login-screen" aria-label="Đăng nhập quản trị">
      <div class="login-hero">
        <span class="eyebrow">AppShell · Có banner</span>
        <h1>Cổng quản trị 1API</h1>
        <p>Giao diện quản trị mới dùng Vue 3, tái sử dụng trực tiếp các API hiện tại qua <code>/api/admin/*</code>.</p>
        <div class="login-banner" role="status">
          <strong>Không gian làm việc mới</strong>
          <span>Sidebar shell · banner dạng vĩnh viễn · thẻ API trực tiếp</span>
        </div>
      </div>
      <form class="login-card" @submit.prevent="signIn">
        <span class="eyebrow">Truy cập an toàn</span>
        <h2>Đăng nhập quản trị</h2>
        <label>
          Tên đăng nhập
          <input v-model="loginForm.username" autocomplete="username" />
        </label>
        <label>
          Mật khẩu
          <input v-model="loginForm.password" type="password" autocomplete="current-password" />
        </label>
        <button class="primary" type="submit" :disabled="loading">{{ loading ? 'Đang đăng nhập…' : 'Đăng nhập' }}</button>
        <p class="notice" :class="notice.tone">{{ notice.text }}</p>
      </form>
    </section>

    <section v-else class="app-shell" aria-label="1API admin AppShell">
      <div class="app-shell-body">
        <aside class="side-nav" aria-label="Khu vực quản trị">
          <div class="side-nav-logo">
            <div class="side-nav-brand">
              <span class="logo-icon" aria-hidden="true">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 8v8"/><path d="M8 12h8"/></svg>
              </span>
              <strong>1API</strong>
            </div>
          </div>
          <section class="side-nav-section" aria-label="Main">
            <button
              v-for="item in menuItems.filter(item => item.section === 'main')"
              :key="item.key"
              class="side-nav-item"
              :class="{ selected: activeMenu === item.key }"
              :aria-current="activeMenu === item.key ? 'page' : undefined"
              @click="activeMenu = item.key"
            >
              <span class="side-nav-icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path v-for="(d, i) in item.icon" :key="i" :d="d" /></svg></span>
              <span>{{ item.label }}</span>
            </button>
          </section>

          <section class="side-nav-section" aria-labelledby="organization-nav-heading">
            <h2 id="organization-nav-heading">Tổ chức</h2>
            <button
              v-for="item in menuItems.filter(item => item.section === 'organization')"
              :key="item.key"
              class="side-nav-item"
              :class="{ selected: activeMenu === item.key }"
              :aria-current="activeMenu === item.key ? 'page' : undefined"
              @click="activeMenu = item.key"
            >
              <span class="side-nav-icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path v-for="(d, i) in item.icon" :key="i" :d="d" /></svg></span>
              <span>{{ item.label }}</span>
            </button>
          </section>

          <div class="session-card">
            <span class="pulse"></span>
            <div>
              <strong>{{ adminUser }}</strong>
              <code>{{ maskedToken }}</code>
            </div>
            <button class="nav-logout" type="button" @click="logout">Đăng xuất</button>
          </div>
        </aside>

        <main class="app-shell-content">
          <div class="page-stack">
            <section v-if="activeMenu === 'dashboard'" class="dashboard-hero" aria-label="Tổng quan nhanh">
              <div>
                <span class="eyebrow">Dashboard</span>
                <h1>1API vận hành</h1>
                <p>{{ healthLabel }} · {{ formatNumber(requestCount) }} yêu cầu · {{ formatNumber(errorCount) }} lỗi</p>
              </div>
              <button class="dashboard-refresh" type="button" @click="loadWorkspace" :disabled="loading">{{ loading ? 'Đang tải…' : 'Cập nhật' }}</button>
            </section>

            <section v-if="activeMenu === 'dashboard'" class="metric-grid" aria-label="Chỉ số">
              <article><span>Gói</span><strong>{{ enabledPlans }}/{{ plans.length }}</strong><small>gói đang hoạt động</small></article>
              <article><span>Người dùng</span><strong>{{ activeUsers }}</strong><small>người dùng có hạn mức</small></article>
              <article><span>Mô hình</span><strong>{{ activeModels }}</strong><small>mô hình đang hoạt động</small></article>
              <article><span>Kênh</span><strong>{{ activeChannels }}/{{ channels.length }}</strong><small>kênh trực tuyến</small></article>
              <article><span>Yêu cầu</span><strong>{{ formatNumber(requestCount) }}</strong><small>tổng yêu cầu</small></article>
              <article><span>Lỗi</span><strong>{{ formatNumber(errorCount) }}</strong><small>lỗi hệ thống</small></article>
            </section>

            <section v-if="activeMenu === 'dashboard'" class="panel-grid">
              <article class="panel">
                <div class="panel-head"><span class="eyebrow">Mô hình hàng đầu</span><h2>Trạng thái mô hình</h2></div>
                <ul class="compact-list">
                  <li v-for="model in (models?.items || []).slice(0, 6)" :key="model.model_name"><span>{{ model.model_name }}</span><em>{{ statusText(model.status) }}</em></li>
                </ul>
              </article>
              <article class="panel">
                <div class="panel-head"><span class="eyebrow">Người dùng tích cực</span><h2>Top người dùng</h2></div>
                <ul class="compact-list user-summary-list">
                  <li v-for="user in topUserCards" :key="user.user_id">
                    <span><strong>{{ user.username }}</strong><small>{{ user.planTitle }}</small></span>
                    <em>{{ formatNumber(user.amountLeft) }} token</em>
                  </li>
                  <li v-if="!logStats?.byUser?.length" class="empty-item">Chưa có dữ liệu</li>
                </ul>
              </article>
            </section>

            <section v-if="activeMenu === 'users'" class="panel">
              <div class="panel-head"><span class="eyebrow">Người dùng</span><h2>Người dùng được cấp phép</h2></div>
              <div class="table-wrap"><table><thead><tr><th>Người dùng</th><th>Gói</th><th>Còn lại</th><th></th></tr></thead><tbody><tr v-for="user in users" :key="user.user_id"><td>{{ user.username }}</td><td>{{ user.plan_title || '—' }}</td><td>{{ formatNumber(user.amount_left) }}</td><td class="actions-cell"><button class="copy-btn" @click="fetchAndCopyToken(user)" :disabled="copyLoadingUserId === user.user_id" title="Sao chép token">{{ copyLoadingUserId === user.user_id ? '⏳' : 'Copy token' }}</button><button class="grant-btn" @click="openGrantDialog(user)">Cấp thêm</button></td></tr></tbody></table></div>
            </section>

            <section v-if="activeMenu === 'models'" class="panel">
              <div class="panel-head"><span class="eyebrow">Mô hình</span><h2>Đồng bộ mô hình</h2></div>
              <div class="table-wrap"><table><thead><tr><th>Mô hình</th><th>Mô tả</th><th>Kênh</th><th>Trạng thái</th><th></th></tr></thead><tbody><tr v-for="model in models?.items || []" :key="model.model_name"><td>{{ model.model_name }}</td><td>{{ model.description || '—' }}</td><td>{{ model.channels || '—' }}</td><td><span class="status" :class="{ 'status-on': model.status === 1, 'status-off': model.status !== 1 }">{{ statusText(model.status) }}</span></td><td class="actions-cell"><button class="toggle-btn" :class="{ active: model.status === 1 }" @click="toggleModelActive(model.model_name, model.status)" :disabled="loading">{{ model.status === 1 ? 'Vô hiệu' : 'Kích hoạt' }}</button><button class="test-btn" @click="testModel(model.model_name)" :disabled="testLoading">Kiểm tra</button></td></tr></tbody></table></div>
            </section>

            <section v-if="activeMenu === 'channels'" class="panel">
              <div class="panel-head"><span class="eyebrow">Kênh</span><h2>Kênh định tuyến</h2></div>
              <button class="filter-toggle" type="button" :aria-expanded="channelsFilterOpen" @click="channelsFilterOpen = !channelsFilterOpen">
                <span>Lọc kênh</span><strong>{{ channelsFilterOpen ? 'Thu gọn' : 'Mở lọc' }}</strong>
              </button>
              <div v-show="channelsFilterOpen" class="filter-bar">
                <label class="filter-item">
                  Tìm kiếm
                  <input v-model="channelsFilter.q" placeholder="tên, tag, id…" @keyup.enter="applyChannelsFilter" />
                </label>
                <label class="filter-item">
                  Trạng thái
                  <select v-model="channelsFilter.status">
                    <option value="">Tất cả</option>
                    <option value="1">Bật</option>
                    <option value="2">Tắt</option>
                  </select>
                </label>
                <div class="filter-actions">
                  <button class="primary" @click="applyChannelsFilter" :disabled="loading">Lọc</button>
                  <button @click="resetChannelsFilter" :disabled="loading">Đặt lại</button>
                </div>
              </div>
              <div class="table-wrap"><table><thead><tr><th>Tên</th><th>URL gốc</th><th>Nhóm</th><th>Trạng thái</th><th>Số dư</th></tr></thead><tbody><tr v-for="channel in channels" :key="channel.id"><td>{{ channel.name }}</td><td>{{ channel.base_url || '—' }}</td><td>{{ channel.group || '—' }}</td><td><span class="status">{{ statusText(channel.status) }}</span></td><td>{{ formatNumber(channel.balance) }}</td></tr></tbody></table></div>
            </section>

            <section v-if="activeMenu === 'logs'" class="panel">
              <div class="panel-head"><span class="eyebrow">Nhật ký</span><h2>Nhật ký sử dụng</h2></div>
              <button class="filter-toggle" type="button" :aria-expanded="logsFilterOpen" @click="logsFilterOpen = !logsFilterOpen">
                <span>Lọc nhật ký</span><strong>{{ logsFilterOpen ? 'Thu gọn' : 'Mở lọc' }}</strong>
              </button>
              <div v-show="logsFilterOpen" class="filter-bar logs-filter-bar">
                <label class="filter-item">
                  Người dùng
                  <input v-model="logsFilter.username" placeholder="tên người dùng…" @keyup.enter="applyLogsFilter" />
                </label>
                <label class="filter-item">
                  Mô hình
                  <input v-model="logsFilter.modelName" placeholder="mô hình…" @keyup.enter="applyLogsFilter" />
                </label>
                <label class="filter-item">
                  Trạng thái
                  <select v-model="logsFilter.status">
                    <option value="">Tất cả</option>
                    <option value="success">Thành công</option>
                    <option value="error">Lỗi</option>
                  </select>
                </label>
                <label class="filter-item logs-date-item">
                  Từ ngày
                  <input v-model="logsFilter.startDate" type="date" />
                </label>
                <label class="filter-item logs-date-item">
                  Đến ngày
                  <input v-model="logsFilter.endDate" type="date" />
                </label>
                <div class="filter-actions">
                  <button class="primary" @click="applyLogsFilter" :disabled="logsLoading">{{ logsLoading ? 'Đang tải…' : 'Tìm kiếm' }}</button>
                  <button @click="resetLogsFilter" :disabled="logsLoading">Đặt lại</button>
                </div>
              </div>
              <div class="table-wrap logs-table-wrap"><table class="logs-table"><thead><tr><th>User</th><th>Model</th><th>TG</th><th>TT</th><th>Token</th><th>Quota</th></tr></thead><tbody><tr v-for="(log, index) in logs" :key="index"><td data-label="Người dùng">{{ log.username || log.user_id || '—' }}</td><td data-label="Mô hình">{{ log.model_name || log.model || '—' }}</td><td data-label="Thời gian" class="time-cell" :title="formatDate(log.created_at)">{{ formatCompactDate(log.created_at) }}</td><td data-label="Trạng thái"><span class="status" :class="logStatusClass(log)" :title="formatLogStatus(log)">{{ logStatusShort(log) }}</span><small v-if="log.error_message" class="log-error-message">{{ log.error_message }}</small></td><td data-label="Token" class="tokens-cell" :title="formatTokens(log)">{{ logTokensShort(log) }}</td><td data-label="Quota"><strong :title="formatNumber(log.quota || log.total_quota)">{{ logQuotaShort(log.quota || log.total_quota) }}</strong></td></tr></tbody></table></div>
              <div v-if="logsTotal > logsPageSize" class="pager">
                <button :disabled="logsPage <= 1 || logsLoading" @click="changeLogsPage(logsPage - 1)">← Trước</button>
                <span>Trang {{ logsPage }} / {{ logsTotalPages }}</span>
                <button :disabled="logsPage >= logsTotalPages || logsLoading" @click="changeLogsPage(logsPage + 1)">Sau →</button>
              </div>
            </section>

            <!-- Grant quota dialog -->
            <div v-if="grantDialogVisible" class="modal-overlay" @click.self="closeGrantDialog">
              <div class="modal-dialog" role="dialog" aria-modal="true" aria-label="Cấp thêm hạn mức">
                <div class="modal-head">
                  <span class="eyebrow">Cấp thêm</span>
                  <h2>{{ grantUser?.username || 'Người dùng' }}</h2>
                  <button class="modal-close" @click="closeGrantDialog" aria-label="Đóng">✕</button>
                </div>
                <div class="modal-body">
                  <div v-if="grantUser" class="grant-info">
                    <p><strong>Hạn mức còn lại:</strong> {{ formatNumber(grantUser.amount_left) }}</p>
                    <p><strong>Đã cấp thêm hôm nay:</strong> {{ formatNumber(grantUser.daily_extra_quota) || '0' }}</p>
                  </div>
                  <label class="modal-field">
                    Số lượng cấp thêm
                    <input v-model.number="grantAmount" type="number" min="1" placeholder="Nhập số lượng…" />
                  </label>
                  <button class="modal-send" @click="submitGrant" :disabled="grantLoading || !grantAmount || grantAmount <= 0">
                    {{ grantLoading ? 'Đang cấp…' : 'Xác nhận cấp thêm' }}
                  </button>
                  <div v-if="grantResult" class="modal-result grant-result">
                    <strong>Kết quả:</strong>
                    <p>Đã cấp <strong>{{ formatNumber(grantResult.grantedAmount) }}</strong> cho <strong>{{ grantResult.username }}</strong></p>
                    <p>Hạn mức còn lại: <strong>{{ formatNumber(grantResult.amountLeft) }}</strong></p>
                  </div>
                </div>
              </div>
            </div>

            <!-- Test dialog -->
            <div v-if="testDialogVisible" class="modal-overlay" @click.self="closeTestDialog">
              <div class="modal-dialog" role="dialog" aria-modal="true" aria-label="Kiểm tra mô hình">
                <div class="modal-head">
                  <span class="eyebrow">Kiểm tra</span>
                  <h2>{{ testDialogModel }}</h2>
                  <button class="modal-close" @click="closeTestDialog" aria-label="Đóng">✕</button>
                </div>
                <div class="modal-body">
                  <label class="modal-field">
                    Prompt
                    <textarea v-model="testPrompt" rows="4" placeholder="Nhập prompt…"></textarea>
                  </label>
                  <button class="modal-send" @click="sendTestRequest" :disabled="testLoading || !testPrompt.trim()">
                    {{ testLoading ? 'Đang gửi…' : 'Gửi yêu cầu' }}
                  </button>
                  <div v-if="testResult" class="modal-result">
                    <strong>Kết quả:</strong>
                    <pre>{{ testResult }}</pre>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </main>
      </div>
    </section>
  </main>
</template>
