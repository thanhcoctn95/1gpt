import { createRouter, createWebHistory, type RouteRecordRaw } from 'vue-router'
import { useAuth } from '@/composables/useAuth'

const routes: RouteRecordRaw[] = [
  { path: '/', redirect: '/user' },

  // ---- User portal ----
  {
    path: '/user/login',
    name: 'user-login',
    component: () => import('@/views/user/UserLogin.vue'),
    meta: { section: 'user', public: true },
  },
  {
    path: '/user',
    component: () => import('@/layouts/UserLayout.vue'),
    meta: { section: 'user' },
    children: [
      { path: '', redirect: '/user/overview' },
      { path: 'overview', name: 'user-overview', component: () => import('@/views/user/UserOverview.vue') },
      { path: 'models', name: 'user-models', component: () => import('@/views/user/UserModels.vue') },
      { path: 'plans', name: 'user-plans', component: () => import('@/views/user/UserPlans.vue') },
      { path: 'guide', name: 'user-guide', component: () => import('@/views/user/UserGuide.vue') },
      { path: 'logs', name: 'user-logs', component: () => import('@/views/user/UserLogs.vue') },
    ],
  },

  // ---- Admin portal ----
  {
    path: '/admin/login',
    name: 'admin-login',
    component: () => import('@/views/admin/AdminLogin.vue'),
    meta: { section: 'admin', public: true },
  },
  {
    path: '/admin',
    component: () => import('@/layouts/AdminLayout.vue'),
    meta: { section: 'admin' },
    children: [
      { path: '', redirect: '/admin/overview' },
      { path: 'overview', name: 'admin-overview', component: () => import('@/views/admin/AdminOverview.vue') },
      { path: 'users', name: 'admin-users', component: () => import('@/views/admin/AdminUsers.vue') },
      { path: 'models', name: 'admin-models', component: () => import('@/views/admin/AdminModels.vue') },
      { path: 'plans', name: 'admin-plans', component: () => import('@/views/admin/AdminPlans.vue') },
      { path: 'logs', name: 'admin-logs', component: () => import('@/views/admin/AdminLogs.vue') },
    ],
  },

  { path: '/:pathMatch(.*)*', redirect: '/user' },
]

export const router = createRouter({
  history: createWebHistory(),
  routes,
})

router.beforeEach((to) => {
  const { isUserAuthed, isAdminAuthed } = useAuth()
  if (to.meta.public) return true
  if (to.meta.section === 'user' && !isUserAuthed.value) {
    return { name: 'user-login', query: { redirect: to.fullPath } }
  }
  if (to.meta.section === 'admin' && !isAdminAuthed.value) {
    return { name: 'admin-login', query: { redirect: to.fullPath } }
  }
  return true
})

window.addEventListener('admin-session-expired', () => {
  const { handleAdminSessionExpired } = useAuth()
  handleAdminSessionExpired()
  const current = router.currentRoute.value
  if (current.meta.section === 'admin' && current.name !== 'admin-login') {
    void router.replace({ name: 'admin-login', query: { redirect: current.fullPath } })
  }
})
