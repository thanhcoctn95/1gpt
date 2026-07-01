export type ApiEnvelope<T> = { success: boolean; data: T; message?: string };
export type HealthResponse = {
  success: boolean;
  service: string;
  newApiBaseUrl: string;
  newApiPublicBaseUrl?: string;
  time: string;
};
export type PortalConfig = {
  newApiBaseUrl: string;
  newApiPublicBaseUrl: string;
  openAiBaseUrl: string;
};
export type DashboardMe = {
  user: Record<string, unknown>;
  subscriptions: Array<Record<string, unknown>>;
  stats24h: Record<string, unknown>;
};
export type ModelRow = {
  model_name: string;
  description: string;
  icon: string;
  status: number;
};

export type ModelRatioRow = {
  model_name: string;
  model_ratio: number;
  completion_ratio: number;
};

export type GroupRatioRow = {
  name: string;
  group_ratio: number;
};

export type ModelRatiosResponse = {
  models: ModelRatioRow[];
  groups: GroupRatioRow[];
};
export type ClaudeOpusUsage = {
  active: boolean;
  limit: number;
  used: number;
  remaining: number;
  unlimited?: boolean;
};
export type LogRow = Record<string, unknown>;
export type TokenRow = Record<string, unknown> & {
  id: number;
  model_limits?: string;
  model_limits_enabled?: boolean;
  status?: number;
  group?: string;
  unlimited_quota?: boolean;
};

export type AdminPlanRow = Record<string, unknown> & {
  id: number;
  title: string;
  subtitle?: string;
  price_amount?: number;
  total_amount?: number;
  quota_reset_period?: string;
  upgrade_group?: string;
  sort_order?: number;
  enabled?: boolean;
  model_list?: string | null;
};
export type ProvisionedUserRow = Record<string, unknown> & {
  user_id: number;
  username: string;
  token_id?: number;
  token_name?: string;
  key_masked?: string;
  plan_title?: string;
  amount_total?: number;
  amount_used?: number;
  daily_extra_quota?: number;
  amount_left?: number;
  quota_reset_period?: string;
  start_time?: string;
  end_time?: string;
  last_reset_time?: string;
  next_reset_time?: string;
};

export type DailyExtraQuotaResult = {
  userId: number;
  username: string;
  subscriptionId: number;
  grantedAmount: number;
  dailyExtraQuota: number;
  amountTotal: number;
  amountUsed: number;
  amountLeft: number;
  planType?: string;
};
export type AdminLoginResult = {
  adminToken: string;
  tokenMasked: string;
  user: { id: number; username: string; displayName?: string; role: number };
};

export type ProvisionResult = {
  userId: number;
  username: string;
  planId: number;
  planTitle: string;
  subscriptionId: number;
  planType?: string;
};

export type UserTokenResult = {
  userId: number;
  username: string;
  tokenId: number;
  tokenName: string;
  apiKey: string;
  keyMasked: string;
  baseUrl: string;
};

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(path, init);
  const json = await response.json();
  if (!response.ok || json.success === false)
    throw new Error(json.message || `Request failed: ${response.status}`);
  return json.data ?? json;
}

function authHeaders(apiKey: string): HeadersInit {
  return {
    authorization: `Bearer ${apiKey}`,
    "content-type": "application/json",
  };
}

export async function loginAdmin(payload: {
  username: string;
  password: string;
}): Promise<AdminLoginResult> {
  return request<AdminLoginResult>("/api/admin/login", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload),
  });
}

export async function getHealth(): Promise<HealthResponse> {
  return request<HealthResponse>("/api/health");
}
export async function getPortalConfig(): Promise<PortalConfig> {
  return request<PortalConfig>("/api/config");
}
export async function getDashboardMe(apiKey: string): Promise<DashboardMe> {
  return request<DashboardMe>("/api/dashboard/me", {
    headers: authHeaders(apiKey),
  });
}
export async function getDashboardModels(apiKey: string): Promise<ModelRow[]> {
  return request<ModelRow[]>("/api/dashboard/models", {
    headers: authHeaders(apiKey),
  });
}
export async function getModelRatios(apiKey: string): Promise<ModelRatiosResponse> {
  return request<ModelRatiosResponse>("/api/dashboard/model-ratios", {
    headers: authHeaders(apiKey),
  });
}
export async function getClaudeOpusUsage(apiKey: string): Promise<ClaudeOpusUsage> {
  return request<ClaudeOpusUsage>("/api/dashboard/claude-opus-usage", {
    headers: authHeaders(apiKey),
  });
}
export async function getDashboardLogs(
  apiKey: string,
  params: { page?: number; size?: number } = {},
): Promise<{ page: number; size: number; total: number; items: LogRow[] }> {
  const search = new URLSearchParams();
  if (params.page) search.set("page", String(params.page));
  if (params.size) search.set("size", String(params.size));
  const query = search.toString();
  return request<{
    page: number;
    size: number;
    total: number;
    items: LogRow[];
  }>(`/api/dashboard/logs${query ? `?${query}` : ""}`, {
    headers: authHeaders(apiKey),
  });
}
export async function testDashboard(
  apiKey: string,
  payload: { model: string; prompt: string; maxTokens: number },
): Promise<unknown> {
  return request<unknown>("/api/dashboard/test", {
    method: "POST",
    headers: authHeaders(apiKey),
    body: JSON.stringify(payload),
  });
}
export async function getAvailableModels(apiKey: string): Promise<Array<{ model_name: string }>> {
  return request<Array<{ model_name: string }>>("/api/admin/models/available", {
    headers: authHeaders(apiKey),
  });
}
export async function getUserTokens(apiKey: string, userId: number): Promise<TokenRow[]> {
  return request<TokenRow[]>(`/api/users/${userId}/tokens`, {
    headers: authHeaders(apiKey),
  });
}
export async function updateTokenLimits(
  apiKey: string,
  tokenId: number,
  payload: Record<string, unknown>,
): Promise<unknown> {
  return request<unknown>(`/api/tokens/${tokenId}/model-limits`, {
    method: "PATCH",
    headers: authHeaders(apiKey),
    body: JSON.stringify(payload),
  });
}

