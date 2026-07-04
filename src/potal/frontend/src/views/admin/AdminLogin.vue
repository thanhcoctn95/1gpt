<script setup lang="ts">
import { ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { toast } from 'vue-sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { useAuth } from '@/composables/useAuth'
import { loginAdmin, ApiError } from '@/services/api'

const { t } = useI18n()
const router = useRouter()
const route = useRoute()
const { setAdminSession } = useAuth()

const username = ref('')
const password = ref('')
const submitting = ref(false)

async function submit() {
  if (!username.value.trim() || !password.value || submitting.value) return
  submitting.value = true
  try {
    const result = await loginAdmin({ username: username.value.trim(), password: password.value })
    setAdminSession(result)
    const redirect = (route.query.redirect as string) || '/admin/overview'
    router.push(redirect)
  } catch (err) {
    const msg = err instanceof ApiError ? err.message : t('auth.loginFailed')
    toast.error(t('auth.loginFailed'), { description: msg })
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <div class="flex min-h-svh items-center justify-center bg-background p-4">
    <Card class="w-full max-w-md">
      <CardHeader>
        <CardTitle class="text-2xl">{{ t('auth.adminTitle') }}</CardTitle>
        <CardDescription>{{ t('auth.adminSubtitle') }}</CardDescription>
      </CardHeader>
      <CardContent>
        <form class="flex flex-col gap-4" @submit.prevent="submit">
          <div class="grid gap-2">
            <Label for="username">{{ t('auth.username') }}</Label>
            <Input id="username" v-model="username" autocomplete="username" />
          </div>
          <div class="grid gap-2">
            <Label for="password">{{ t('auth.password') }}</Label>
            <Input id="password" v-model="password" type="password" autocomplete="current-password" />
          </div>
          <Button type="submit" :disabled="submitting || !username.trim() || !password">
            {{ submitting ? t('common.loading') : t('common.login') }}
          </Button>
        </form>
      </CardContent>
    </Card>
  </div>
</template>
