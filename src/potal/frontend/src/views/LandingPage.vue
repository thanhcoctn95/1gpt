<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { getHealth, getPublicPlans } from '../services/api'

type Coach = { id: string; name: string; alias: string; role: string; spec: string; context: string; speed: string; best: string; benchmark: string; emoji: string }
type Story = { quote: string; author: string; role: string; gain: string; stat: string }
type PlanItem = { id: string; name: string; tagline: string; price: string; tokenCredit: string; unit: string; per: string; badge: string | null; features: string[] }

const { t, tm, locale } = useI18n()

const emit = defineEmits<{
  (e: 'login', apiKey: string): void
  (e: 'go-admin'): void
}>()

const apiKeyInput = ref('')
const loginError = ref('')
const loginBusy = ref(false)
const modalOpen = ref(false)
const navScrolled = ref(false)
const stickyCtaVisible = ref(false)
const revealObserver = ref<IntersectionObserver | null>(null)
const prefersReducedMotion = ref(false)

// Real-time stats from API
const apiHealthy = ref<boolean | null>(null)
const modelCount = ref(0)

const coachModels = [
  { id: 'gpt-5.5', name: 'GPT-5.5', spec: '180ms TTFT', context: '128K', speed: '180ms', benchmark: '98/100 SPRT', emoji: '⚡' },
  { id: 'gpt-5.5-xhigh', name: 'GPT-5.5 X-HIGH', spec: '400K context', context: '400K', speed: '420ms', benchmark: '94/100 PR', emoji: '🧠' },
  { id: 'opus-4.8', name: 'Opus 4.8', spec: '200K context', context: '200K', speed: '290ms', benchmark: '96/100 IQ', emoji: '♟' },
  { id: 'opus-4.8', name: 'Opus 4.8', spec: '200K context (short)', context: '200K', speed: '290ms', benchmark: '96/100 IQ', emoji: '♟' },
  { id: 'opus-4.8-thinking', name: 'Opus 4.8 Thinking', spec: 'Thinking mode (short)', context: '200K', speed: '1.5s', benchmark: 'Thinking', emoji: '💭' },
  { id: 'claude-opus-4.7-thinking', name: 'Opus 4.7 Thinking', spec: '87% SWE-bench', context: '200K', speed: '1.2s', benchmark: '87% SWE', emoji: '🔬' },
  { id: 'fast-code-v4', name: 'Fast Code v4', spec: 'Low-cost tokens', context: '128K', speed: '210ms', benchmark: 'FAST', emoji: '🚀' },
  { id: 'opencode/deepseek-v4-flash-free', name: 'Opencode Zen', spec: 'DS v4 Flash Free', context: '128K', speed: 'Free', benchmark: 'OPENCODE', emoji: '🌀' },
  { id: 'code-reasoning-pro', name: 'Code Reasoning Pro', spec: 'Coding Pro', context: '128K', speed: '350ms', benchmark: 'REASONING', emoji: '🧪' },
  { id: 'minimax-m3', name: 'Minimax M3', spec: 'Vision + Code', context: '256K', speed: '350ms', benchmark: 'NEW GEN', emoji: '🎭' },
] as const

const coaches = computed<Coach[]>(() => {
  const models = tm('coaches.models') as unknown as Array<{ alias: string; role: string; best: string }>
  return coachModels.map((m, i) => ({ ...m, ...(models[i] || { alias: '', role: '', best: '' }) }))
})

const stories = computed<Story[]>(() => {
  const items = tm('stories.items') as unknown as Array<{ gain: string; quote: string; author: string; role: string; stat: string }>
  return items.map(s => ({ ...s }))
})

const monthlyPlanItems = [
  { id: 'plus', price: '549.000', tokenCredit: '20M' },
  { id: 'pro', price: '879.000', tokenCredit: '40M' },
  { id: 'ultra', price: '1.199.000', tokenCredit: '60M' },
  { id: 'max', price: '1.549.000', tokenCredit: '80M' },
] as const

const tokenPackItems = [
  { id: 'mini', price: '69.000', tokenCredit: '50M' },
  { id: 'starter', price: '129.000', tokenCredit: '100M' },
  { id: 'standard', price: '299.000', tokenCredit: '250M' },
  { id: 'power', price: '549.000', tokenCredit: '500M' },
] as const

