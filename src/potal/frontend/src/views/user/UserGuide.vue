<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { IconBook2, IconCopy } from "@tabler/icons-vue";
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
const selectedTool = ref("Claude Code");
const selectedOs = ref<"windows" | "linux" | "macos">("windows");
const userApiKey = ref("");
const newApiBaseUrl = ref("");
const openAiBaseUrl = ref("");

const automaticCommand = computed(() => {
	if (selectedTool.value !== "Claude Code")
		return activeExample.value?.content || "";
	if (selectedOs.value === "windows") {
		return `irm https://kiro.pix4k.com/setup/install.ps1 | iex; setup -Key ${userApiKey.value || "{API KEY}"}`;
	}
	return `curl -fsSL https://kiro.pix4k.com/setup/install.sh | bash -s -- --key ${userApiKey.value || "{API KEY}"}`;
});

const automaticConfig = computed(
	() =>
		({
			windows: {
				intro: t("user.guide.windowsIntro"),
				warning: t("user.guide.windowsWarning"),
			},
			linux: {
				intro: t("user.guide.linuxIntro"),
				warning: t("user.guide.terminalWarning"),
			},
			macos: {
				intro: t("user.guide.macosIntro"),
				warning: t("user.guide.terminalWarning"),
			},
		})[selectedOs.value],
);

const toolTabs = [
	"Claude Code",
	"Codex CLI",
	"OpenCode",
	"Roo Code / OpenAI Compatible",
];

const osTabs = [
	{ id: "windows", label: "Windows" },
	{ id: "linux", label: "Linux" },
	{ id: "macos", label: "macOS" },
] as const;

const examples = computed(() => [
	{
		title: "Claude Code",
		description: t("user.guide.claudeDescription"),
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

const activeExample = computed(() =>
	examples.value.find((example) => example.title === selectedTool.value),
);

async function copy(text: string) {
	try {
		await navigator.clipboard.writeText(text);
		toast.success(t("common.copied"));
	} catch {
		toast.error(t("common.error"));
	}
}

onMounted(async () => {
	userApiKey.value = localStorage.getItem("potalUserApiKey") || "";
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

    <Card class="gap-0 py-0">
      <CardHeader class="gap-2 px-5 py-5 md:px-6 md:py-6">
        <CardTitle class="text-lg">② {{ t('user.guide.automaticSetup') }}</CardTitle>
        <CardDescription class="text-sm leading-6 text-foreground/80">
          {{ t('user.guide.automaticDescription') }}
        </CardDescription>
        <div role="tablist" :aria-label="t('user.guide.toolLabel')" class="mt-3 flex flex-wrap gap-2">
          <button
            v-for="tool in toolTabs"
            :key="tool"
            type="button"
            role="tab"
            :aria-selected="selectedTool === tool"
            class="min-h-10 rounded-md border px-3 text-sm font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
            :class="selectedTool === tool ? 'border-blue-600 bg-blue-600 text-white dark:border-blue-500 dark:bg-blue-500' : 'bg-background text-muted-foreground hover:bg-muted hover:text-foreground'"
            @click="selectedTool = tool"
          >
            {{ tool }}
          </button>
        </div>
      </CardHeader>

      <CardContent class="px-5 pb-6 md:px-6">
        <div role="tablist" :aria-label="t('user.guide.osLabel')" class="flex border-b">
          <button
            v-for="tab in osTabs"
            :id="`guide-tab-${tab.id}`"
            :key="tab.id"
            type="button"
            role="tab"
            :aria-selected="selectedOs === tab.id"
            :aria-controls="`guide-panel-${tab.id}`"
            class="relative min-h-11 px-4 text-sm font-semibold text-muted-foreground transition-colors hover:text-foreground focus-visible:z-10 focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-ring md:px-5"
            :class="selectedOs === tab.id ? 'text-blue-600 after:absolute after:inset-x-0 after:-bottom-px after:h-0.5 after:bg-blue-600 dark:text-blue-400 dark:after:bg-blue-400' : ''"
            @click="selectedOs = tab.id"
          >
            {{ tab.label }}
          </button>
        </div>

        <div
          :id="`guide-panel-${selectedOs}`"
          role="tabpanel"
          :aria-labelledby="`guide-tab-${selectedOs}`"
          class="pt-4"
        >
          <template v-if="selectedTool === 'Claude Code'">
            <p class="text-sm leading-6">{{ automaticConfig.intro }}</p>
            <div class="mt-2 flex gap-3 rounded-lg border border-amber-500/30 bg-amber-500/10 px-4 py-3 text-sm leading-6">
              <span aria-hidden="true" class="mt-0.5 text-amber-600">⚠</span>
              <span>{{ automaticConfig.warning }}</span>
            </div>
            <div class="mt-3 flex min-w-0 items-center gap-3 rounded-lg border bg-muted/60 p-2 pl-4">
              <code class="min-w-0 flex-1 overflow-x-auto whitespace-nowrap py-2 text-sm">{{ automaticCommand }}</code>
              <Button variant="outline" size="sm" class="h-9 shrink-0" @click="copy(automaticCommand)">
                <IconCopy class="size-4" /> {{ t('common.copy') }}
              </Button>
            </div>
            <p class="mt-5 text-sm leading-6 text-foreground/80">
              {{ t('user.guide.automaticResult') }}
            </p>
          </template>

          <template v-else-if="activeExample">
            <p class="text-sm leading-6">{{ activeExample.description }}</p>
            <div class="mt-3 grid gap-3 rounded-lg border bg-muted/30 p-4 text-sm">
              <div>
                <div class="font-medium">{{ t('user.guide.configLocation') }}</div>
                <code class="mt-1 block overflow-x-auto whitespace-nowrap rounded-md bg-muted px-3 py-2">{{ selectedOs === 'windows' ? activeExample.windowsPath : activeExample.macPath }}</code>
              </div>
              <div>
                <div class="font-medium">{{ t('user.guide.openConfig') }}</div>
                <code class="mt-1 block overflow-x-auto whitespace-nowrap rounded-md bg-muted px-3 py-2">{{ selectedOs === 'windows' ? activeExample.windowsCommand : activeExample.macCommand }}</code>
              </div>
            </div>
          </template>

          <p class="mt-5 text-sm text-muted-foreground">
            {{ t('user.guide.manualConfigFor', { tool: selectedTool }) }}
          </p>
          <div class="relative mt-3 rounded-lg border bg-muted/60">
            <Button variant="outline" size="sm" class="absolute right-2 top-2 h-9" :disabled="loading || !activeExample" @click="activeExample && copy(activeExample.content)">
              <IconCopy class="size-4" /> {{ t('common.copy') }}
            </Button>
            <Skeleton v-if="loading" class="m-4 h-40" />
            <pre v-else class="max-h-96 overflow-auto whitespace-pre-wrap break-words p-4 pr-24 text-xs leading-relaxed"><code>{{ activeExample?.content }}</code></pre>
          </div>
        </div>
      </CardContent>
    </Card>

    <p class="text-sm text-muted-foreground">{{ t('user.guide.securityNote') }}</p>
  </div>
</template>
