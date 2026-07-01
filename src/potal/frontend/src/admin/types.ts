export type AdminMenuKey = 'dashboard' | 'users' | 'models' | 'logs' | 'plans' | 'channels'

export type AdminMenuItem = {
  key: AdminMenuKey
  label: string
  desc: string
  icon: readonly string[]
}

export type AdminShellHealth = {
  label: string
  tone: string
  text: string
}

export type AdminLoginForm = {
  username: string
  password: string
}
