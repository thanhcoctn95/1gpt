<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { IconBook2, IconCopy, IconExternalLink } from "@tabler/icons-vue";
import {
	Card,
	CardContent,
	CardDescription,
	CardHeader,
	CardTitle,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { getPortalConfig } from "@/services/api";

const { t } = useI18n();
const loading = ref(true);
const newApiBaseUrl = ref("");
const openAiBaseUrl = ref("");

const examples = computed(() => [
	{
		title: "Claude Code",
		description: t("user.guide.claudeDescription"),
		docUrl: "https://docs.anthropic.com/en/docs/claude-code/settings",
		macPath: "~/.claude/settings.json",
		windowsPath: "%USERPROFILE%\\.claude\\settings.json",
		macCommand: "mkdir -p ~/.claude && ${EDITOR:-nano} ~/.claude/settings.json",
		windowsCommand:
			'New-Item -ItemType Directory -Force "$env:USERPROFILE\\.claude"; notepad "$env:USERPROFILE\\.claude\\settings.json"',
		content: `{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "sk-...",
    "ANTHROPIC_BASE_URL": "${newApiBaseUrl.value}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "gpt-5.5",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "gpt-5.5-xhigh",
    "CLAUDE_CODE_SUBAGENT_MODEL": "gpt-5.5"
  },
  "model": "sonnet",
  "disableLoginPrompt": true
}`,
	},
	{
		title: "Codex CLI",
		description: t("user.guide.codexDescription"),
		docUrl: "https://developers.openai.com/codex/config-basic",
		macPath: "~/.codex/config.toml",
		windowsPath: "%USERPROFILE%\\.codex\\config.toml",
		macCommand: "mkdir -p ~/.codex && ${EDITOR:-nano} ~/.codex/config.toml",
		windowsCommand:
			'New-Item -ItemType Directory -Force "$env:USERPROFILE\\.codex"; notepad "$env:USERPROFILE\\.codex\\config.toml"',
		content: `model = "gpt-5.5"
model_provider = "oneapi"

[model_providers.oneapi]
name = "1API"
base_url = "${openAiBaseUrl.value}"
env_key = "OPENAI_API_KEY"
wire_api = "responses"`,
	},
	{
		title: "OpenCode",
		description: t("user.guide.openCodeDescription"),
		docUrl: "https://opencode.ai/docs/config/",
		macPath: "~/.config/opencode/opencode.json",
		windowsPath: "%USERPROFILE%\\.config\\opencode\\opencode.json",
		macCommand:
			"mkdir -p ~/.config/opencode && ${EDITOR:-nano} ~/.config/opencode/opencode.json",
		windowsCommand:
			'New-Item -ItemType Directory -Force "$env:USERPROFILE\\.config\\opencode"; notepad "$env:USERPROFILE\\.config\\opencode\\opencode.json"',
		content: `{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "openai": {
      "options": {
        "baseURL": "${openAiBaseUrl.value}",
        "apiKey": "{env:OPENAI_API_KEY}"
      }
    }
  },
  "model": "openai/gpt-5.5"
}`,
	},
	{
		title: "Roo Code / OpenAI Compatible",
		description: t("user.guide.rooDescription"),
		docUrl: "https://docs.roocode.com/providers/openai-compatible",
		macPath: t("user.guide.rooUiPath"),
		windowsPath: t("user.guide.rooUiPath"),
		macCommand:
			"VS Code → Roo Code → Settings → API Provider → OpenAI Compatible",
		windowsCommand:
			"VS Code → Roo Code → Settings → API Provider → OpenAI Compatible",
		content: `Base URL: ${openAiBaseUrl.value}
API Key:  sk-...
Model ID: gpt-5.5`,
	},
]);

async function copy(text: string) {
	try {
		await navigator.clipboard.writeText(text);
		toast.success(t("common.copied"));
	} catch {
		toast.error(t("common.error"));
	}
}

onMounted(async () => {
	try {
		const config = await getPortalConfig();
		newApiBaseUrl.value = config.newApiPublicBaseUrl || config.newApiBaseUrl;
		openAiBaseUrl.value = config.openAiBaseUrl || `${newApiBaseUrl.value}/v1`;
	} catch {
		toast.error(t("user.guide.loadError"));
	} finally {
		loading.value = false;
	}
});
</script>

<template>
  <div class="flex flex-col gap-4 md:gap-6">
    <div>
      <h2 class="flex items-center gap-2 text-2xl font-semibold tracking-tight">
        <IconBook2 class="size-6" /> {{ t('user.guide.title') }}
      </h2>
      <p class="mt-1 text-sm text-muted-foreground">{{ t('user.guide.subtitle') }}</p>
    </div>

    <div class="grid gap-4 md:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle class="text-base">{{ t('user.guide.baseUrl') }}</CardTitle>
          <CardDescription>{{ t('user.guide.baseUrlDescription') }}</CardDescription>
        </CardHeader>
        <CardContent>
          <Skeleton v-if="loading" class="h-9 w-full" />
          <div v-else class="flex items-center gap-2">
            <code class="min-w-0 flex-1 overflow-x-auto rounded-md bg-muted px-3 py-2 text-sm">{{ newApiBaseUrl || '—' }}</code>
            <Button variant="outline" size="icon" :disabled="!newApiBaseUrl" @click="copy(newApiBaseUrl)">
              <IconCopy class="size-4" />
              <span class="sr-only">{{ t('common.copy') }}</span>
            </Button>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle class="text-base">{{ t('user.guide.openAiBaseUrl') }}</CardTitle>
          <CardDescription>{{ t('user.guide.openAiBaseUrlDescription') }}</CardDescription>
        </CardHeader>
        <CardContent>
          <Skeleton v-if="loading" class="h-9 w-full" />
          <div v-else class="flex items-center gap-2">
            <code class="min-w-0 flex-1 overflow-x-auto rounded-md bg-muted px-3 py-2 text-sm">{{ openAiBaseUrl || '—' }}</code>
            <Button variant="outline" size="icon" :disabled="!openAiBaseUrl" @click="copy(openAiBaseUrl)">
              <IconCopy class="size-4" />
              <span class="sr-only">{{ t('common.copy') }}</span>
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>

    <div class="grid gap-4 xl:grid-cols-2">
      <Card v-for="example in examples" :key="example.title">
        <CardHeader class="flex-row items-start justify-between gap-4">
          <div>
            <CardTitle class="text-base">{{ example.title }}</CardTitle>
            <CardDescription class="mt-1">{{ example.description }}</CardDescription>
            <a
              :href="example.docUrl"
              target="_blank"
              rel="noopener noreferrer"
              class="mt-2 inline-flex items-center gap-1 text-xs font-medium text-primary underline-offset-4 hover:underline"
            >
              {{ t('user.guide.officialDocs') }} <IconExternalLink class="size-3.5" />
            </a>
            <div class="mt-4 grid gap-3 text-xs">
              <div class="font-medium text-foreground">{{ t('user.guide.configLocation') }}</div>
              <div>
                <div class="text-muted-foreground">macOS</div>
                <code class="mt-1 block break-all rounded bg-muted px-2 py-1.5">{{ example.macPath }}</code>
                <div class="mt-2 text-muted-foreground">{{ t('user.guide.openConfig') }}</div>
                <code class="mt-1 block break-all rounded bg-muted px-2 py-1.5">{{ example.macCommand }}</code>
              </div>
              <div>
                <div class="text-muted-foreground">Windows (PowerShell)</div>
                <code class="mt-1 block break-all rounded bg-muted px-2 py-1.5">{{ example.windowsPath }}</code>
                <div class="mt-2 text-muted-foreground">{{ t('user.guide.openConfig') }}</div>
                <code class="mt-1 block break-all rounded bg-muted px-2 py-1.5">{{ example.windowsCommand }}</code>
              </div>
            </div>
          </div>
          <Button variant="outline" size="sm" :disabled="loading || !openAiBaseUrl" @click="copy(example.content)">
            <IconCopy class="size-4" /> {{ t('common.copy') }}
          </Button>
        </CardHeader>
        <CardContent>
          <Skeleton v-if="loading" class="h-40 w-full" />
          <template v-else>
            <div class="mb-3 rounded-lg border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-muted-foreground">
              {{ t('user.guide.mergeNote') }}
            </div>
            <pre class="max-h-96 overflow-auto whitespace-pre-wrap break-words rounded-lg bg-muted p-4 text-xs leading-relaxed"><code>{{ example.content }}</code></pre>
          </template>
        </CardContent>
      </Card>
    </div>

    <p class="text-sm text-muted-foreground">{{ t('user.guide.securityNote') }}</p>
  </div>
</template>
