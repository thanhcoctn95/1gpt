<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { toast } from 'vue-sonner'
import { IconCoins, IconCopy, IconPlus, IconRefresh } from '@tabler/icons-vue'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TableBody, TableCell, TableEmpty, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { useAuth } from '@/composables/useAuth'
import { formatDate, formatTokens } from '@/lib/format'
import { ApiError, getAdminPlans, getProvisionedUsers, getUserToken, grantTokens, provisionUser } from '@/services/api'
import type { AdminPlanRow, ProvisionedUserRow } from '@/services/api'

const { t } = useI18n()
const { adminToken } = useAuth()

const loading = ref(false)
const plansLoading = ref(false)
const submitting = ref(false)
const users = ref<ProvisionedUserRow[]>([])
const plans = ref<AdminPlanRow[]>([])
const dialogOpen = ref(false)
const username = ref('')
const selectedPlanId = ref('')
const copyingUserId = ref<number | null>(null)

const grantDialogOpen = ref(false)
const grantUser = ref<ProvisionedUserRow | null>(null)
const grantAmount = ref('')
const granting = ref(false)

const canSubmit = computed(() => username.value.trim().length > 0 && selectedPlanId.value.length > 0 && !submitting.value)
const canGrant = computed(() => {
  const amount = Number(grantAmount.value)
  return grantUser.value !== null && Number.isFinite(amount) && amount > 0 && !granting.value
})

function errorMessage(err: unknown, fallback: string): string {
  return err instanceof ApiError ? err.message : fallback
}

function resetForm() {
  username.value = ''
  selectedPlanId.value = ''
}

async function fetchUsers() {
  loading.value = true
  try {
    users.value = await getProvisionedUsers(adminToken.value)
  } catch (err) {
    toast.error(errorMessage(err, t('common.error')))
  } finally {
    loading.value = false
  }
}

async function fetchPlans() {
  plansLoading.value = true
  try {
    plans.value = await getAdminPlans(adminToken.value)
  } catch (err) {
    toast.error(errorMessage(err, t('common.error')))
  } finally {
    plansLoading.value = false
  }
}

async function submitUser() {
  if (!canSubmit.value) return
  submitting.value = true
  const name = username.value.trim()
  try {
    await provisionUser(adminToken.value, { username: name, planId: Number(selectedPlanId.value) })
    toast.success(t('admin.users.createSuccess', { name }))
    dialogOpen.value = false
    resetForm()
    await fetchUsers()
  } catch (err) {
    toast.error(t('admin.users.createError'), { description: errorMessage(err, t('admin.users.createError')) })
  } finally {
    submitting.value = false
  }
}

async function copyToken(user: ProvisionedUserRow) {
  if (copyingUserId.value !== null) return
  copyingUserId.value = user.user_id
  const name = user.username
  try {
    const result = await getUserToken(adminToken.value, { userId: user.user_id })
    await navigator.clipboard.writeText(result.apiKey)
    toast.success(t('admin.users.tokenCopied', { name }))
  } catch (err) {
    toast.error(t('admin.users.tokenFetchError'), { description: errorMessage(err, t('admin.users.tokenFetchError')) })
  } finally {
    copyingUserId.value = null
  }
}

function openGrantDialog(user: ProvisionedUserRow) {
  grantUser.value = user
  grantAmount.value = ''
  grantDialogOpen.value = true
}

async function submitGrant() {
  if (!canGrant.value || !grantUser.value) return
  granting.value = true
  const user = grantUser.value
  const amount = Math.floor(Number(grantAmount.value))
  try {
    await grantTokens(adminToken.value, { userId: user.user_id, amount })
    toast.success(t('admin.users.grantSuccess', { amount: amount.toLocaleString('en-US'), name: user.username }))
    grantDialogOpen.value = false
    grantAmount.value = ''
    await fetchUsers()
  } catch (err) {
    toast.error(t('admin.users.grantError'), { description: errorMessage(err, t('admin.users.grantError')) })
  } finally {
    granting.value = false
  }
}

