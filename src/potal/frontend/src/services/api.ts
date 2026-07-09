// API client for the 1API Portal backend (Spring, /api/*).
// User endpoints authenticate with a New API key (Bearer). Admin endpoints
// authenticate with an admin token issued by POST /api/admin/login.

export type ApiEnvelope<T> = { success: boolean; data: T; message?: string }

export type HealthResponse = {
  success: boolean
  service: string
  newApiBaseUrl: string
  newApiPublicBaseUrl?: string
  time: string
}

export type PortalConfig = {
  newApiBaseUrl: string
  newApiPublicBaseUrl: string
  openAiBaseUrl: string
}

export type SubscriptionRow = Record<string, unknown> & {
  id: number
  plan_id?: number
  plan_title?: string
  plan_subtitle?: string
  price_amount?: number
  quota_reset_period?: string
  amount_total?: number
  amount_used?: number
  amount_left?: number
  status?: string
  source?: string
  upgrade_group?: string
  start_time?: string
  end_time?: string
  last_reset_time?: string
  next_reset_time?: string
}

export type DashboardMe = {
  user: Record<string, unknown>
  subscriptions: SubscriptionRow[]
  stats24h: { request_24h?: number; quota_24h?: number } & Record<string, unknown>
}

export type ModelRow = {
  model_name: string
  description: string
  icon: string
  status: number
}

export type ModelRatioRow = {
  model_name: string
  model_ratio: number
  completion_ratio: number
}

export type GroupRatioRow = {
  name: string
  group_ratio: number
}

export type ModelRatiosResponse = {
  models: ModelRatioRow[]
  groups: GroupRatioRow[]
}

export type LogRow = Record<string, unknown> & {
  id?: number
  request_id?: string
  model_name?: string
  type?: number
  prompt_tokens?: number
  completion_tokens?: number
  quota?: number
  use_time?: number
  is_stream?: boolean
  channel_name?: string
  token_id?: number
  token_name?: string
  username?: string
  content?: string
  other?: string
  created_at?: string
  request_status?: 'error' | 'success'
  status_code?: string
  error_message?: string
  error_type?: string
  error_code?: string
  user_id?: number
}

export type LogModelStatRow = {
  model_name: string
  request_count: number
}

export type DashboardLogParams = {
  page?: number
  size?: number
  modelName?: string
  status?: 'error' | 'success' | ''
  startTime?: number
  endTime?: number
}

export type Paginated<T> = { page: number; size: number; total: number; items: T[] }

export type AdminLoginResult = {
  adminToken: string
  tokenMasked: string
  user: { id: number; username: string; displayName?: string; role: number }
}

export type ProvisionedUserRow = Record<string, unknown> & {
  user_id: number
  username: string
  token_id?: number
  token_name?: string
  key_masked?: string
  plan_title?: string
  amount_total?: number
  amount_used?: number
  daily_extra_quota?: number
  amount_left?: number
  quota_reset_period?: string
  start_time?: string
  end_time?: string
  last_reset_time?: string
  next_reset_time?: string
}

export type ProvisionResult = {
  userId: number
  username: string
  planId: number
  planTitle: string
  subscriptionId: number
  planType?: string
}

export type UserTokenResult = {
  userId: number
  username: string
  tokenId: number
  tokenName: string
  apiKey: string
  keyMasked: string
  baseUrl: string
}

export type AdminPlanRow = Record<string, unknown> & {
  id: number
  title: string
  subtitle?: string
  price_amount?: number
  total_amount?: number
  quota_reset_period?: string
  upgrade_group?: string
  sort_order?: number
  enabled?: boolean
  model_list?: string | null
}

export type AdminModelRow = {
  model_name: string
  description: string
  icon: string
  channels: string
  status: number
  has_token_out: boolean
}

export type AdminModelsResponse = {
  items: AdminModelRow[]
  total: number
  activeCount: number
}

export type AdminLogStatsModel = {
  model: string
  req_count: number
  total_quota: number
  tokens_in: number
  tokens_out: number
  error_count: number
}

export type AdminLogStatsUser = {
  username: string
  user_id: number
  req_count: number
  total_quota: number
  error_count: number
}

export type AdminLogStatsErrorType = {
  error_type: string
  error_count: number
}

