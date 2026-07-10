import { useColorMode } from '@vueuse/core'

export type ThemeMode = 'light' | 'dark'

// Shared color-mode state for the whole portal (user + admin).
// vueuse `useColorMode` toggles the `dark` class on <html> and persists the
// choice to localStorage. The initial value follows the OS preference until the
// user picks a theme explicitly.
const mode = useColorMode({
  selector: 'html',
  attribute: 'class',
  storageKey: 'potalTheme',
  // Map modes to the class applied on <html>. `auto` follows system preference.
  modes: {
    light: '',
    dark: 'dark',
  },
  initialValue: 'auto',
})

/**
 * Access and control the light/dark theme.
 * `mode` is 'light' | 'dark' | 'auto'; `isDark` reflects the effective theme.
 */
export function useTheme() {
  const isDark = () => document.documentElement.classList.contains('dark')

  function toggle() {
    mode.value = isDark() ? 'light' : 'dark'
  }

  function set(next: ThemeMode) {
    mode.value = next
  }

  return { mode, isDark, toggle, set }
}
