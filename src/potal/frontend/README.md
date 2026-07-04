# 1API Portal Frontend

Vue 3 + Vite single-page app for the 1API Portal. It ships two portals from one build:

| Portal | Base path | Auth | Purpose |
| --- | --- | --- | --- |
| User | `/user` | New API key (Bearer) | Personal usage overview, model catalog, usage logs |
| Admin | `/admin` | Admin token from `POST /api/admin/login` | User provisioning, model visibility, usage logs and retention |

## Stack

| Area | Choice |
| --- | --- |
| Framework | Vue 3 (`<script setup>`) + Vue Router |
| Build | Vite 6, `vue-tsc` type-checked build |
| Styling | Tailwind CSS v4 (`@tailwindcss/vite`), dark theme by default |
| UI | shadcn-vue (new-york, neutral) components under `src/components/ui` |
| Icons | `lucide-vue-next` and `@tabler/icons-vue` |
| i18n | `vue-i18n`, Vietnamese (default) and English |
| Data grid / charts | `@tanstack/vue-table`, `@unovis/vue` |
| Toasts | `vue-sonner` |

## Run

```bash
cd src/potal/frontend
npm install
npm run dev
```

Default dev URL: <http://localhost:5173>

The Vite dev server proxies `/api` to `http://localhost:8081` by default. Override with:

```bash
PORTAL_BACKEND_URL=http://localhost:8081 npm run dev
```

## Scripts

| Command | Action |
| --- | --- |
| `npm run dev` | Start the dev server on `0.0.0.0:5173` |
| `npm run build` | Type-check (`vue-tsc -b`) and build to `dist/` |
| `npm run preview` | Preview the production build on `0.0.0.0:4173` |
| `npm run typecheck` | Type-check without emitting |

## Project layout

| Path | Contents |
| --- | --- |
| `src/main.ts` | App bootstrap (router, i18n, global styles) |
| `src/router/index.ts` | Routes and per-section auth guards |
| `src/layouts/` | `UserLayout.vue`, `AdminLayout.vue` (sidebar + header shell) |
| `src/views/user/` | User login, overview, models, logs |
| `src/views/admin/` | Admin login, overview, users, models, logs |
| `src/components/portal/` | Shared sidebar, header, and user menu |
| `src/components/ui/` | shadcn-vue primitives |
| `src/composables/useAuth.ts` | User key and admin session state (localStorage) |
| `src/services/api.ts` | Typed client for the Spring backend (`/api/*`) |
| `src/i18n/locales/` | `vi.ts` (default) and `en.ts` |
| `src/lib/` | `format.ts` (key masking, formatting), `utils.ts` |

## Auth model

- User portal authenticates with a New API key stored in `localStorage` (`potalUserApiKey`) and sent as a Bearer token.
- Admin portal exchanges username/password at `POST /api/admin/login` for an admin token (`potalAdminToken`), with the admin profile cached in `potalAdminUser`.
- Route guards in `router/index.ts` redirect unauthenticated visitors to the matching login screen.
- All API keys and upstream tokens are masked in the UI via `maskKey` and are never rendered in raw form.

## Deploy

Built as a static bundle served by nginx. See `Dockerfile` and the Kubernetes manifest `src/deploy/k8s/09-new-api-user-portal.yaml`. This is a frontend-only image; no backend, database, or generated `dist` sources are committed.