export type AdminLogStatsResponse = {
  totals: {
    req_count: number
    total_quota: number
    tokens_in: number
    tokens_out: number
    error_count: number
  }
  byModel: AdminLogStatsModel[]
  byUser: AdminLogStatsUser[]
  byErrorType: AdminLogStatsErrorType[]
}

export type PublicPlanRow = {
  id: number
  title: string
  subtitle?: string
  price_amount?: number
  total_amount?: number
  quota_reset_period?: string
  upgrade_group?: string
  sort_order?: number
  model_list?: string | null
  model_count: number
}

export class ApiError extends Error {
  status: number
  constructor(message: string, status: number) {
    super(message)
    this.name = 'ApiError'
    this.status = status
  }
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(path, init)
  let json: any = null
  try {
    json = await response.json()
  } catch {
    json = null
  }
  if (!response.ok || (json && json.success === false)) {
    const message = (json && json.message) || `Request failed: ${response.status}`
    throw new ApiError(message, response.status)
  }
  return (json && 'data' in json ? json.data : json) as T
}

function authHeaders(apiKey: string): HeadersInit {
  return {
    authorization: `Bearer ${apiKey}`,
    'content-type': 'application/json',
  }
}

// ---- health / config (public) ----
export const getHealth = () => request<HealthResponse>('/api/health')
export const getPortalConfig = () => request<PortalConfig>('/api/config')
export const getPublicPlans = () => request<PublicPlanRow[]>('/api/public/plans')

// ---- user dashboard (Bearer API key) ----
export const getDashboardMe = (apiKey: string) =>
  request<DashboardMe>('/api/dashboard/me', { headers: authHeaders(apiKey) })

export const getDashboardModels = (apiKey: string) =>
  request<ModelRow[]>('/api/dashboard/models', { headers: authHeaders(apiKey) })

export const getModelRatios = (apiKey: string) =>
  request<ModelRatiosResponse>('/api/dashboard/model-ratios', { headers: authHeaders(apiKey) })

export function getDashboardLogs(
  apiKey: string,
  params: DashboardLogParams = {},
): Promise<Paginated<LogRow>> {
  const search = new URLSearchParams()
  if (params.page) search.set('page', String(params.page))
  if (params.size) search.set('size', String(params.size))
  if (params.modelName) search.set('modelName', params.modelName)
  if (params.status) search.set('status', params.status)
  if (params.startTime) search.set('startTime', String(params.startTime))
  if (params.endTime) search.set('endTime', String(params.endTime))
  const query = search.toString()
  return request<Paginated<LogRow>>(`/api/dashboard/logs${query ? `?${query}` : ''}`, {
    headers: authHeaders(apiKey),
  })
}

export function getDashboardLogModelStats(
  apiKey: string,
  params: Omit<DashboardLogParams, 'page' | 'size'> = {},
): Promise<LogModelStatRow[]> {
  const search = new URLSearchParams()
  if (params.modelName) search.set('modelName', params.modelName)
  if (params.status) search.set('status', params.status)
  if (params.startTime) search.set('startTime', String(params.startTime))
  if (params.endTime) search.set('endTime', String(params.endTime))
  const query = search.toString()
  return request<LogModelStatRow[]>(`/api/dashboard/logs/model-stats${query ? `?${query}` : ''}`, {
    headers: authHeaders(apiKey),
  })
}

export const testDashboardModel = (
  apiKey: string,
  payload: { model: string; prompt: string; maxTokens: number },
) =>
  request<unknown>('/api/dashboard/test', {
    method: 'POST',
    headers: authHeaders(apiKey),
    body: JSON.stringify(payload),
  })

