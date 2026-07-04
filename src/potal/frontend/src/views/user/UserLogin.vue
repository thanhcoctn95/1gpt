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
import { getDashboardMe, ApiError } from '@/services/api'

const { t } = useI18n()
const router = useRouter()
const route = useRoute()
const { setUserApiKey } = useAuth()

const apiKey = ref('')
const submitting = ref(false)

async function submit() {
  if (!apiKey.value.trim() || submitting.value) return
  submitting.value = true
  try {
    await getDashboardMe(apiKey.value.trim())
    setUserApiKey(apiKey.value)
    const redirect = (route.query.redirect as string) || '/user/overview'
    router.push(redirect)
  } catch (err) {
    const msg = err instanceof ApiError ? err.message : t('auth.invalidKey')
    toast.error(t('auth.invalidKey'), { description: msg })
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <div class="flex min-h-svh items-center justify-center bg-background p-4">
    <Card class="w-full max-w-md">
      <CardHeader>
        <CardTitle class="text-2xl">{{ t('auth.userTitle') }}</CardTitle>
        <CardDescription>{{ t('auth.userSubtitle') }}</CardDescription>
      </CardHeader>
      <CardContent>
        <form class="flex flex-col gap-4" @submit.prevent="submit">
          <div class="grid gap-2">
            <Label for="apiKey">{{ t('auth.apiKeyLabel') }}</Label>
            <Input
              id="apiKey"
              v-model="apiKey"
              type="password"
              autocomplete="off"
              :placeholder="t('auth.apiKeyPlaceholder')"
            />
          </div>
          <Button type="submit" :disabled="submitting || !apiKey.trim()">
            {{ submitting ? t('common.loading') : t('auth.enter') }}
          </Button>
        </form>
      </CardContent>
    </Card>
  </div>
</template>