function mapPlans(base: ReadonlyArray<{ id: string; price: string; tokenCredit: string }>, localeKey: string, perKey: string, unitKey: string): PlanItem[] {
  const items = tm(localeKey) as unknown as Array<{ name: string; tagline: string; badge: string | null; features: string[] }>
  return base.map((p, i) => ({
    ...p,
    name: items[i]?.name || '',
    tagline: items[i]?.tagline || '',
    badge: items[i]?.badge || null,
    features: items[i]?.features || [],
    unit: t(unitKey),
    per: t(perKey),
  }))
}

const monthlyPlans = computed<PlanItem[]>(() => mapPlans(monthlyPlanItems, 'plans.monthlyItems', 'plans.monthlyPer', 'plans.monthlyUnit'))
const tokenPackPlans = computed<PlanItem[]>(() => mapPlans(tokenPackItems, 'plans.tokenPackItems', 'plans.tokenPackPer', 'plans.tokenPackUnit'))

const kpis = computed(() => {
  const items = tm('kpis.items') as unknown as Array<{ value: string; label: string; sub: string }>
  return items.map((item, i) => i === 0 ? { ...item, value: modelCount.value > 0 ? String(modelCount.value) : item.value } : item)
})

const heroStats = computed(() => {
  const items = tm('hero.stats') as unknown as Array<{ value: string; label: string }>
  return items.map((item, i) => i === 0 ? { ...item, value: modelCount.value > 0 ? String(modelCount.value) : item.value } : item)
})
const storyCount = computed(() => stories.value.length)

// Stories carousel
const storyIdx = ref(0)
let storyTimer: ReturnType<typeof setInterval> | null = null
function nextStory() { storyIdx.value = (storyIdx.value + 1) % stories.value.length }
function prevStory() { storyIdx.value = (storyIdx.value - 1 + stories.value.length) % stories.value.length }
function startStoryAuto() {
  if (prefersReducedMotion.value) return
  stopStoryAuto()
  storyTimer = setInterval(nextStory, 6000)
}
function stopStoryAuto() { if (storyTimer) { clearInterval(storyTimer); storyTimer = null } }

// Scroll-driven
let scrollHandler: (() => void) | null = null
function onScroll() {
  const y = window.scrollY
  navScrolled.value = y > 32
  stickyCtaVisible.value = y > 600
}

// Reveal on scroll
function setupReveal() {
  if (prefersReducedMotion.value) {
    document.querySelectorAll<HTMLElement>('.lp-reveal').forEach(el => el.classList.add('is-visible'))
    return
  }
  revealObserver.value = new IntersectionObserver(entries => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        const delay = Number(entry.target.getAttribute('data-reveal-delay') || 0)
        window.setTimeout(() => entry.target.classList.add('is-visible'), delay)
        revealObserver.value?.unobserve(entry.target)
      }
    }
  }, { threshold: 0.15, rootMargin: '0px 0px -10% 0px' })
  document.querySelectorAll<HTMLElement>('.lp-reveal').forEach(el => revealObserver.value?.observe(el))
}

// Hero video: muted autoplay, click to unmute
const heroMuted = ref(true)
const heroVideo = ref<HTMLVideoElement | null>(null)
function toggleHeroSound() {
  if (!heroVideo.value) return
  heroMuted.value = !heroVideo.value.muted
  heroVideo.value.muted = heroMuted.value
}

// Open / close login modal
function openLogin() {
  loginError.value = ''
  apiKeyInput.value = ''
  modalOpen.value = true
  // focus input on next tick
  setTimeout(() => document.getElementById('lp-key-input')?.focus(), 80)
}
function closeLogin() {
  if (loginBusy.value) return
  modalOpen.value = false
  loginError.value = ''
}
async function submitLogin() {
  if (!apiKeyInput.value.trim() || loginBusy.value) return
  loginBusy.value = true
  loginError.value = ''
  emit('login', apiKeyInput.value.trim())
  // emit doesn't await — parent will toggle loggedIn which unmounts us
  // but if it fails, parent will set error and re-render landing
  setTimeout(() => { loginBusy.value = false }, 800)
}

