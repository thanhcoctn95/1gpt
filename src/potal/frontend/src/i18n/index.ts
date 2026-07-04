import { createI18n } from 'vue-i18n'
import vi from './locales/vi'
import en from './locales/en'

const LOCALE_KEY = 'potalLocale'

function detectLocale(): 'vi' | 'en' {
  const stored = localStorage.getItem(LOCALE_KEY)
  if (stored === 'vi' || stored === 'en') return stored
  const nav = (navigator.language || '').toLowerCase()
  return nav.startsWith('en') ? 'en' : 'vi'
}

export const i18n = createI18n({
  legacy: false,
  locale: detectLocale(),
  fallbackLocale: 'vi',
  messages: { vi, en },
})

export function setLocale(locale: 'vi' | 'en') {
  i18n.global.locale.value = locale
  localStorage.setItem(LOCALE_KEY, locale)
  document.documentElement.setAttribute('lang', locale)
}
