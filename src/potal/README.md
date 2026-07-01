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
| VietAPI credit check | Calls VietAPI portal login endpoint per stored channel token and returns sanitized quota fields only. |
| Multi-token compatible | Supports current one-token-per-channel setup and future newline/JSON-array multi-key channels. |

VietAPI quota is displayed in the same unit as the VietAPI portal:

| VietAPI portal label | Backend field | Source field | UI unit |
| --- | --- | --- | --- |
| Gói tháng / còn lại | `total_available` | `data.usage.remain_quota` / `user_remain_quota` | `🌽`, where `1 🌽 = 1,000,000` raw quota |
| Đã dùng | `total_used` | `data.usage.user_used_quota` | `🌽` |
| Hạn ngày | `daily_cap` | `data.usage.group_daily_cap` | `🌽` |
| Hạn gói | `expire_time` / `expire_at` | `data.usage.user_quota_expire_time` | Local date/time |

Do not log or display raw VietAPI/New API keys. API responses expose masked token labels only.

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
