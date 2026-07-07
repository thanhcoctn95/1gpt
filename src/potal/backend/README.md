# 1API Backend

Java 21 + Spring Boot backend for the 1API portal.

## Run

```bash
cd src/potal/backend
./gradlew bootRun
```

If Gradle is not installed/wrapper not generated yet:

```bash
gradle bootRun
```

## Environment

- `PORTAL_BACKEND_PORT` default `8081`
- `NEW_API_BASE_URL` default `http://localhost:3000`
- `NEW_API_DB_URL` default `jdbc:postgresql://localhost:5432/newapi`
- `NEW_API_DB_USER` default `newapi`
- `NEW_API_DB_PASSWORD` must be set for real DB access

## Key endpoints

### Public/runtime

- `GET /api/health`
- `GET /api/config`

### Admin auth

- `POST /api/admin/login`

### Admin New API channels

These endpoints power the `/admin` → `Channels` screen in the portal.

- `GET /api/admin/channels`
  - Lists New API channels from the shared New API PostgreSQL database.
  - Supports `q` and `status` query params.
  - Never returns raw upstream API keys; keys are masked and token count is derived server-side.
- `PATCH /api/admin/channels/{channelId}`
  - Updates safe channel metadata only: name, status, base URL, group, models, weight, priority.
  - Does not update or expose upstream secret keys.
- `POST /api/admin/channels/{channelId}/credit`
  - Checks upstream VietAPI account quota by calling `https://vietapi.tech/api/portal/login` with the stored channel key. This endpoint name is legacy; portal user billing remains token/quota based.
  - Supports single-token channels and future multi-token channels stored as newline-separated keys or JSON string arrays.
  - Aggregates successful token checks.

## VietAPI quota mapping

VietAPI portal displays quota in `🌽` units. The backend keeps raw quota values and the frontend converts using:

```txt
1 🌽 = 1,000,000 raw quota
```

For VietAPI portal-login responses, explicit `data.usage.*` fields are preferred:

| Portal label | Response field | API response field | Notes |
| --- | --- | --- | --- |
| Gói tháng / còn lại | `data.usage.remain_quota` or `data.usage.user_remain_quota` | `total_available` | Display as `total_available / 1_000_000 🌽` |
| Đã dùng | `data.usage.user_used_quota` | `total_used` | Display as `total_used / 1_000_000 🌽` |
| Hạn ngày | `data.usage.group_daily_cap` | `daily_cap` | Display as `daily_cap / 1_000_000 🌽` |
| Hạn gói | `data.usage.user_quota_expire_time` | `expire_time`, `expire_at` | Unix seconds plus ISO timestamp |

Do not log or return raw VietAPI response objects because they can include sensitive fields such as full keys/tokens.