// Language switcher
function switchLang() {
  const next = locale.value === 'vi' ? 'en' : 'vi'
  locale.value = next
  localStorage.setItem('potalLocale', next)
}

// Smooth scroll
function scrollToId(id: string) {
  const el = document.getElementById(id)
  if (el) el.scrollIntoView({ behavior: prefersReducedMotion.value ? 'auto' : 'smooth', block: 'start' })
}

// Lifecycle
onMounted(async () => {
  prefersReducedMotion.value = window.matchMedia('(prefers-reduced-motion: reduce)').matches

  // Fetch real health for hero status
  try {
    const health = await getHealth()
    apiHealthy.value = health.success
  } catch {
    apiHealthy.value = null
  }

  // Fetch dynamic public model count from pricing plans; do not fall back to a fake fixed number.
  try {
    const plans = await getPublicPlans()
    modelCount.value = Math.max(0, ...plans.map(plan => Number(plan.model_count || 0)).filter(Number.isFinite))
  } catch {
    modelCount.value = 0
  }

  scrollHandler = onScroll
  window.addEventListener('scroll', onScroll, { passive: true })
  onScroll()
  setupReveal()
  startStoryAuto()

  // Pause story auto on hover
  const carousel = document.getElementById('lp-story-track')
  if (carousel) {
    carousel.addEventListener('mouseenter', stopStoryAuto)
    carousel.addEventListener('mouseleave', startStoryAuto)
  }

  // Carousel drag (rubber-band)
  setupCarouselDrag()
})

onUnmounted(() => {
  if (scrollHandler) window.removeEventListener('scroll', scrollHandler)
  stopStoryAuto()
  revealObserver.value?.disconnect()
})

// Drag-to-swipe carousel
let dragStartX = 0
let dragDeltaX = 0
let isDragging = false
function setupCarouselDrag() {
  const carousel = document.getElementById('lp-story-track')
  if (!carousel) return
  carousel.addEventListener('pointerdown', e => {
    isDragging = true
    dragStartX = e.clientX
    dragDeltaX = 0
    carousel.setPointerCapture(e.pointerId)
    carousel.classList.add('is-dragging')
  })
  carousel.addEventListener('pointermove', e => {
    if (!isDragging) return
    dragDeltaX = e.clientX - dragStartX
    carousel.style.transform = `translateX(calc(${-storyIdx.value * 100}% + ${dragDeltaX}px))`
  })
  carousel.addEventListener('pointerup', e => {
    if (!isDragging) return
    isDragging = false
    carousel.classList.remove('is-dragging')
    carousel.style.transform = ''
    if (Math.abs(dragDeltaX) > 60) {
      if (dragDeltaX < 0) nextStory(); else prevStory()
    }
  })
  carousel.addEventListener('pointercancel', () => { isDragging = false; carousel.classList.remove('is-dragging'); carousel.style.transform = '' })
}

function fmtNumber(n: number) {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M'
  if (n >= 1_000) return (n / 1_000).toFixed(1) + 'K'
  return String(n)
}
</script>