// ---- admin auth ----
export const loginAdmin = (payload: { username: string; password: string }) =>
  request<AdminLoginResult>('/api/admin/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  })

// ---- admin: users ----
export const getProvisionedUsers = (apiKey: string) =>
  request<ProvisionedUserRow[]>('/api/admin/provisioned-users', { headers: authHeaders(apiKey) })

export const provisionUser = (apiKey: string, payload: { username: string; planId: number }) =>
  request<ProvisionResult>('/api/admin/provision-user', {
    method: 'POST',
    headers: authHeaders(apiKey),
    body: JSON.stringify(payload),
  })

export const getUserToken = (apiKey: string, payload: { userId?: number; username?: string }) =>
  request<UserTokenResult>('/api/admin/user-token', {
    method: 'POST',
    headers: authHeaders(apiKey),
    body: JSON.stringify(payload),
  })

export type GrantTokensResult = {
  userId: number
  username: string
  subscriptionId: number
  grantedAmount: number
  dailyExtraQuota: number
  amountTotal: number
  amountUsed: number
  amountLeft: number
  planType: 'token' | 'monthly'
}

export const grantTokens = (apiKey: string, payload: { userId: number; amount: number }) =>
  request<GrantTokensResult>('/api/admin/grant-daily-extra-quota', {
    method: 'POST',
    headers: authHeaders(apiKey),
    body: JSON.stringify(payload),
  })

export const getAdminPlans = (apiKey: string) =>
  request<AdminPlanRow[]>('/api/admin/plans', { headers: authHeaders(apiKey) })

// ---- admin: models ----
export function getAdminModels(
  apiKey: string,
  options?: { showAll?: boolean },
): Promise<AdminModelsResponse> {
  const params = options?.showAll ? '?showAll=true' : ''
  return request<AdminModelsResponse>('/api/admin/models' + params, {
    headers: authHeaders(apiKey),
  })
}

export const setModelActive = (apiKey: string, modelName: string, active: boolean) =>
  request<{ modelName: string; active: boolean; status: number; abilitiesUpdated: number }>(
    `/api/admin/models/${encodeURIComponent(modelName)}/active`,
    {
      method: 'PATCH',
      headers: authHeaders(apiKey),
      body: JSON.stringify({ active }),
    },
  )

// ---- admin: logs ----
export type AdminLogParams = {
  page?: number
  size?: number
  userId?: number
  username?: string
  modelName?: string
  status?: 'error' | 'success' | ''
  startTime?: number
  endTime?: number
}

function adminLogSearch(params: AdminLogParams): string {
  const search = new URLSearchParams()
  if (params.page) search.set('page', String(params.page))
  if (params.size) search.set('size', String(params.size))
  if (params.userId) search.set('userId', String(params.userId))
  if (params.username) search.set('username', params.username)
  if (params.modelName) search.set('modelName', params.modelName)
  if (params.status) search.set('status', params.status)
  if (params.startTime) search.set('startTime', String(params.startTime))
  if (params.endTime) search.set('endTime', String(params.endTime))
  const query = search.toString()
  return query ? `?${query}` : ''
}

export const getAdminLogs = (apiKey: string, params: AdminLogParams = {}) =>
  request<Paginated<LogRow>>(`/api/admin/logs${adminLogSearch(params)}`, {
    headers: authHeaders(apiKey),
  })

export const getAdminLogsStats = (apiKey: string, params: Omit<AdminLogParams, 'page' | 'size'> = {}) =>
  request<AdminLogStatsResponse>(`/api/admin/logs/stats${adminLogSearch(params)}`, {
    headers: authHeaders(apiKey),
  })

// ---- admin: log retention + deletion ----
export type LogRetentionResponse = { retentionDays: number; options: number[] }

export const getLogRetention = (apiKey: string) =>
  request<LogRetentionResponse>('/api/admin/logs/retention', { headers: authHeaders(apiKey) })

export const setLogRetention = (apiKey: string, retentionDays: number) =>
  request<{ retentionDays: number }>('/api/admin/logs/retention', {
    method: 'PUT',
    headers: authHeaders(apiKey),
    body: JSON.stringify({ retentionDays }),
  })

export type DeleteLogsParams = {
  olderThanDays?: number
  userId?: number
  modelName?: string
  status?: 'error' | 'success' | ''
  startTime?: number
  endTime?: number
  all?: boolean
}

export const deleteAdminLogs = (apiKey: string, params: DeleteLogsParams = {}) => {
  const search = new URLSearchParams()
  if (params.olderThanDays) search.set('olderThanDays', String(params.olderThanDays))
  if (params.userId) search.set('userId', String(params.userId))
  if (params.modelName) search.set('modelName', params.modelName)
  if (params.status) search.set('status', params.status)
  if (params.startTime) search.set('startTime', String(params.startTime))
  if (params.endTime) search.set('endTime', String(params.endTime))
  if (params.all) search.set('all', 'true')
  const query = search.toString()
  return request<{ deleted: number }>(`/api/admin/logs${query ? `?${query}` : ''}`, {
    method: 'DELETE',
    headers: authHeaders(apiKey),
  })
}
