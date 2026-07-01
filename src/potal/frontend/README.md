# 1API Frontend

Vue 3 + Vite frontend for the portal.

## Run

```bash
cd src/potal/frontend
npm install
npm run dev
```

Default dev URL: <http://localhost:5173>

The Vite dev server proxies `/api` to `http://localhost:8081` by default.
Override with:

```bash
PORTAL_BACKEND_URL=http://localhost:8081 npm run dev
```

## Admin portal

Open `/admin` and sign in with a New API admin user. The admin shell currently includes:

| Menu | Purpose |
| --- | --- |
| Dashboard | High-level operational summary |
| Người dùng | Provisioned user list, token copy, extra quota grant |
| Gói | Subscription/token plan management |
| Đồng bộ | Model visibility and routing gates |
| Channels | New API upstream channel metadata and VietAPI credit/quota checks |
| Usage Logs | User usage logs and model stats |


## Clean-slate Astryx admin design contract

The `/admin` portal is rebuilt as a Vue 3 + Vite adaptation of the official Astryx Themes guidance from `https://astryx.atmeta.com/themes`. The implementation uses scoped CSS tokens and Vue templates only: no React, StyleX, `@astryxdesign/*`, backend API, database, or generated `dist` changes are part of this contract.

| Area | Contract |
| --- | --- |
| Theme source | Use Astryx Neutral token semantics: `--color-background-*`, `--color-text-*`, `--color-border*`, `--radius-*`, `--shadow-*`, `light-dark(...)`. |
| App frame | Build one clean Pika-style admin dashboard frame: skip link, sticky global top bar, fixed side navigation rail, semantic main content, page header, status strip, framed page canvas, playground-style operations card, quick links, and mobile-safe overflow behavior. |
| Navigation | Dashboard, Người dùng, Gói, Đồng bộ, Channels, and Usage Logs remain the only admin sections; active section uses `aria-current`. |
| Content pages | Each page uses the same Astryx page pattern: section title, optional toolbar/filter row, primary data surface, loading skeleton, empty state, and status/error feedback. |
| Accessibility | Preserve labels, captions, `aria-busy`, `role=status`, focus-visible states, skip-link navigation, dialog semantics, readable contrast, and reduced-motion behavior. |
| Security | Keep all admin/user/channel/API tokens masked in browser UI; never reveal raw New API or VietAPI upstream keys. |
| Integration | Preserve existing Vue state, API service calls, route behavior, and Kubernetes frontend-only deploy model. |
| Non-goals | No dependency additions, React/StyleX integration, backend contract changes, database changes, or direct edits under `src/potal/frontend/dist`. |

Clean-slate acceptance checks for UI work:

| Screen | Required visible states |
| --- | --- |
| Admin login | Branded Astryx Neutral login card, labelled username/password fields, disabled/loading feedback, accessible status message. |
| Dashboard | Pika-style overview hero, metric rows, playground operations card, quick-action list, quick links, top-user table, local status/time, and empty state. |
| Người dùng | Toolbar/action, loading skeleton, table with masked token display, token/quota actions, empty state, modal validation/status messages. |
| Gói | Toolbar/action, loading skeleton, plan table, create/edit modal, model picker empty state, validation/status messages. |
| Đồng bộ | Loading skeleton, API error banner, model summary, empty state, accessible model toggle. |
| Channels | Filter toolbar, loading/reload feedback, masked keys only, quota check status, edit form, empty state. |
| Usage Logs | Filter toolbar, stats loading/empty states, paginated table, error/empty states. |

Verification required before completion:

| Check | Command or evidence |
| --- | --- |
| Types | `cd src/potal/frontend && npm run typecheck` |
| Build | `cd src/potal/frontend && npm run build` |
| Dependencies | scan `package.json` for `react`, `react-dom`, and `@astryxdesign/*` additions; expected `[]`. |
| Source markers | Search for clean shell/theme markers and obsolete legacy UI markers. |
| Runtime smoke | Local `/admin` HTTP `200`; after deployment, public `https://1api.click/admin` HTTP `200`. |

## Channels screen

The `Channels` screen is integrated directly into the main `potal` admin UI, not the separate `new-api-user-portal` companion.

Visible data:

| Field | Display behavior |
| --- | --- |
| Channel ID/name/status | Read from New API `channels` table |
| Upstream base URL/group | Editable safe metadata |
| Upstream key | Masked only; raw key is never exposed to the browser |
| Token count | Derived on the backend from single key, newline multi-key, or JSON-array multi-key storage |
| Models | Editable comma-separated model list |
| Routing | Weight and priority |
| VietAPI quota | Shown in `🌽` units with raw value as secondary detail |

Credit check display uses VietAPI portal semantics:

| Label | Source API field | UI format |
| --- | --- | --- |
| Còn lại | `total_available` from backend, mapped from `data.usage.remain_quota` | `N 🌽` |
| Đã dùng | `total_used` from backend, mapped from `data.usage.user_used_quota` | `N 🌽` |
| Hạn ngày | `daily_cap` from backend, mapped from `data.usage.group_daily_cap` | `N 🌽` |
| Hạn gói | `expire_time` from backend, mapped from `data.usage.user_quota_expire_time` | Localized date/time |

Conversion:

```txt
1 🌽 = 1,000,000 raw quota
```

Security notes:

- The browser never receives full VietAPI/New API keys.
- The backend sanitizes credit check responses and returns only parsed quota fields plus masked token labels.
- Editing a channel intentionally excludes secret key changes; update upstream keys in New API/admin DB using the normal operational procedure.
