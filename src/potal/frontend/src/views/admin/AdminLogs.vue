<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import {
	IconChevronLeft,
	IconChevronRight,
	IconRefresh,
	IconSearch,
	IconTrash,
} from "@tabler/icons-vue";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
	Card,
	CardContent,
	CardDescription,
	CardHeader,
	CardTitle,
} from "@/components/ui/card";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
	Select,
	SelectContent,
	SelectItem,
	SelectTrigger,
	SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import {
	Table,
	TableBody,
	TableCell,
	TableEmpty,
	TableHead,
	TableHeader,
	TableRow,
} from "@/components/ui/table";
import { useAuth } from "@/composables/useAuth";
import {
	formatDateTime,
	formatNumber,
	formatResponseTime,
	formatCredit,
	todayISODate,
} from "@/lib/format";
import {
	ApiError,
	deleteAdminLogs,
	getAdminLogs,
	getAdminLogsStats,
	getLogRetention,
	setLogRetention,
} from "@/services/api";
import type {
	AdminLogParams,
	AdminLogStatsResponse,
	DeleteLogsParams,
	LogRow,
} from "@/services/api";

const { t } = useI18n();
const { adminToken } = useAuth();

const pageSize = 20;
const loading = ref(false);
const logs = ref<LogRow[]>([]);
const total = ref(0);
const page = ref(1);
const usernameFilter = ref("");
const modelFilter = ref("");
const statusFilter = ref<"all" | "success" | "error">("all");
const fromDate = ref(todayISODate());
const toDate = ref(todayISODate());
const stats = ref<AdminLogStatsResponse | null>(null);

const modelChartRows = computed(() =>
	(stats.value?.byModel ?? []).map((row) => ({
		model: String(row.model || "—"),
		count: Number(row.req_count ?? 0),
		tokensIn: Number(row.tokens_in ?? 0),
		tokensOut: Number(row.tokens_out ?? 0),
		quota: Number(row.total_quota ?? 0),
	})),
);
const maxModelTokens = computed(() =>
	Math.max(
		1,
		...modelChartRows.value.map((row) => row.tokensIn + row.tokensOut),
	),
);

const statusBreakdown = computed(() => {
	const total = Number(stats.value?.totals?.req_count ?? 0);
	const error = Number(stats.value?.totals?.error_count ?? 0);
	const success = Math.max(0, total - error);
	const denom = total > 0 ? total : 1;
	const successPct = (success / denom) * 100;
	const errorPct = (error / denom) * 100;
	return {
		success,
		error,
		total,
		successPct,
		errorPct,
		gradient: `conic-gradient(rgb(34 197 94) 0% ${successPct}%, rgb(239 68 68) ${successPct}% 100%)`,
	};
});

const pageCount = computed(() =>
	Math.max(1, Math.ceil(total.value / pageSize)),
);
const pageLabel = computed(
	() => `${t("common.page")} ${page.value} / ${pageCount.value}`,
);

function errorMessage(err: unknown): string {
	return err instanceof ApiError ? err.message : t("common.error");
}

function dateToUnixSeconds(
	value: string,
	endOfDay: boolean,
): number | undefined {
	if (!value) return undefined;
	const suffix = endOfDay ? "T23:59:59" : "T00:00:00";
	const time = new Date(`${value}${suffix}`).getTime();
	return Number.isNaN(time) ? undefined : Math.floor(time / 1000);
}

function buildParams(): AdminLogParams {
	return {
		page: page.value,
		size: pageSize,
		username: usernameFilter.value.trim() || undefined,
		modelName: modelFilter.value.trim() || undefined,
		status: statusFilter.value === "all" ? "" : statusFilter.value,
		startTime: dateToUnixSeconds(fromDate.value, false),
		endTime: dateToUnixSeconds(toDate.value, true),
	};
}

async function fetchLogs() {
	loading.value = true;
	try {
		const params = buildParams();
		const [response, statsRes] = await Promise.all([
			getAdminLogs(adminToken.value, params),
			getAdminLogsStats(adminToken.value, {
				username: params.username,
				modelName: params.modelName,
				startTime: params.startTime,
				endTime: params.endTime,
			}),
		]);
		logs.value = response.items;
		total.value = response.total;
		page.value = response.page || page.value;
		stats.value = statsRes;
	} catch (err) {
		toast.error(errorMessage(err));
	} finally {
		loading.value = false;
	}
}

