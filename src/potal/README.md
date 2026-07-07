# 1API Portal

Portal source for 1API subscription/quota management.

> Folder name follows the requested spelling: `potal`.

## Structure

```txt
potal/
├── backend/   # Java 21 Spring Boot API
└── frontend/  # Vue 3 + Vite UI
```

## Backend

```bash
cd src/potal/backend
gradle bootRun
```

Default backend URL: <http://localhost:8081>

Health:

```bash
curl http://localhost:8081/api/health
```

## Frontend

```bash
cd src/potal/frontend
npm install
npm run dev
```

Default frontend URL: <http://localhost:5173>

## Current scope

Implemented Java 21 backend and Vue 3 frontend for the 1API user/admin portal. Source now lives next to `new-api` at `src/potal`. Docker compose remains under `src/new-api` so it can reuse the existing New API/Postgres services and env file.

## Admin channel management

The main portal admin screen is available at `/admin`. The `Channels` menu is integrated into this portal and manages New API upstream channels directly from the shared New API PostgreSQL database.

| Capability | Notes |
| --- | --- |
| List channels | Shows ID, name, status, base URL, group, masked key, token count, model list, weight, priority, balance, and used quota. |
| Edit safe metadata | Allows channel name, status, base URL, group, models, weight, and priority. It does not expose or edit secret upstream keys. |
| VietAPI quota check | Calls VietAPI portal login endpoint per stored channel token and returns sanitized quota fields only. This upstream check is separate from portal user token billing. |
| Multi-token compatible | Supports current one-token-per-channel setup and future newline/JSON-array multi-key channels. |

VietAPI quota is displayed in the same unit as the VietAPI portal:

| VietAPI portal label | Backend field | Source field | UI unit |
| --- | --- | --- | --- |
| Gói tháng / còn lại | `total_available` | `data.usage.remain_quota` / `user_remain_quota` | `🌽`, where `1 🌽 = 1,000,000` raw quota |
| Đã dùng | `total_used` | `data.usage.user_used_quota` | `🌽` |
| Hạn ngày | `daily_cap` | `data.usage.group_daily_cap` | `🌽` |
| Hạn gói | `expire_time` / `expire_at` | `data.usage.user_quota_expire_time` | Local date/time |

Do not log or display raw VietAPI/New API keys. API responses expose masked token labels only.

## Admin dashboard, logs & users

The admin portal (`/admin`) surfaces usage analytics, log management, and user provisioning. All cost/quota values are shown in **tokens** (raw New API quota units, 1:1) rather than USD.

### Overview (`/admin`)

| Capability | Notes |
| --- | --- |
| Date-range filter | `Tu ngay` / `Den ngay` inputs, default to today `00:00 -> 23:59`; passes `startTime`/`endTime` (unix seconds) to `GET /api/admin/logs/stats`. |
| Error focus | Cards for total requests, total tokens, total errors, and error rate. |
| Error types table | Groups errors by HTTP `status_code` parsed from log `content`/`other`. |
| Top error users table | Users ordered by error count, with per-user error percentage. |

### Logs (`/admin` -> Logs)

| Capability | Notes |
| --- | --- |
| Token cost + response time | Cost column shows tokens (`formatTokens`); response time uses `use_time` (`formatResponseTime`). |
| Full error message | Error rows show `status_code . message` (fallback `error_type`/`error_code`); rendered full, wrapped, and selectable for tracing. Message is parsed and cleaned server-side (strips `status_code=NNN,` prefix and `(reset after ...)` / `(request id: ...)` noise). |
| Delete logs | `DELETE /api/admin/logs` with filters (`olderThanDays`, `userId`, `modelName`, `status`, `startTime`, `endTime`, or `all=true`). Refuses to wipe all logs unless a filter or `all=true` is given. UI: destructive button + confirm dialog (scope: current filters / older-than-N-days / all). |
| Log retention | `GET`/`PUT /api/admin/logs/retention` persists `PortalLogRetentionDays` in the `options` table. Allowed: `0` (keep forever), `7`, `30`, `90`, `180`, `365` days. A `@Scheduled` job (hourly, minute 30, `Asia/Ho_Chi_Minh`) purges logs older than the window; `0` disables auto-cleanup. |

### Users (`/admin` -> Users)

| Capability | Notes |
| --- | --- |
| Quota columns | Split into Total / Used / Left, all in tokens. |
| Grant tokens | `POST /api/admin/grant-daily-extra-quota` (`{userId, amount}`). Monthly plans get a daily bonus (reset at midnight); token packs get permanent tokens. UI: `Cap token` button + dialog. |

> The user portal logs view (`/logs`) shares the same server-side error parsing, so users also see the cleaned full error message.

### Mobile

The admin layout uses the shadcn-vue sidebar with a built-in mobile offcanvas (`<= 768px`, via Sheet) toggled from the header. Page titles shrink on small screens, filter/action rows stack (`flex-col sm:flex-row`), and tables scroll horizontally (`overflow-auto`).

## Docker

Build and run 1API portal services alongside the existing New API compose stack:

```bash
cd /Users/thanhtq/Documents/project/1gpt/src/new-api
docker compose \
  --env-file .env.local-postgres \
  -f docker-compose.local-postgres.yml \
  -f docker-compose.potal.yml \
  up -d --build potal-backend potal-frontend
```

Open:

- Portal frontend: <http://localhost:5173>
- Backend health through frontend proxy: <http://localhost:5173/api/health>

Optional port override:

```bash
POTAL_FRONTEND_PORT=5174 docker compose --env-file .env.local-postgres -f docker-compose.local-postgres.yml -f docker-compose.potal.yml up -d --build potal-backend potal-frontend
```