export async function applyPricingPlan(
  apiKey: string,
  plan: string,
): Promise<{ message?: string; subscription?: Record<string, unknown> }> {
  return request<{ message?: string; subscription?: Record<string, unknown> }>(
    "/api/pricing/apply",
    {
      method: "POST",
      headers: authHeaders(apiKey),
      body: JSON.stringify({ plan }),
    },
  );
}

export async function getAdminPlans(apiKey: string): Promise<AdminPlanRow[]> {
  return request<AdminPlanRow[]>("/api/admin/plans", {
    headers: authHeaders(apiKey),
  });
}

export type PlanPayload = {
  title: string;
  subtitle?: string;
  priceAmount: number;
  totalAmount: number;
  quotaResetPeriod: "daily" | "never";
  upgradeGroup?: string;
  sortOrder?: number;
  modelList?: string | null;
};

export async function createPlan(
  apiKey: string,
  payload: PlanPayload,
): Promise<{ planId: number; title: string; quotaResetPeriod: string }> {
  return request<{ planId: number; title: string; quotaResetPeriod: string }>(
    "/api/admin/plans/create",
    {
      method: "POST",
      headers: authHeaders(apiKey),
      body: JSON.stringify(payload),
    },
  );
}

export async function updatePlan(
  apiKey: string,
  planId: number,
  payload: PlanPayload,
): Promise<{ planId: number; title: string; quotaResetPeriod: string }> {
  return request<{ planId: number; title: string; quotaResetPeriod: string }>(
    `/api/admin/plans/${planId}`,
    {
      method: "PUT",
      headers: authHeaders(apiKey),
      body: JSON.stringify(payload),
    },
  );
}

export async function getProvisionedUsers(apiKey: string): Promise<ProvisionedUserRow[]> {
  return request<ProvisionedUserRow[]>("/api/admin/provisioned-users", {
    headers: authHeaders(apiKey),
  });
}

export async function provisionUser(
  apiKey: string,
  payload: { username: string; planId: number },
): Promise<ProvisionResult> {
  return request<ProvisionResult>("/api/admin/provision-user", {
    method: "POST",
    headers: authHeaders(apiKey),
    body: JSON.stringify(payload),
  });
}

export async function getUserToken(
  apiKey: string,
  payload: { userId?: number; username?: string },
): Promise<UserTokenResult> {
  return request<UserTokenResult>("/api/admin/user-token", {
    method: "POST",
    headers: authHeaders(apiKey),
    body: JSON.stringify(payload),
  });
}

export async function getAdminLogs(
  apiKey: string,
  params: {
    page?: number;
    size?: number;
    userId?: number;
    username?: string;
    modelName?: string;
    startTime?: number;
    endTime?: number;
  } = {},
): Promise<{ page: number; size: number; total: number; items: LogRow[] }> {
  const search = new URLSearchParams();
  if (params.page) search.set("page", String(params.page));
  if (params.size) search.set("size", String(params.size));
  if (params.userId) search.set("userId", String(params.userId));
  if (params.username) search.set("username", params.username);
  if (params.modelName) search.set("modelName", params.modelName);
  if (params.startTime) search.set("startTime", String(params.startTime));
  if (params.endTime) search.set("endTime", String(params.endTime));
  const query = search.toString();
  return request<{
    page: number;
    size: number;
    total: number;
    items: LogRow[];
  }>(`/api/admin/logs${query ? `?${query}` : ""}`, {
    headers: authHeaders(apiKey),
  });
}

