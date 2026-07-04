// New API stores quota in internal units where 500000 units = 1 USD.
export const QUOTA_PER_USD = 500000

export function quotaToUsd(quota: number | undefined | null): number {
  if (!quota || Number.isNaN(quota)) return 0
  return quota / QUOTA_PER_USD
}

export function formatUsd(amount: number | undefined | null, digits = 2): string {
  const value = typeof amount === 'number' && !Number.isNaN(amount) ? amount : 0
  return `$${value.toFixed(digits)}`
}

export function formatQuotaUsd(quota: number | undefined | null, digits = 2): string {
  return formatUsd(quotaToUsd(Number(quota ?? 0)), digits)
}

export function formatNumber(value: number | undefined | null): string {
  const n = typeof value === 'number' && !Number.isNaN(value) ? value : 0
  return new Intl.NumberFormat('en-US').format(n)
}

// Quota units are billed internally. We surface them to admins/users as a plain
// token count instead of a USD amount. 1 quota unit === 1 token here.
export function quotaToTokens(quota: number | undefined | null): number {
  const n = Number(quota ?? 0)
  return Number.isFinite(n) ? Math.round(n) : 0
}

// Format a quota value as a compact token count, e.g. 1234567 -> "1,234,567".
export function formatTokens(quota: number | undefined | null): string {
  return formatNumber(quotaToTokens(quota))
}

// Format New API `use_time` (seconds, sometimes ms) as a human response time.
export function formatResponseTime(value: unknown): string {
  const n = Number(value ?? 0)
  if (!Number.isFinite(n) || n <= 0) return '—'
  const seconds = n > 1000 ? n / 1000 : n
  return seconds >= 10 ? `${seconds.toFixed(0)}s` : `${seconds.toFixed(2)}s`
}

export function formatVnd(amount: number | undefined | null): string {
  const value = typeof amount === 'number' && !Number.isNaN(amount) ? amount : 0
  return new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(value)
}

export function formatDateTime(value: unknown): string {
  if (!value) return '—'
  const date = typeof value === 'number' ? new Date(value * 1000) : new Date(String(value))
  if (Number.isNaN(date.getTime())) return String(value)
  return date.toLocaleString('vi-VN', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  })
}

export function formatDate(value: unknown): string {
  if (!value) return '—'
  const date = typeof value === 'number' ? new Date(value * 1000) : new Date(String(value))
  if (Number.isNaN(date.getTime())) return String(value)
  return date.toLocaleDateString('vi-VN')
}

/**
 * Refund estimate = plan price / 30 days * remaining days.
 * end_time is an ISO timestamp; remaining days are counted from now.
 */
export function computeRefund(priceAmount: number | undefined | null, endTime: unknown): {
  refund: number
  daysLeft: number
} {
  const price = typeof priceAmount === 'number' && !Number.isNaN(priceAmount) ? priceAmount : 0
  if (!endTime) return { refund: 0, daysLeft: 0 }
  const end = new Date(String(endTime)).getTime()
  if (Number.isNaN(end)) return { refund: 0, daysLeft: 0 }
  const msLeft = end - Date.now()
  const daysLeft = Math.max(0, Math.ceil(msLeft / (1000 * 60 * 60 * 24)))
  const refund = (price / 30) * daysLeft
  return { refund, daysLeft }
}

export function maskKey(key: string | undefined | null): string {
  if (!key) return '—'
  if (key.length <= 12) return key
  return `${key.slice(0, 6)}…${key.slice(-4)}`
}

/** New API log types: 1 = topup, 2 = consume/success, 5 = error (varies). */
export function isErrorLog(row: { type?: unknown; content?: unknown }): boolean {
  const t = Number(row?.type ?? 0)
  // In New API, type=2 is a normal consumption log. Errors are surfaced via
  // content/other. Treat type>=4 or presence of error markers as errors.
  if (t >= 4) return true
  const content = String(row?.content ?? '').toLowerCase()
  return content.includes('error') || content.includes('fail')
}