<template>
  <div class="lp-shell">
    <div class="lp-grain" aria-hidden="true"></div>
    <div class="lp-grid-overlay" aria-hidden="true"></div>

    <!-- Top Nav -->
    <header class="lp-nav" :class="{ 'is-scrolled': navScrolled }">
      <div class="lp-nav-inner">
        <a href="#top" class="lp-logo" @click.prevent="scrollToId('lp-top')">
          <span class="lp-logo-mark">1</span><span class="lp-logo-text">{{ t('nav.logo') }}</span>
          <span class="lp-logo-pill">POTAL · v0.1</span>
        </a>
        <nav class="lp-nav-links" aria-label="Primary">
          <a href="#lp-programs" @click.prevent="scrollToId('lp-programs')">{{ t('nav.goto') }}</a>
          <a href="#lp-coaches" @click.prevent="scrollToId('lp-coaches')">{{ t('nav.models') }}</a>
          <a href="#lp-stories" @click.prevent="scrollToId('lp-stories')">{{ t('nav.caseStudies') }}</a>
          <a href="#lp-trial" @click.prevent="scrollToId('lp-trial')">{{ t('nav.trial') }}</a>
        </nav>
        <div class="lp-nav-cta">
          <span v-if="apiHealthy === true" class="lp-status ok" :title="t('nav.live')"><span class="dot" aria-hidden="true"></span>{{ t('nav.live') }}</span>
          <span v-else-if="apiHealthy === false" class="lp-status off"><span class="dot" aria-hidden="true"></span>{{ t('nav.offline') }}</span>
          <span v-else class="lp-status"><span class="dot" aria-hidden="true"></span>—</span>
          <button class="lp-lang-btn" :title="t('lang.name')" @click="switchLang">{{ t('lang.short') }}</button>
          <a href="/admin" class="lp-nav-admin" @click.prevent="$emit('go-admin')">{{ t('nav.admin') }}</a>
          <button class="lp-btn-primary" @click="openLogin">{{ t('nav.getKey') }}</button>
        </div>
      </div>
    </header>

    <!-- Hero -->
    <section id="lp-top" class="lp-hero">
      <div class="lp-hero-inner">
        <div class="lp-hero-eyebrow lp-reveal" data-reveal-delay="0">
          <span class="lp-tag">POTAL · v0.1</span>
          <span class="lp-tag-divider" aria-hidden="true">·</span>
          <span class="lp-tag">{{ t('hero.tag') }}</span>
        </div>
        <h1 class="lp-hero-title">
          <span class="lp-reveal" data-reveal-delay="80">{{ t('hero.line1') }}</span>
          <span class="lp-reveal lp-accent" data-reveal-delay="160">{{ t('hero.line2') }}</span>
          <span class="lp-reveal" data-reveal-delay="240">{{ t('hero.line3') }} <em>{{ t('hero.line3Em') }}</em></span>
        </h1>
        <p class="lp-hero-sub lp-reveal" data-reveal-delay="320">
          {{ t('hero.sub') }}
        </p>
        <div class="lp-hero-cta lp-reveal" data-reveal-delay="400">
          <button class="lp-btn-primary lg" @click="openLogin">{{ t('hero.getKey') }} <span aria-hidden="true">→</span></button>
          <button class="lp-btn-ghost lg" @click="scrollToId('lp-programs')">{{ t('hero.viewPlans') }}</button>
        </div>
        <div class="lp-hero-stats lp-reveal" data-reveal-delay="500">
          <div v-for="s in heroStats" :key="s.label"><strong>{{ s.value }}</strong><span>{{ s.label }}</span></div>
        </div>
        <div class="lp-hero-reel lp-reveal" data-reveal-delay="600">
          <div class="lp-reel-wrap">
            <div class="lp-reel-bg" aria-hidden="true">
              <div class="lp-reel-mesh"></div>
              <div class="lp-reel-spot"></div>
            </div>
            <div class="lp-reel-overlay" aria-hidden="true">
              <div class="lp-reel-grid"></div>
              <div class="lp-reel-ticker">
                <div v-for="i in 2" :key="i" class="lp-ticker-row">
                  <span>REQ</span><span class="lp-ticker-val">+{{ (Math.random() * 200 + 50).toFixed(0) }}</span>
                  <span>TOK</span><span class="lp-ticker-val">{{ (Math.random() * 8000 + 1000).toFixed(0) }}K</span>
                  <span>LAT</span><span class="lp-ticker-val">{{ (Math.random() * 30 + 8).toFixed(0) }}ms</span>
                  <span>·</span>
                  <span>USER</span><span class="lp-ticker-val">usr_{{ Math.floor(Math.random() * 999) }}</span>
                  <span>·</span>
                </div>
              </div>
            </div>
            <div class="lp-reel-tag" :aria-label="t('hero.reelTag')">
              <span class="lp-reel-tag-dot" aria-hidden="true"></span>
              {{ t('hero.reelTag') }}
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- KPI Strip -->
    <section class="lp-kpi-strip" :aria-label="t('kpis.items.0.label')">
      <div class="lp-kpi-inner">
        <div v-for="(k, i) in kpis" :key="k.label" class="lp-kpi-card lp-reveal" :data-reveal-delay="i * 80">
          <strong class="lp-kpi-value">{{ k.value }}</strong>
          <span class="lp-kpi-label">{{ k.label }}</span>
          <span class="lp-kpi-sub">{{ k.sub }}</span>
        </div>
      </div>
    </section>

    <!-- Plans -->
    <section id="lp-programs" class="lp-programs">
      <div class="lp-section-head">
        <span class="lp-section-eyebrow lp-reveal">— {{ t('plans.section') }}</span>
        <h2 class="lp-section-title lp-reveal" data-reveal-delay="80">{{ t('plans.title') }} <em>{{ t('plans.titleEm') }}</em></h2>
        <p class="lp-section-sub lp-reveal" data-reveal-delay="160">{{ t('plans.sub') }}</p>
      </div>
      <div class="lp-plan-group lp-reveal" data-reveal-delay="220">
        <h3>{{ t('plans.monthlyTitle') }}</h3>
        <p>{{ t('plans.monthlySub') }}</p>
      </div>
      <div class="lp-program-grid">
        <article v-for="(p, i) in monthlyPlans" :key="p.id" class="lp-program-card lp-reveal" :data-reveal-delay="i * 100" :class="{ featured: p.badge }">
          <div v-if="p.badge" class="lp-program-badge">{{ p.badge }}</div>
          <header class="lp-program-head">
            <h3>{{ p.name }}</h3>
            <p class="lp-program-tag">{{ p.tagline }}</p>
          </header>
          <div class="lp-program-price">
            <strong>{{ p.price }}<small>₫ / {{ p.per }}</small></strong>
            <span class="lp-program-token">{{ p.tokenCredit }} <em>{{ p.unit }}</em></span>
          </div>
          <ul class="lp-program-features">
            <li v-for="f in p.features" :key="f"><span class="lp-check" aria-hidden="true">▸</span>{{ f }}</li>
          </ul>
          <button class="lp-btn-block" :class="p.badge ? 'primary' : 'ghost'" @click="openLogin">START {{ p.name }}</button>
        </article>
      </div>
      <div class="lp-plan-group lp-reveal" data-reveal-delay="260">
        <h3>{{ t('plans.tokenPackTitle') }}</h3>
        <p>{{ t('plans.tokenPackSub') }}</p>
      </div>
      <div class="lp-program-grid">
        <article v-for="(p, i) in tokenPackPlans" :key="p.id" class="lp-program-card lp-reveal" :data-reveal-delay="i * 100" :class="{ featured: p.badge }">
          <div v-if="p.badge" class="lp-program-badge">{{ p.badge }}</div>
          <header class="lp-program-head">
            <h3>{{ p.name }}</h3>
            <p class="lp-program-tag">{{ p.tagline }}</p>
          </header>
          <div class="lp-program-price">
            <strong>{{ p.price }}<small>₫ / {{ p.per }}</small></strong>
            <span class="lp-program-token">{{ p.tokenCredit }} <em>{{ p.unit }}</em></span>
          </div>
          <ul class="lp-program-features">
            <li v-for="f in p.features" :key="f"><span class="lp-check" aria-hidden="true">▸</span>{{ f }}</li>
          </ul>
          <button class="lp-btn-block" :class="p.badge ? 'primary' : 'ghost'" @click="openLogin">START {{ p.name }}</button>
        </article>
      </div>
    </section>

    <!-- Trust / Money-back Guarantee -->
    <section class="lp-trust lp-reveal">
      <div class="lp-trust-inner">
        <span class="lp-trust-badge">🛡️</span>
        <h2 class="lp-trust-title">{{ t('trust.title') }}</h2>
        <p class="lp-trust-line">— {{ t('trust.line1') }}</p>
        <p class="lp-trust-line">— {{ t('trust.line2') }}</p>
      </div>
    </section>

    <!-- Models -->
    <section id="lp-coaches" class="lp-coaches">
      <div class="lp-section-head">
        <span class="lp-section-eyebrow lp-reveal">— {{ t('coaches.section') }}</span>
        <h2 class="lp-section-title lp-reveal" data-reveal-delay="80">{{ t('coaches.title') }} <em>{{ t('coaches.titleEm') }}</em></h2>
        <p class="lp-section-sub lp-reveal" data-reveal-delay="160">{{ t('coaches.sub') }}</p>
      </div>
      <div class="lp-coach-grid">
        <article v-for="(c, i) in coaches" :key="c.id" class="lp-coach-card lp-reveal" :data-reveal-delay="i * 80" tabindex="0" :aria-label="`${c.name} — ${c.alias}`">
          <div class="lp-coach-flip">
            <div class="lp-coach-face lp-coach-front">
              <div class="lp-coach-emoji" aria-hidden="true">{{ c.emoji }}</div>
              <div class="lp-coach-front-info">
                <span class="lp-coach-alias">{{ c.alias }}</span>
                <h3 class="lp-coach-name">{{ c.name }}</h3>
                <p class="lp-coach-role">{{ c.role }}</p>
              </div>
              <span class="lp-coach-hint">{{ t('coaches.hint') }}</span>
            </div>
            <div class="lp-coach-face lp-coach-back">
              <div class="lp-coach-stats">
                <div><span>{{ t('coaches.backLabels.context') }}</span><strong>{{ c.context }}</strong></div>
                <div><span>{{ t('coaches.backLabels.ttft') }}</span><strong>{{ c.speed }}</strong></div>
                <div><span>{{ t('coaches.backLabels.spec') }}</span><strong>{{ c.spec }}</strong></div>
                <div><span>{{ t('coaches.backLabels.bench') }}</span><strong>{{ c.benchmark }}</strong></div>
              </div>
              <div class="lp-coach-best">
                <span class="lp-coach-best-label">{{ t('coaches.backLabels.bestLabel') }}</span>
                <p>{{ c.best }}</p>
              </div>
            </div>
          </div>
        </article>
      </div>
    </section>

    <!-- Stories -->
    <section id="lp-stories" class="lp-stories">
      <div class="lp-section-head">
        <span class="lp-section-eyebrow lp-reveal">— {{ t('stories.section') }}</span>
        <h2 class="lp-section-title lp-reveal" data-reveal-delay="80">{{ t('stories.title') }} <em>{{ t('stories.titleEm') }}</em></h2>
        <p class="lp-section-sub lp-reveal" data-reveal-delay="160">{{ t('stories.sub') }}</p>
      </div>
      <div class="lp-story-viewport">
        <button class="lp-story-arrow left" type="button" :aria-label="t('stories.prevAria')" @click="prevStory">‹</button>
        <div class="lp-story-track" id="lp-story-track" :aria-label="`Story ${storyIdx + 1} of ${storyCount}`">
          <article v-for="(s, i) in stories" :key="i" class="lp-story-card" :aria-hidden="i !== storyIdx">
            <div class="lp-story-gain">{{ s.gain }}</div>
            <blockquote class="lp-story-quote">"{{ s.quote }}"</blockquote>
            <footer class="lp-story-foot">
              <div>
                <strong>{{ s.author }}</strong>
                <span>{{ s.role }}</span>
              </div>
              <div class="lp-story-stat">
                <span class="lp-story-stat-num">{{ s.stat }}</span>
                <span class="lp-story-stat-label">{{ t('stories.verified') }}</span>
              </div>
            </footer>
          </article>
        </div>
        <button class="lp-story-arrow right" type="button" :aria-label="t('stories.nextAria')" @click="nextStory">›</button>
        <div class="lp-story-dots" role="tablist" :aria-label="t('stories.section')">
          <button v-for="(_, i) in stories" :key="i" class="lp-story-dot" :class="{ active: i === storyIdx }" :aria-selected="i === storyIdx" :aria-label="`${t('stories.dotAria')} ${i + 1}`" @click="storyIdx = i" type="button" role="tab"></button>
        </div>
      </div>
    </section>

    <!-- Trial CTA -->
    <section id="lp-trial" class="lp-trial">
      <div class="lp-trial-inner lp-reveal">
        <span class="lp-section-eyebrow">— {{ t('trial.section') }}</span>
        <h2 class="lp-trial-title">{{ t('trial.title') }} <em>{{ t('trial.titleEm') }}</em></h2>
        <p class="lp-trial-sub">{{ t('trial.sub') }}</p>
        <div class="lp-trial-actions">
          <button class="lp-btn-primary xl" @click="openLogin">{{ t('trial.cta') }} <span aria-hidden="true">→</span></button>
          <span class="lp-trial-note">{{ t('trial.note') }}</span>
        </div>
      </div>
    </section>

    <!-- Footer -->
    <footer class="lp-footer">
      <div class="lp-footer-inner">
        <div class="lp-footer-brand">
          <span class="lp-logo"><span class="lp-logo-mark">1</span><span class="lp-logo-text">{{ t('nav.logo') }}</span></span>
          <p>{{ t('footer.desc') }}</p>
        </div>
        <div class="lp-footer-cols">
          <div>
            <h4>{{ t('footer.product') }}</h4>
            <a href="#lp-programs" @click.prevent="scrollToId('lp-programs')">{{ t('footer.productLinks.0') }}</a>
            <a href="#lp-coaches" @click.prevent="scrollToId('lp-coaches')">{{ t('footer.productLinks.1') }}</a>
            <a href="#lp-stories" @click.prevent="scrollToId('lp-stories')">{{ t('footer.productLinks.2') }}</a>
            <a href="#" @click.prevent="openLogin">{{ t('footer.productLinks.3') }}</a>
          </div>
          <div>
            <h4>{{ t('footer.resources') }}</h4>
            <a href="https://new.api.1api.click" target="_blank" rel="noopener">{{ t('footer.resourceLinks.0') }}</a>
            <a href="https://new.api.1api.click/v1/models" target="_blank" rel="noopener">{{ t('footer.resourceLinks.1') }}</a>
            <a href="mailto:ops@1api.click">{{ t('footer.resourceLinks.2') }}</a>
            <a href="mailto:ops@1api.click?subject=Trial%20request">{{ t('footer.resourceLinks.3') }}</a>
          </div>
          <div>
            <h4>{{ t('footer.operations') }}</h4>
            <a href="#" @click.prevent="scrollToId('lp-stories')">{{ t('footer.opLinks.0') }}</a>
            <a href="https://1api.click" target="_blank" rel="noopener">{{ t('footer.opLinks.1') }}</a>
            <a href="mailto:ops@1api.click">{{ t('footer.opLinks.2') }}</a>
          </div>
        </div>
      </div>
      <div class="lp-footer-base">
        <span>{{ t('footer.copyright') }}</span>
        <span class="lp-footer-mono">v0.1 · {{ new Date().toISOString().slice(0, 10) }}</span>
      </div>
    </footer>

    <!-- Sticky bottom CTA -->
    <Transition name="lp-sticky">
      <button v-if="stickyCtaVisible && !modalOpen" type="button" class="lp-sticky-cta" @click="openLogin">
        <span class="lp-sticky-dot" aria-hidden="true"></span>
        {{ t('sticky.label') }}
      </button>
    </Transition>

    <!-- Login modal -->
    <Transition name="lp-modal">
      <div v-if="modalOpen" class="lp-modal-backdrop" @click.self="closeLogin" role="dialog" aria-modal="true" aria-labelledby="lp-modal-title">
        <div class="lp-modal">
          <button class="lp-modal-close" type="button" :aria-label="t('modal.closeAria')" @click="closeLogin">×</button>
          <span class="lp-section-eyebrow">— {{ t('modal.eyebrow') }}</span>
          <h3 id="lp-modal-title">{{ t('modal.title') }} <em>{{ t('modal.titleEm') }}</em></h3>
          <p>{{ t('modal.sub') }}</p>
          <label class="lp-modal-label">
            <span>{{ t('modal.label') }}</span>
            <input id="lp-key-input" v-model="apiKeyInput" type="password" :placeholder="t('modal.placeholder')" autocomplete="off" @keyup.enter="submitLogin" />
          </label>
          <p v-if="loginError" class="lp-modal-error" role="alert">{{ loginError }}</p>
          <div class="lp-modal-actions">
            <button class="lp-btn-ghost" type="button" @click="closeLogin" :disabled="loginBusy">{{ t('modal.cancel') }}</button>
            <button class="lp-btn-primary" type="button" @click="submitLogin" :disabled="!apiKeyInput || loginBusy">
              {{ loginBusy ? t('modal.submitting') : t('modal.submit') }}
            </button>
          </div>
          <p class="lp-modal-foot">
            <a href="https://t.me/+GRP4GxmlccU5Nzc1" target="_blank" rel="noopener">{{ t('modal.trialLink') }}</a>
          </p>
        </div>
      </div>
    </Transition>
  </div>
</template>
