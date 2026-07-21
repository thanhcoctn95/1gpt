import { computed, ref } from 'vue'
import { logoutAdmin as revokeAdminSession, type AdminLoginResult } from '@/services/api'

const USER_KEY = 'potalUserApiKey'
const ADMIN_TOKEN_KEY = 'potalAdminToken'
const ADMIN_USER_KEY = 'potalAdminUser'

const userApiKey = ref<string>(localStorage.getItem(USER_KEY) || '')
const adminToken = ref<string>(localStorage.getItem(ADMIN_TOKEN_KEY) || '')
const adminUser = ref<AdminLoginResult['user'] | null>(readAdminUser())

function readAdminUser(): AdminLoginResult['user'] | null {
  try {
    const raw = localStorage.getItem(ADMIN_USER_KEY)
    return raw ? (JSON.parse(raw) as AdminLoginResult['user']) : null
  } catch {
    return null
  }
}

function persistAdminSession(result: AdminLoginResult) {
  adminToken.value = result.adminToken
  adminUser.value = result.user
  localStorage.setItem(ADMIN_TOKEN_KEY, result.adminToken)
  localStorage.setItem(ADMIN_USER_KEY, JSON.stringify(result.user))
}

function clearAdminSession() {
  adminToken.value = ''
  adminUser.value = null
  localStorage.removeItem(ADMIN_TOKEN_KEY)
  localStorage.removeItem(ADMIN_USER_KEY)
}

export function useAuth() {
  const isUserAuthed = computed(() => Boolean(userApiKey.value))
  const isAdminAuthed = computed(() => Boolean(adminToken.value))

  function setUserApiKey(key: string) {
    userApiKey.value = key.trim()
    if (userApiKey.value) localStorage.setItem(USER_KEY, userApiKey.value)
    else localStorage.removeItem(USER_KEY)
  }

  function logoutUser() { setUserApiKey('') }
  function setAdminSession(result: AdminLoginResult) { persistAdminSession(result) }
  function logoutAdmin() {
    void revokeAdminSession().catch(() => undefined)
    clearAdminSession()
  }

  function handleAdminSessionExpired() {
    clearAdminSession()
  }

  return { userApiKey, adminToken, adminUser, isUserAuthed, isAdminAuthed, setUserApiKey, logoutUser, setAdminSession, logoutAdmin, handleAdminSessionExpired }
}