function applyFilters() {
	page.value = 1;
	fetchLogs();
}

function resetFilters() {
	usernameFilter.value = "";
	modelFilter.value = "";
	statusFilter.value = "all";
	fromDate.value = todayISODate();
	toDate.value = todayISODate();
	page.value = 1;
	fetchLogs();
}

function nextPage() {
	if (page.value >= pageCount.value) return;
	page.value += 1;
	fetchLogs();
}

function prevPage() {
	if (page.value <= 1) return;
	page.value -= 1;
	fetchLogs();
}

function otherDetails(row: LogRow): Record<string, unknown> {
	if (!row.other) return {};
	try {
		const parsed = JSON.parse(row.other);
		return parsed && typeof parsed === "object" ? parsed : {};
	} catch {
		return {};
	}
}

function detailValue(row: LogRow, key: string): string {
	const value = otherDetails(row)[key];
	return value === undefined || value === null || value === ""
		? "—"
		: String(value);
}

function typeLabel(row: LogRow): string {
	return Number(row.type) === 2 ? "Consume" : String(row.type ?? "—");
}

function userColor(name: unknown): string {
	const palette = [
		"bg-emerald-600",
		"bg-violet-600",
		"bg-sky-600",
		"bg-amber-600",
		"bg-rose-600",
		"bg-cyan-600",
		"bg-fuchsia-600",
		"bg-lime-600",
	];
	const value = String(name || "?");
	const hash = [...value].reduce((sum, char) => sum + char.charCodeAt(0), 0);
	return palette[hash % palette.length];
}

function thinkingColor(level: unknown): string {
	const colors: Record<string, string> = {
		low: "border-emerald-400/40 bg-emerald-500/15 text-emerald-200",
		medium: "border-sky-400/40 bg-sky-500/15 text-sky-200",
		high: "border-amber-400/40 bg-amber-500/15 text-amber-200",
		xhigh: "border-rose-400/40 bg-rose-500/15 text-rose-200",
	};
	return (
		colors[String(level).toLowerCase()] ||
		"border-slate-400/40 bg-slate-500/15 text-slate-200"
	);
}

function modelColor(model: unknown): string {
	const name = String(model || "").toLowerCase();
	if (name.includes("luna"))
		return "bg-violet-500/20 text-violet-200 border-violet-400/40";
	if (name.includes("terra"))
		return "bg-sky-500/20 text-sky-200 border-sky-400/40";
	if (name.includes("sol"))
		return "bg-amber-500/20 text-amber-200 border-amber-400/40";
	if (name.includes("claude") || name.includes("opus"))
		return "bg-rose-500/20 text-rose-200 border-rose-400/40";
	return "bg-slate-500/20 text-slate-200 border-slate-400/40";
}

// ---- retention config ----
const retentionDays = ref(0);
const retentionOptions = ref<number[]>([0, 7, 30, 90, 180, 365]);
const retentionSaving = ref(false);

function retentionLabel(days: number): string {
	return days === 0
		? t("admin.logs.retentionForever")
		: t("admin.logs.retentionDays", { days });
}

async function fetchRetention() {
	try {
		const res = await getLogRetention(adminToken.value);
		retentionDays.value = res.retentionDays;
		if (Array.isArray(res.options) && res.options.length)
			retentionOptions.value = res.options;
	} catch {
		// non-fatal; keep defaults
	}
}

async function changeRetention(value: unknown) {
	const days = Number(value);
	if (!Number.isFinite(days)) return;
	retentionSaving.value = true;
	try {
		await setLogRetention(adminToken.value, days);
		retentionDays.value = days;
		toast.success(t("admin.logs.retentionSaved"));
	} catch (err) {
		toast.error(t("admin.logs.retentionError"), {
			description: errorMessage(err),
		});
	} finally {
		retentionSaving.value = false;
	}
}

// ---- delete logs ----
const deleteDialogOpen = ref(false);
const deleteScope = ref<"filter" | "olderThan" | "all">("filter");
const deleteOlderThanDays = ref("30");
const deleting = ref(false);

function openDeleteDialog() {
	deleteScope.value = "filter";
	deleteOlderThanDays.value = "30";
	deleteDialogOpen.value = true;
}

