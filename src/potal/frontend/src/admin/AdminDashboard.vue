<script setup lang="ts">
import type { AdminMenuKey } from './types'

defineProps<{
  adminStats: {
    totalUsers: number
    activeSubs: number
    totalQuota: number
    extraToday: number
  }
  topUsersByUsage: Array<Record<string, unknown>>
  adminClock: string
  fmt: (value: unknown) => string
}>()

const emit = defineEmits<{
  'set-menu': [value: AdminMenuKey]
  'open-create-user': []
}>()
</script>

<template>
  <div class="admin-dashboard admin-app-page-panel fitness-reveal">
    <section class="admin-overview-card" aria-labelledby="admin-overview-title">
      <div class="admin-overview-copy">
        <span class="admin-page-kicker">OPERATIONS OVERVIEW</span>
        <h2 id="admin-overview-title">1API Admin Dashboard</h2>
        <p>Operate users, quota, channels and API activity from a single AppShell dashboard with fast scanning and clear priority.</p>
      </div>
      <div class="admin-overview-meta" aria-label="Thời gian local">
        <span>Local time</span>
        <strong>{{ adminClock }}</strong>
      </div>
    </section>

    <section class="admin-metric-list" aria-label="Chỉ số vận hành">
      <button class="admin-metric-row" @click="emit('set-menu', 'users')">
        <span class="admin-metric-label">Tổng user</span>
        <strong>{{ fmt(adminStats.totalUsers) }}</strong>
        <small>Xem danh sách</small>
      </button>
      <button class="admin-metric-row" @click="emit('set-menu', 'users')">
        <span class="admin-metric-label">Gói active</span>
        <strong>{{ fmt(adminStats.activeSubs) }}</strong>
        <small>Đang chạy</small>
      </button>
      <button class="admin-metric-row" @click="emit('set-menu', 'logs')">
        <span class="admin-metric-label">Tổng quota cấp</span>
        <strong>{{ fmt(adminStats.totalQuota) }}</strong>
        <small>Xem logs</small>
      </button>
      <button class="admin-metric-row" @click="emit('set-menu', 'users')">
        <span class="admin-metric-label">Extra hôm nay</span>
        <strong>{{ fmt(adminStats.extraToday) }}</strong>
        <small>Quota bổ sung</small>
      </button>
    </section>

    <div class="pika-dashboard-grid">
      <section class="admin-workspace-card pika-playground-card" aria-labelledby="admin-playground-title">
        <div class="section-title"><h3 id="admin-playground-title">Operations shortcuts</h3><p>Jump into high-frequency admin workflows from the command surface.</p></div>
        <div class="pika-prompt-box">
          <strong>Command launcher</strong>
          <span>Kiểm tra user, quota, model, channel hoặc usage logs chỉ bằng một click.</span>
          <div class="pika-chip-row"><button class="small" @click="emit('set-menu', 'users')">Users</button><button class="small" @click="emit('set-menu', 'models')">Models</button><button class="small" @click="emit('set-menu', 'channels')">Channels</button></div>
        </div>
      </section>

      <section class="admin-workspace-card" aria-labelledby="admin-actions-title">
        <div class="section-title"><h3 id="admin-actions-title">Quick actions</h3><p>Prioritized operational flows presented as direct AppShell actions.</p></div>
        <div class="admin-action-table">
          <button class="admin-action-row" @click="emit('set-menu', 'users'); emit('open-create-user')"><span class="admin-row-index">01</span><span><strong>Thêm người dùng mới</strong><small>Tạo user + gán gói subscription.</small></span><span aria-hidden="true">→</span></button>
          <button class="admin-action-row" @click="emit('set-menu', 'users')"><span class="admin-row-index">02</span><span><strong>Cấp thêm quota cho user</strong><small>Bấm &quot;Cấp thêm&quot; trên từng user để bonus quota hôm nay.</small></span><span aria-hidden="true">→</span></button>
          <button class="admin-action-row" @click="emit('set-menu', 'logs')"><span class="admin-row-index">03</span><span><strong>Tra usage logs</strong><small>Logs sử dụng theo user trong 24h.</small></span><span aria-hidden="true">→</span></button>
          <button class="admin-action-row" @click="emit('set-menu', 'plans')"><span class="admin-row-index">04</span><span><strong>Quản lý gói subscription</strong><small>Tạo / sửa gói tháng & gói token.</small></span><span aria-hidden="true">→</span></button>
        </div>
      </section>

      <section class="admin-workspace-card" aria-labelledby="admin-top-users-title">
        <div class="section-title"><h3 id="admin-top-users-title">Top user theo quota đã dùng</h3><p>Top 5 user tiêu hao quota nhiều nhất hiện tại.</p></div>
        <div class="admin-table-wrap"><table class="admin-app-mini-table">
          <thead><tr><th>User</th><th>Gói</th><th class="num">Đã dùng</th><th class="num">Còn lại</th></tr></thead>
          <tbody>
            <tr v-for="u in topUsersByUsage" :key="String(u.user_id)">
              <td data-label="User"><strong>{{ u.username }}</strong><br /><small>#{{ u.user_id }}</small></td>
              <td data-label="Gói">{{ u.plan_title || '—' }}</td>
              <td data-label="Đã dùng" class="num"><strong>{{ fmt(u.amount_used) }}</strong></td>
              <td data-label="Còn lại" class="num">{{ fmt(u.amount_left) }}</td>
            </tr>
            <tr v-if="!topUsersByUsage.length"><td colspan="4" class="admin-app-empty-state">Chưa có user nào dùng quota.</td></tr>
          </tbody>
        </table></div>
      </section>

      <section class="admin-workspace-card pika-quick-links" aria-labelledby="admin-quick-links-title">
        <div class="section-title"><h3 id="admin-quick-links-title">Quick Links</h3><p>Jump to the most used admin areas.</p></div>
        <div class="pika-link-list">
          <button @click="emit('set-menu', 'users')"><strong>Người dùng</strong><span>Provision, token, quota</span></button>
          <button @click="emit('set-menu', 'plans')"><strong>Gói</strong><span>Subscription packages</span></button>
          <button @click="emit('set-menu', 'logs')"><strong>Usage</strong><span>Analytics and logs</span></button>
        </div>
      </section>
    </div>
  </div>
</template>