onMounted(async () => {
  await Promise.all([fetchUsers(), fetchPlans()])
})
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
      <div class="flex flex-col gap-1">
        <h1 class="text-xl font-semibold tracking-tight sm:text-2xl">{{ t('admin.users.title') }}</h1>
        <p class="text-sm text-muted-foreground">{{ t('admin.users.quota') }}</p>
      </div>
      <div class="flex items-center gap-2">
        <Button variant="outline" :disabled="loading" @click="fetchUsers">
          <IconRefresh class="size-4" />
          {{ t('common.refresh') }}
        </Button>
        <Dialog v-model:open="dialogOpen">
          <DialogTrigger as-child>
            <Button>
              <IconPlus class="size-4" />
              {{ t('admin.users.addUser') }}
            </Button>
          </DialogTrigger>
          <DialogContent>
            <form class="grid gap-4" @submit.prevent="submitUser">
              <DialogHeader>
                <DialogTitle>{{ t('admin.users.createTitle') }}</DialogTitle>
                <DialogDescription>{{ t('admin.users.selectPlan') }}</DialogDescription>
              </DialogHeader>

              <div class="grid gap-2">
                <Label for="admin-user-username">{{ t('admin.users.username') }}</Label>
                <Input id="admin-user-username" v-model="username" autocomplete="off" />
              </div>

              <div class="grid gap-2">
                <Label for="admin-user-plan">{{ t('admin.users.plan') }}</Label>
                <Select v-model="selectedPlanId" :disabled="plansLoading || plans.length === 0">
                  <SelectTrigger id="admin-user-plan" class="w-full">
                    <SelectValue :placeholder="plansLoading ? t('common.loading') : t('admin.users.selectPlan')" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem v-for="plan in plans" :key="plan.id" :value="String(plan.id)">
                      <div class="flex flex-col">
                        <span>{{ plan.title }}</span>
                        <span class="text-xs text-muted-foreground">{{ formatTokens(plan.total_amount) }} · {{ plan.quota_reset_period || '—' }}</span>
                      </div>
                    </SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <DialogFooter>
                <Button type="button" variant="outline" @click="dialogOpen = false">{{ t('common.cancel') }}</Button>
                <Button type="submit" :disabled="!canSubmit">{{ submitting ? t('common.loading') : t('common.create') }}</Button>
              </DialogFooter>
            </form>
          </DialogContent>
        </Dialog>
      </div>
    </div>

    <Card>
      <CardHeader>
        <CardTitle>{{ t('admin.nav.users') }}</CardTitle>
        <CardDescription>{{ t('admin.users.tokenKey') }}</CardDescription>
      </CardHeader>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{{ t('admin.users.username') }}</TableHead>
              <TableHead>{{ t('admin.users.plan') }}</TableHead>
              <TableHead class="text-right">{{ t('admin.users.quotaTotal') }}</TableHead>
              <TableHead class="text-right">{{ t('admin.users.quotaUsed') }}</TableHead>
              <TableHead class="text-right">{{ t('admin.users.quotaLeft') }}</TableHead>
              <TableHead>{{ t('admin.users.tokenKey') }}</TableHead>
              <TableHead>{{ t('admin.users.period') }}</TableHead>
              <TableHead>{{ t('admin.users.endTime') }}</TableHead>
              <TableHead class="text-right">{{ t('common.actions') }}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <template v-if="loading">
              <TableRow v-for="index in 6" :key="`user-skeleton-${index}`">
                <TableCell><Skeleton class="h-4 w-32" /></TableCell>
                <TableCell><Skeleton class="h-4 w-28" /></TableCell>
                <TableCell><Skeleton class="ml-auto h-4 w-20" /></TableCell>
                <TableCell><Skeleton class="ml-auto h-4 w-20" /></TableCell>
                <TableCell><Skeleton class="ml-auto h-4 w-20" /></TableCell>
                <TableCell><Skeleton class="h-4 w-32" /></TableCell>
                <TableCell><Skeleton class="h-4 w-20" /></TableCell>
                <TableCell><Skeleton class="h-4 w-24" /></TableCell>
                <TableCell><Skeleton class="ml-auto h-8 w-28" /></TableCell>
              </TableRow>
            </template>
            <TableEmpty v-else-if="users.length === 0" :colspan="9" class="text-muted-foreground">
              {{ t('common.noData') }}
            </TableEmpty>
            <TableRow v-for="user in users" v-else :key="user.user_id">
              <TableCell class="font-medium">{{ user.username }}</TableCell>
              <TableCell>
                <Badge variant="secondary">{{ user.plan_title || '—' }}</Badge>
              </TableCell>
              <TableCell class="text-right tabular-nums">{{ formatTokens(user.amount_total) }}</TableCell>
              <TableCell class="text-right tabular-nums">{{ formatTokens(user.amount_used) }}</TableCell>
              <TableCell class="text-right tabular-nums">{{ formatTokens(user.amount_left) }}</TableCell>
              <TableCell class="font-mono text-xs text-muted-foreground">{{ user.key_masked || '—' }}</TableCell>
              <TableCell>{{ user.quota_reset_period || '—' }}</TableCell>
              <TableCell>{{ formatDate(user.end_time) }}</TableCell>
              <TableCell class="text-right">
                <div class="flex items-center justify-end gap-2">
                  <Button variant="outline" size="sm" :disabled="granting" @click="openGrantDialog(user)">
                    <IconCoins class="size-4" />
                    {{ t('admin.users.grantTokens') }}
                  </Button>
                  <Button variant="outline" size="sm" :disabled="copyingUserId !== null" @click="copyToken(user)">
                    <IconCopy class="size-4" />
                    {{ copyingUserId === user.user_id ? t('common.loading') : t('admin.users.copyToken') }}
                  </Button>
                </div>
              </TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </CardContent>
    </Card>

    <Dialog v-model:open="grantDialogOpen">
      <DialogContent>
        <form class="grid gap-4" @submit.prevent="submitGrant">
          <DialogHeader>
            <DialogTitle>{{ t('admin.users.grantTitle', { name: grantUser?.username ?? '' }) }}</DialogTitle>
            <DialogDescription>{{ t('admin.users.grantDescription') }}</DialogDescription>
          </DialogHeader>

          <div class="grid gap-2">
            <Label for="admin-grant-amount">{{ t('admin.users.grantAmount') }}</Label>
            <Input
              id="admin-grant-amount"
              v-model="grantAmount"
              type="number"
              min="1"
              step="1"
              inputmode="numeric"
              autocomplete="off"
            />
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" @click="grantDialogOpen = false">{{ t('common.cancel') }}</Button>
            <Button type="submit" :disabled="!canGrant">{{ granting ? t('common.loading') : t('admin.users.grant') }}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  </div>
</template>