async function confirmDelete() {
	deleting.value = true;
	try {
		let params: DeleteLogsParams;
		if (deleteScope.value === "all") {
			params = { all: true };
		} else if (deleteScope.value === "olderThan") {
			const days = Math.max(
				1,
				Math.floor(Number(deleteOlderThanDays.value) || 0),
			);
			params = { olderThanDays: days };
		} else {
			const base = buildParams();
			params = {
				modelName: base.modelName,
				status: base.status,
				startTime: base.startTime,
				endTime: base.endTime,
			};
		}
		const res = await deleteAdminLogs(adminToken.value, params);
		toast.success(
			t("admin.logs.deleteSuccess", { count: formatNumber(res.deleted) }),
		);
		deleteDialogOpen.value = false;
		page.value = 1;
		await fetchLogs();
	} catch (err) {
		toast.error(t("admin.logs.deleteError"), {
			description: errorMessage(err),
		});
	} finally {
		deleting.value = false;
	}
}

onMounted(() => {
	fetchLogs();
	fetchRetention();
});
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
      <div class="flex flex-col gap-1">
        <h1 class="text-xl font-semibold tracking-tight sm:text-2xl">{{ t('admin.logs.title') }}</h1>
        <p class="text-sm text-muted-foreground">{{ t('common.total') }}: {{ formatNumber(total) }}</p>
      </div>
      <div class="flex flex-col gap-2 sm:flex-row sm:items-center">
        <div class="flex items-center gap-2">
          <span class="whitespace-nowrap text-sm text-muted-foreground">{{ t('admin.logs.retentionLabel') }}</span>
          <Select :model-value="String(retentionDays)" :disabled="retentionSaving" @update:model-value="changeRetention">
            <SelectTrigger class="w-40">
              <SelectValue :placeholder="retentionLabel(retentionDays)" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem v-for="opt in retentionOptions" :key="opt" :value="String(opt)">
                {{ retentionLabel(opt) }}
              </SelectItem>
            </SelectContent>
          </Select>
        </div>
        <Button variant="destructive" @click="openDeleteDialog">
          <IconTrash class="size-4" />
          {{ t('admin.logs.deleteLogs') }}
        </Button>
      </div>
    </div>

    <Card>
      <CardHeader>
        <CardTitle>{{ t('common.search') }}</CardTitle>
        <CardDescription>{{ t('admin.logs.filterStatus') }}</CardDescription>
      </CardHeader>
      <CardContent>
        <form class="grid gap-4 md:grid-cols-2 xl:grid-cols-6" @submit.prevent="applyFilters">
          <Input v-model="usernameFilter" :placeholder="t('admin.logs.filterUser')" />
          <Input v-model="modelFilter" :placeholder="t('admin.logs.filterModel')" />
          <Select v-model="statusFilter">
            <SelectTrigger class="w-full">
              <SelectValue :placeholder="t('admin.logs.filterStatus')" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">{{ t('admin.logs.statusAll') }}</SelectItem>
              <SelectItem value="success">{{ t('admin.logs.statusSuccess') }}</SelectItem>
              <SelectItem value="error">{{ t('admin.logs.statusError') }}</SelectItem>
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
        <CardTitle class="text-base">{{ t('admin.logs.statsTitle') }}</CardTitle>
        <CardDescription>{{ t('admin.logs.statsHint') }}</CardDescription>
      </CardHeader>
      <CardContent>
        <div class="grid gap-8 lg:grid-cols-2">
          <!-- Success / error rate -->
          <div class="flex flex-col gap-3">
            <h3 class="text-sm font-medium">{{ t('admin.logs.statusChart') }}</h3>
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
                :aria-label="`${t('admin.logs.statusSuccess')} ${statusBreakdown.successPct.toFixed(1)}%, ${t('admin.logs.statusError')} ${statusBreakdown.errorPct.toFixed(1)}%`"
              >
                <div class="absolute inset-[22%] flex flex-col items-center justify-center rounded-full bg-background">
                  <span class="text-lg font-semibold tabular-nums">{{ statusBreakdown.successPct.toFixed(0) }}%</span>
                  <span class="text-xs text-muted-foreground">{{ t('admin.logs.statusSuccess') }}</span>
                </div>
              </div>
              <ul class="flex flex-1 flex-col gap-3 text-sm">
                <li class="flex items-center justify-between gap-3">
                  <span class="flex items-center gap-2">
                    <span class="size-3 rounded-full" style="background: rgb(34 197 94)" />
                    {{ t('admin.logs.statusSuccess') }}
                  </span>
                  <span class="tabular-nums text-muted-foreground">
                    {{ formatNumber(statusBreakdown.success) }} ({{ statusBreakdown.successPct.toFixed(1) }}%)
                  </span>
                </li>
                <li class="flex items-center justify-between gap-3">
                  <span class="flex items-center gap-2">
                    <span class="size-3 rounded-full" style="background: rgb(239 68 68)" />
                    {{ t('admin.logs.statusError') }}
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
            <h3 class="text-sm font-medium">{{ t('admin.logs.modelRequests') }}</h3>
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
                    {{ formatNumber(row.count) }} {{ t('admin.overview.totalRequests') }}
                    <span class="mx-1">·</span>
                    {{ t('admin.logs.tokensIn') }}: {{ formatNumber(row.tokensIn) }}
                    <span class="mx-1">·</span>
                    {{ t('admin.logs.tokensOut') }}: {{ formatNumber(row.tokensOut) }}
                    <span class="mx-1">·</span>
                    {{ formatCredit(row.quota) }} {{ t('admin.logs.creditLabel') }}
                  </span>
                </div>
                <div class="h-2.5 w-full overflow-hidden rounded-full bg-muted">
                  <div
                    v-if="row.tokensIn + row.tokensOut > 0"
                    class="flex h-full overflow-hidden rounded-full"
                    :style="{ width: `${Math.max(4, ((row.tokensIn + row.tokensOut) / maxModelTokens) * 100)}%` }"
                  >
                    <div
                      class="h-full bg-primary"
                      :style="{ width: `${(row.tokensIn / (row.tokensIn + row.tokensOut)) * 100}%` }"
                    />
                    <div
                      class="h-full bg-chart-2"
                      :style="{ width: `${(row.tokensOut / (row.tokensIn + row.tokensOut)) * 100}%` }"
                    />
                  </div>
                  <div v-else class="h-full w-[4%] rounded-full bg-muted-foreground/30" />
                </div>
              </li>
            </ul>
          </div>
        </div>
      </CardContent>
    </Card>

    <Card>
      <CardHeader>
        <CardTitle>{{ t('admin.nav.logs') }}</CardTitle>
        <CardDescription>{{ pageLabel }}</CardDescription>
      </CardHeader>
      <CardContent class="flex flex-col gap-4">
        <div class="overflow-x-auto rounded-lg border bg-card/40">
          <Table class="min-w-[1500px]">
            <TableHeader><TableRow>
              <TableHead>{{ t('admin.logs.time') }}</TableHead>
              <TableHead>{{ t('admin.logs.channel') }}</TableHead>
              <TableHead>{{ t('admin.logs.user') }}</TableHead>
              <TableHead>{{ t('admin.logs.tokens') }}</TableHead>
              <TableHead>{{ t('admin.logs.group') }}</TableHead>
              <TableHead>{{ t('admin.logs.type') }}</TableHead>
              <TableHead>{{ t('admin.logs.model') }}</TableHead>
              <TableHead>{{ t('admin.logs.thinking') }}</TableHead>
              <TableHead>{{ t('admin.logs.responseTime') }}</TableHead>
              <TableHead class="text-right">{{ t('admin.logs.tokensIn') }}</TableHead>
              <TableHead class="text-right">{{ t('admin.logs.tokensOut') }}</TableHead>
              <TableHead>{{ t('admin.logs.spend') }}</TableHead>
              <TableHead>{{ t('admin.logs.details') }}</TableHead>
            </TableRow></TableHeader>
            <TableBody>
              <TableEmpty v-if="!loading && !logs.length" :colspan="12" class="text-muted-foreground">{{ t('common.noData') }}</TableEmpty>
              <template v-for="row in logs" v-else :key="String(row.id ?? row.request_id ?? `${row.created_at}-${row.model_name}`)">
                <TableRow class="align-middle">
                  <TableCell class="whitespace-nowrap text-xs text-muted-foreground">{{ formatDateTime(row.created_at) }}</TableCell>
                  <TableCell><Badge variant="secondary">{{ row.channel_name || '—' }}</Badge></TableCell>
                  <TableCell><div class="flex items-center gap-2 font-medium"><span class="flex size-6 items-center justify-center rounded-full text-xs text-white" :class="userColor(row.username)">{{ String(row.username || '?').slice(0, 1).toUpperCase() }}</span>{{ row.username || '—' }}</div></TableCell>
                  <TableCell><Badge variant="outline" class="font-mono text-xs">{{ row.token_name || '—' }}</Badge></TableCell>
                  <TableCell><Badge variant="secondary">{{ detailValue(row, 'group') === '—' ? 'default' : detailValue(row, 'group') }}</Badge></TableCell>
                  <TableCell><Badge variant="outline">{{ typeLabel(row) }}</Badge></TableCell>
                  <TableCell><div class="flex items-center gap-2"><Badge variant="outline" class="font-mono" :class="modelColor(row.model_name)">{{ row.model_name || '—' }}</Badge></div></TableCell>
                  <TableCell><Badge v-if="row.reasoning_effort" variant="outline" :class="thinkingColor(row.reasoning_effort)">{{ row.reasoning_effort }}</Badge><span v-else class="text-muted-foreground">—</span></TableCell>
                  <TableCell class="whitespace-nowrap"><div class="flex gap-1 text-xs tabular-nums"><Badge variant="secondary">{{ formatResponseTime(row.use_time) }}</Badge><Badge variant="outline">{{ row.is_stream ? 'stream' : '—' }}</Badge></div></TableCell>
                  <TableCell class="text-right tabular-nums">{{ formatNumber(row.prompt_tokens) }}</TableCell>
                  <TableCell class="text-right tabular-nums">{{ formatNumber(row.completion_tokens) }}</TableCell>
                  <TableCell class="whitespace-nowrap font-medium tabular-nums text-destructive">-{{ formatCredit(row.quota) }} cr</TableCell>
                  <TableCell class="min-w-64 text-xs text-muted-foreground"><div>Group ratio {{ detailValue(row, 'group_ratio') }}x</div><div>Input {{ detailValue(row, 'input_rate') }} / 1M tokens</div><div>Completion {{ detailValue(row, 'output_rate') }} / 1M tokens</div></TableCell>
                </TableRow>
              </template>
            </TableBody>
          </Table>
        </div>

        <div class="flex items-center justify-between gap-4">
          <p class="text-sm text-muted-foreground">{{ pageLabel }}</p>
          <div class="flex items-center gap-2">
            <Button variant="outline" size="sm" :disabled="loading || page <= 1" @click="prevPage">
              <IconChevronLeft class="size-4" />
              {{ t('common.prev') }}
            </Button>
            <Button variant="outline" size="sm" :disabled="loading || page >= pageCount" @click="nextPage">
              {{ t('common.next') }}
              <IconChevronRight class="size-4" />
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>

    <Dialog v-model:open="deleteDialogOpen">
      <DialogContent>
        <form class="grid gap-4" @submit.prevent="confirmDelete">
          <DialogHeader>
            <DialogTitle>{{ t('admin.logs.deleteTitle') }}</DialogTitle>
            <DialogDescription>{{ t('admin.logs.deleteDescription') }}</DialogDescription>
          </DialogHeader>

          <div class="grid gap-2">
            <Label>{{ t('admin.logs.deleteScope') }}</Label>
            <Select v-model="deleteScope">
              <SelectTrigger class="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="filter">{{ t('admin.logs.deleteByFilter') }}</SelectItem>
                <SelectItem value="olderThan">{{ t('admin.logs.deleteOlderThan') }}</SelectItem>
                <SelectItem value="all">{{ t('admin.logs.deleteAll') }}</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div v-if="deleteScope === 'olderThan'" class="grid gap-2">
            <Label for="delete-older-days">{{ t('admin.logs.deleteDays') }}</Label>
            <Input id="delete-older-days" v-model="deleteOlderThanDays" type="number" min="1" step="1" inputmode="numeric" />
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" @click="deleteDialogOpen = false">{{ t('common.cancel') }}</Button>
            <Button type="submit" variant="destructive" :disabled="deleting">
              {{ deleting ? t('common.loading') : t('admin.logs.deleteConfirm') }}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  </div>
</template>
