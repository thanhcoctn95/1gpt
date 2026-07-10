import type { LogRow } from '@/services/api'
import { isErrorLog } from '@/lib/format'

const USER_PALETTES = [
  {
    avatar: 'bg-violet-600 text-white dark:bg-violet-500',
    panel: 'border-violet-200 bg-violet-50/80 text-violet-950 dark:border-violet-500/30 dark:bg-violet-500/10 dark:text-violet-100',
  },
  {
    avatar: 'bg-sky-600 text-white dark:bg-sky-500',
    panel: 'border-sky-200 bg-sky-50/80 text-sky-950 dark:border-sky-500/30 dark:bg-sky-500/10 dark:text-sky-100',
  },
  {
    avatar: 'bg-emerald-600 text-white dark:bg-emerald-500',
    panel: 'border-emerald-200 bg-emerald-50/80 text-emerald-950 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-100',
  },
  {
    avatar: 'bg-amber-600 text-white dark:bg-amber-500',
    panel: 'border-amber-200 bg-amber-50/80 text-amber-950 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-100',
  },
  {
    avatar: 'bg-rose-600 text-white dark:bg-rose-500',
    panel: 'border-rose-200 bg-rose-50/80 text-rose-950 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-100',
  },
  {
    avatar: 'bg-cyan-600 text-white dark:bg-cyan-500',
    panel: 'border-cyan-200 bg-cyan-50/80 text-cyan-950 dark:border-cyan-500/30 dark:bg-cyan-500/10 dark:text-cyan-100',
  },
]

const MODEL_PALETTES = [
  {
    pill: 'border-emerald-200 bg-emerald-50 text-emerald-800 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-200',
    dot: 'bg-emerald-500',
  },
  {
    pill: 'border-blue-200 bg-blue-50 text-blue-800 dark:border-blue-500/30 dark:bg-blue-500/10 dark:text-blue-200',
    dot: 'bg-blue-500',
  },
  {
    pill: 'border-fuchsia-200 bg-fuchsia-50 text-fuchsia-800 dark:border-fuchsia-500/30 dark:bg-fuchsia-500/10 dark:text-fuchsia-200',
    dot: 'bg-fuchsia-500',
  },
  {
    pill: 'border-orange-200 bg-orange-50 text-orange-800 dark:border-orange-500/30 dark:bg-orange-500/10 dark:text-orange-200',
    dot: 'bg-orange-500',
  },
  {
    pill: 'border-teal-200 bg-teal-50 text-teal-800 dark:border-teal-500/30 dark:bg-teal-500/10 dark:text-teal-200',
    dot: 'bg-teal-500',
  },
  {
    pill: 'border-indigo-200 bg-indigo-50 text-indigo-800 dark:border-indigo-500/30 dark:bg-indigo-500/10 dark:text-indigo-200',
    dot: 'bg-indigo-500',
  },
]

function stableHash(value: unknown): number {
  const text = String(value ?? '').trim() || 'unknown'
  let hash = 0
  for (let i = 0; i < text.length; i += 1) {
    hash = (hash * 31 + text.charCodeAt(i)) >>> 0
  }
  return hash
}

function pick<T>(items: T[], value: unknown): T {
  return items[stableHash(value) % items.length]
}

export function identityInitial(value: unknown): string {
  const text = String(value ?? '').trim()
  return text ? text.slice(0, 1).toUpperCase() : '?'
}

export function userAvatarClass(value: unknown): string {
  return pick(USER_PALETTES, value).avatar
}

export function userPanelClass(value: unknown): string {
  return pick(USER_PALETTES, value).panel
}

export function modelPillClass(value: unknown): string {
  return pick(MODEL_PALETTES, value).pill
}

export function modelDotClass(value: unknown): string {
  return pick(MODEL_PALETTES, value).dot
}

export function requestStatus(row: LogRow): 'success' | 'error' {
  if (row.request_status) return row.request_status === 'error' ? 'error' : 'success'
  return isErrorLog(row) ? 'error' : 'success'
}

export function logRowClass(row: LogRow): string {
  if (requestStatus(row) === 'error') {
    return 'border-l-4 border-l-red-500/80 bg-red-50/30 hover:bg-red-50/70 dark:bg-red-950/10 dark:hover:bg-red-950/25'
  }
  return 'border-l-4 border-l-emerald-500/70 hover:bg-emerald-50/50 dark:hover:bg-emerald-950/20'
}

export function statusBadgeClass(row: LogRow): string {
  if (requestStatus(row) === 'error') {
    return 'border-red-200 bg-red-50 text-red-700 dark:border-red-500/40 dark:bg-red-500/15 dark:text-red-200'
  }
  return 'border-emerald-200 bg-emerald-50 text-emerald-700 dark:border-emerald-500/40 dark:bg-emerald-500/15 dark:text-emerald-200'
}

export function httpStatusBadgeClass(code: unknown): string {
  const status = Number(code ?? 0)
  if (status >= 500) {
    return 'border-rose-200 bg-rose-50 text-rose-700 dark:border-rose-500/40 dark:bg-rose-500/15 dark:text-rose-200'
  }
  if (status >= 400) {
    return 'border-amber-200 bg-amber-50 text-amber-800 dark:border-amber-500/40 dark:bg-amber-500/15 dark:text-amber-200'
  }
  if (status >= 200) {
    return 'border-emerald-200 bg-emerald-50 text-emerald-700 dark:border-emerald-500/40 dark:bg-emerald-500/15 dark:text-emerald-200'
  }
  return 'border-slate-200 bg-slate-50 text-slate-700 dark:border-slate-500/30 dark:bg-slate-500/10 dark:text-slate-200'
}

export function responseTimeBadgeClass(value: unknown): string {
  const seconds = Number(value ?? 0)
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return 'border-slate-200 bg-slate-50 text-slate-700 dark:border-slate-500/30 dark:bg-slate-500/10 dark:text-slate-200'
  }
  if (seconds >= 60) {
    return 'border-red-200 bg-red-50 text-red-700 dark:border-red-500/40 dark:bg-red-500/15 dark:text-red-200'
  }
  if (seconds >= 20) {
    return 'border-amber-200 bg-amber-50 text-amber-800 dark:border-amber-500/40 dark:bg-amber-500/15 dark:text-amber-200'
  }
  return 'border-sky-200 bg-sky-50 text-sky-700 dark:border-sky-500/40 dark:bg-sky-500/15 dark:text-sky-200'
}

export function streamBadgeClass(isStream: unknown): string {
  return isStream
    ? 'border-blue-200 bg-blue-50 text-blue-700 dark:border-blue-500/40 dark:bg-blue-500/15 dark:text-blue-200'
    : 'border-slate-200 bg-slate-50 text-slate-700 dark:border-slate-500/30 dark:bg-slate-500/10 dark:text-slate-200'
}

export const tokenInBadgeClass = 'border-cyan-200 bg-cyan-50 text-cyan-800 dark:border-cyan-500/30 dark:bg-cyan-500/10 dark:text-cyan-200'
export const tokenOutBadgeClass = 'border-indigo-200 bg-indigo-50 text-indigo-800 dark:border-indigo-500/30 dark:bg-indigo-500/10 dark:text-indigo-200'
export const quotaBadgeClass = 'border-purple-200 bg-purple-50 text-purple-800 dark:border-purple-500/30 dark:bg-purple-500/10 dark:text-purple-200'
export const channelBadgeClass = 'border-slate-200 bg-slate-50 text-slate-700 dark:border-slate-500/30 dark:bg-slate-500/10 dark:text-slate-200'
