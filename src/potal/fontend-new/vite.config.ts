import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  base: '/admin/',
  server: {
    proxy: {
      '/api': {
        target: process.env.PORTAL_BACKEND_URL || 'http://localhost:8081',
        changeOrigin: true,
      },
    },
  },
})
