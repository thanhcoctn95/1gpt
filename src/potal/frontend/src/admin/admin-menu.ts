import type { AdminMenuItem } from './types'

export const adminMenuItems = [
  { key: 'dashboard', label: 'Dashboard', desc: 'Tổng quan hệ thống', icon: ['M3 13h8V3H3v10z', 'M13 21h8V11h-8v10z', 'M3 21h8v-6H3v6z', 'M13 9h8V3h-8v6z'] },
  { key: 'users', label: 'Người dùng', desc: 'Danh sách đã provision', icon: ['M9 6h12', 'M9 12h12', 'M9 18h12', 'M4 6h.01', 'M4 12h.01', 'M4 18h.01'] },
  { key: 'plans', label: 'Gói', desc: 'Quản lý gói subscription', icon: ['M20 7L9 18l-5-5'] },
  { key: 'models', label: 'Đồng bộ', desc: 'Đồng bộ & bật/tắt model', icon: ['M21 2v6h-6', 'M3 12a9 9 0 0 1 15-6.7L21 8', 'M3 22v-6h6', 'M21 12a9 9 0 0 1-15 6.7L3 16'] },
  { key: 'channels', label: 'Channels', desc: 'New API channel & VietAPI credit', icon: ['M4 7h16', 'M4 12h16', 'M4 17h16', 'M7 7v10', 'M17 7v10'] },
  { key: 'logs', label: 'Usage Logs', desc: 'Logs sử dụng theo user', icon: ['M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z', 'M14 2v6h6', 'M8 13h8', 'M8 17h8', 'M8 9h2'] },
] as const satisfies readonly AdminMenuItem[]