export type AdminLogStatsModel = {
  model: string;
  req_count: number;
  total_quota: number;
  tokens_in: number;
  tokens_out: number;
  error_count: number;
};
export type AdminLogStatsUser = {
  username: string;
  user_id: number;
  req_count: number;
  total_quota: number;
};
export type AdminLogStatsResponse = {
  totals: {
    req_count: number;
    total_quota: number;
    tokens_in: number;
    tokens_out: number;
    error_count: number;
  };
  byModel: AdminLogStatsModel[];
  byUser: AdminLogStatsUser[];
};

export async function getAdminLogsStats(
  apiKey: string,
  params: {
    userId?: number;
    username?: string;
    modelName?: string;
    startTime?: number;
    endTime?: number;
  } = {},
): Promise<AdminLogStatsResponse> {
  const search = new URLSearchParams();
  if (params.userId) search.set("userId", String(params.userId));
  if (params.username) search.set("username", params.username);
  if (params.modelName) search.set("modelName", params.modelName);
  if (params.startTime) search.set("startTime", String(params.startTime));
  if (params.endTime) search.set("endTime", String(params.endTime));
  const query = search.toString();
  return request<AdminLogStatsResponse>(`/api/admin/logs/stats${query ? `?${query}` : ""}`, {
    headers: authHeaders(apiKey),
  });
}

export async function grantDailyExtraQuota(
  apiKey: string,
  payload: { userId: number; amount: number },
): Promise<DailyExtraQuotaResult> {
  return request<DailyExtraQuotaResult>("/api/admin/grant-daily-extra-quota", {
    method: "POST",
    headers: authHeaders(apiKey),
    body: JSON.stringify(payload),
  });
}

export type AdminModelRow = {
  model_name: string;
  description: string;
  icon: string;
  channels: string;
  status: number;
  has_token_out: boolean;
};
export type AdminModelsResponse = {
  items: AdminModelRow[];
  total: number;
  activeCount: number;
};

export async function getAdminModels(
  apiKey: string,
  options?: { showAll?: boolean },
): Promise<AdminModelsResponse> {
  const params = options?.showAll ? "?showAll=true" : "";
  return request<AdminModelsResponse>("/api/admin/models" + params, {
    headers: authHeaders(apiKey),
  });
}

export async function setModelActive(
  apiKey: string,
  modelName: string,
  active: boolean,
): Promise<{
  modelName: string;
  active: boolean;
  status: number;
  abilitiesUpdated: number;
}> {
  return request<{
    modelName: string;
    active: boolean;
    status: number;
    abilitiesUpdated: number;
  }>(`/api/admin/models/${encodeURIComponent(modelName)}/active`, {
    method: "PATCH",
    headers: authHeaders(apiKey),
    body: JSON.stringify({ active }),
  });
}

export type AdminChannelRow = Record<string, unknown> & {
  id: number;
  name: string;
  status?: number;
  base_url?: string;
  key_masked?: string;
  token_count?: number;
  models?: string;
  group?: string;
  weight?: number;
  priority?: number;
  balance?: number;
  balance_updated_at?: string;
  used_quota?: number;
};

export type AdminChannelCreditResult = {
  channel_id: number;
  name: string;
  base_url: string;
  token_count: number;
  checked_at: string;
  credit_check_success: boolean;
  total_available?: number | null;
  total_used?: number | null;
  daily_cap?: number | null;
  expire_time?: number | null;
  expire_at?: string | null;
  unit?: string;
  unit_divisor?: number;
  checks: Array<Record<string, unknown>>;
};

export async function getAdminChannels(
  apiKey: string,
  params: { q?: string; status?: number | '' } = {},
): Promise<AdminChannelRow[]> {
  const search = new URLSearchParams();
  if (params.q) search.set("q", params.q);
  if (params.status !== undefined && params.status !== '') search.set("status", String(params.status));
  const query = search.toString();
  return request<AdminChannelRow[]>(`/api/admin/channels${query ? `?${query}` : ""}`, {
    headers: authHeaders(apiKey),
  });
}

export async function updateAdminChannel(
  apiKey: string,
  channelId: number,
  payload: Record<string, unknown>,
): Promise<AdminChannelRow> {
  return request<AdminChannelRow>(`/api/admin/channels/${channelId}`, {
    method: "PATCH",
    headers: authHeaders(apiKey),
    body: JSON.stringify(payload),
  });
}

export async function checkAdminChannelCredit(
  apiKey: string,
  channelId: number,
): Promise<AdminChannelCreditResult> {
  return request<AdminChannelCreditResult>(`/api/admin/channels/${channelId}/credit`, {
    method: "POST",
    headers: authHeaders(apiKey),
  });
}

// ---- public plans (no auth, for landing/pricing page) ----

export type PublicPlanRow = {
  id: number;
  title: string;
  subtitle?: string;
  price_amount?: number;
  total_amount?: number;
  quota_reset_period?: string;
  upgrade_group?: string;
  sort_order?: number;
  model_list?: string | null;
  model_count: number;
};

export async function getPublicPlans(): Promise<PublicPlanRow[]> {
  return request<PublicPlanRow[]>("/api/public/plans");
}
