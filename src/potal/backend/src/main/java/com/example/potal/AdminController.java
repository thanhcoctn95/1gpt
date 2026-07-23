package com.example.potal;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.http.ResponseEntity;

@RestController
@RequestMapping("/api/admin")
public class AdminController {
    private final JdbcTemplate jdbc;
    private final AuthService authService;
    private final HttpClient httpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    private final ObjectMapper objectMapper = new ObjectMapper();

    public AdminController(JdbcTemplate jdbc, AuthService authService) {
        this.jdbc = jdbc;
        this.authService = authService;
    }

    @GetMapping("/models/available")
    public Map<String, Object> availableModels(@RequestHeader(value = "Authorization", required = false) String authorization) {
        authService.requireAdmin(authorization);
        List<Map<String, Object>> rows = jdbc.queryForList("""
            WITH channel_models AS (
              SELECT DISTINCT trim(model) AS model_name
              FROM channels c
              CROSS JOIN LATERAL regexp_split_to_table(COALESCE(c.models, ''), ',') AS model
              WHERE c.status = 1 AND trim(model) <> ''
            )
            SELECT model_name FROM channel_models ORDER BY model_name ASC LIMIT 500
            """);
        return Map.of("success", true, "data", rows);
    }

    /**
     * List managed models from active channels, optionally including hidden (status=0) models.
     *
     * By default only returns active models (status=1), matching what end users see via
     * the dashboard. Pass {@code ?showAll=true} to include inactive models for management.
     *
     * @param showAll if true, include models with status=0 (disabled/inactive)
     */
    @GetMapping("/models")
    public Map<String, Object> adminModels(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @RequestParam(value = "showAll", defaultValue = "false") boolean showAll
    ) {
        authService.requireAdmin(authorization);
        List<Map<String, Object>> rows = jdbc.queryForList(
            """
            WITH channel_models AS (
              SELECT DISTINCT trim(model) AS model_name, c.name AS channel_name
              FROM channels c
              CROSS JOIN LATERAL regexp_split_to_table(COALESCE(c.models, ''), ',') AS model
              WHERE c.status = 1 AND trim(model) <> ''
            ),
            model_channels AS (
              SELECT model_name,
                     STRING_AGG(channel_name, ', ' ORDER BY channel_name) AS channels
              FROM channel_models
              GROUP BY model_name
            )
            SELECT DISTINCT ON (COALESCE(m.model_name, mc.model_name))
                   COALESCE(m.model_name, mc.model_name) AS model_name,
                   COALESCE(m.description, '') AS description,
                   COALESCE(m.icon, '') AS icon,
                   COALESCE(m.status, 1)::int AS status,
                   COALESCE(mc.channels, '') AS channels,
                   EXISTS (
                     SELECT 1 FROM logs l
                     WHERE l.model_name = COALESCE(m.model_name, mc.model_name)
                       AND l.completion_tokens > 0
                       AND l.created_at >= (EXTRACT(EPOCH FROM NOW()) - 7*24*3600)
                   ) AS has_token_out
            FROM model_channels mc
            LEFT JOIN models m
              ON m.model_name = mc.model_name AND m.deleted_at IS NULL
            ORDER BY COALESCE(m.model_name, mc.model_name) ASC
            LIMIT 500
            """
        );
        // Filter: by default only show active models (status=1), same as user dashboard.
        // Admin can pass showAll=true to see disabled models for re-enable.
        List<Map<String, Object>> filtered = showAll
            ? rows
            : rows.stream().filter(r -> ((Number) r.getOrDefault("status", 1)).intValue() == 1).toList();
        long activeCount = filtered.stream().filter(r -> ((Number) r.getOrDefault("status", 1)).intValue() == 1).count();
        return Map.of("success", true, "data", Map.of(
            "items", filtered,
            "total", filtered.size(),
            "activeCount", activeCount
        ));
    }

    /**
     * Toggle a model active/inactive. Updates `models.status` (display + dashboard gate) and mirrors
     * `abilities.enabled` so New API routing reflects the change. If no `models` row exists yet it is
     * created so the toggle is persistent.
     */
    @PatchMapping("/models/{modelName}/active")
    @Transactional
    public ResponseEntity<?> setModelActive(
        @RequestHeader(value = "Authorization", required = false) String authorization,
        @PathVariable String modelName,
        @RequestBody ModelActiveRequest request
    ) {
        authService.requireAdmin(authorization);
        String safeName = modelName == null ? "" : modelName.trim();
        if (safeName.isBlank() || safeName.length() > 128 || !safeName.matches("[A-Za-z0-9._:/\\-]+")) {
            throw new IllegalArgumentException("Invalid model name");
        }
        ModelActiveRequest safeRequest = request == null ? new ModelActiveRequest(true) : request;
        boolean active = safeRequest.active() == null || safeRequest.active();
        int status = active ? 1 : 0;
        long now = java.time.Instant.now().getEpochSecond();

        int updated = jdbc.update(
            "UPDATE models SET status=?, updated_time=? WHERE model_name=? AND deleted_at IS NULL",
            status, now, safeName);
        if (updated == 0) {
            jdbc.update("""
                INSERT INTO models (model_name, description, icon, status, created_time, updated_time)
                VALUES (?, '', '', ?, ?, ?)
                ON CONFLICT (model_name, deleted_at) DO UPDATE SET status=EXCLUDED.status, updated_time=EXCLUDED.updated_time
                """, safeName, status, now, now);
        }

        // Mirror New API routing gate so an inactive model is not selectable upstream.
        int abilitiesUpdated = jdbc.update("UPDATE abilities SET enabled=? WHERE model=?", active, safeName);

        // New API's /v1/models honors token model_limits. Refresh users whose active
        // subscription grants all models so that endpoint exposes only Admin-active models.
        int tokensUpdated = jdbc.update("""
            WITH active_models AS (
              SELECT string_agg(cm.model_name, ',' ORDER BY cm.model_name) AS model_limits
              FROM (
                SELECT DISTINCT trim(model) AS model_name
                FROM channels c
                CROSS JOIN LATERAL regexp_split_to_table(COALESCE(c.models, ''), ',') AS model
                LEFT JOIN models m ON m.model_name = trim(model) AND m.deleted_at IS NULL
                WHERE c.status = 1 AND trim(model) <> '' AND COALESCE(m.status, 1) = 1
              ) cm
            ), full_model_users AS (
              SELECT DISTINCT s.user_id
              FROM user_subscriptions s
              JOIN subscription_plans p ON p.id = s.plan_id
              WHERE s.status = 'active' AND s.end_time > ?
                AND (p.model_list IS NULL OR btrim(p.model_list) = '')
            )
            UPDATE tokens t
            SET model_limits_enabled = true,
                model_limits = (SELECT model_limits FROM active_models)
            WHERE t.user_id IN (SELECT user_id FROM full_model_users)
              AND t.deleted_at IS NULL
            """, now);

        return ResponseEntity.ok(Map.of("success", true, "data", Map.of(
            "modelName", safeName,
            "active", active,
            "status", status,
            "abilitiesUpdated", abilitiesUpdated,
            "tokensUpdated", tokensUpdated
        )));
    }

    public record ModelActiveRequest(Boolean active) {}

    @GetMapping("/users/{userId}/tokens")
    public Map<String, Object> userTokens(@RequestHeader(value = "Authorization", required = false) String authorization, @PathVariable long userId) {
        authService.requireAdmin(authorization);
        List<Map<String, Object>> rows = jdbc.queryForList("""
            SELECT id, user_id, status, name,
                   CASE WHEN length(key) <= 8 THEN repeat('*', length(key)) ELSE left(key, 4) || repeat('*', GREATEST(length(key)-8, 0)) || right(key, 4) END AS key_masked,
                   to_timestamp(created_time) AS created_time,
                   CASE WHEN accessed_time > 0 THEN to_timestamp(accessed_time) ELSE NULL END AS accessed_time,
                   CASE WHEN expired_time > 0 THEN to_timestamp(expired_time) ELSE NULL END AS expired_time,
                   remain_quota, unlimited_quota, used_quota, "group", cross_group_retry,
                   model_limits_enabled, model_limits, allow_ips
            FROM tokens WHERE user_id=? AND deleted_at IS NULL ORDER BY id DESC
            """, userId);
        return Map.of("success", true, "data", rows);
    }

    @PatchMapping("/tokens/{tokenId}/model-limits")
    public ResponseEntity<?> updateToken(@RequestHeader(value = "Authorization", required = false) String authorization, @PathVariable long tokenId, @RequestBody TokenUpdateRequest request) {
        authService.requireAdmin(authorization);
        request = request.normalized();
        jdbc.update("""
            UPDATE tokens SET model_limits_enabled=?, model_limits=?, status=?, "group"=?, unlimited_quota=?
            WHERE id=? AND deleted_at IS NULL
            """,
            request.modelLimitsEnabled(),
            SqlUtil.uniqueCsv(request.modelLimits()),
            request.status(),
            request.group(),
            request.unlimitedQuota() != null && request.unlimitedQuota(),
            tokenId
        );
        List<Map<String, Object>> rows = jdbc.queryForList("SELECT id, user_id, status, name, model_limits_enabled, model_limits, \"group\", unlimited_quota, used_quota, remain_quota FROM tokens WHERE id=?", tokenId);
        return ResponseEntity.ok(Map.of("success", true, "data", rows.isEmpty() ? Map.of() : rows.get(0)));
    }

    public record TokenUpdateRequest(Integer status, String group, Boolean unlimitedQuota, Boolean modelLimitsEnabled, String modelLimits) {
        TokenUpdateRequest normalized() {
            int safeStatus = status == null ? 1 : status;
            if (safeStatus != 1 && safeStatus != 2) throw new IllegalArgumentException("Invalid token status");
            String safeGroup = group == null ? "" : group.trim();
            if (safeGroup.length() > 64 || !safeGroup.matches("[A-Za-z0-9_.-]*")) throw new IllegalArgumentException("Invalid group");
            String safeLimits = modelLimits == null ? "" : modelLimits.trim();
            if (safeLimits.length() > 8000) throw new IllegalArgumentException("Model limits too long");
            return new TokenUpdateRequest(safeStatus, safeGroup, unlimitedQuota, modelLimitsEnabled, safeLimits);
        }
    }

    @GetMapping("/channels")
    public Map<String, Object> channels(
        @RequestHeader(value = "Authorization", required = false) String authorization,
        @RequestParam(value = "q", defaultValue = "") String q,
        @RequestParam(value = "status", required = false) Integer status
    ) {
        authService.requireAdmin(authorization);
        String query = q == null ? "" : q.trim();
        List<Object> args = new ArrayList<>();
        StringBuilder where = new StringBuilder(" WHERE 1=1 ");
        if (!query.isBlank()) {
            where.append(" AND (name ILIKE ? OR tag ILIKE ? OR remark ILIKE ? OR id::text = ?) ");
            String like = "%" + query + "%";
            args.add(like); args.add(like); args.add(like); args.add(query);
        }
        if (status != null) {
            where.append(" AND status = ? ");
            args.add(status);
        }
        List<Map<String, Object>> rows = jdbc.queryForList("""
            SELECT id, type, name, status, COALESCE(base_url, '') AS base_url,
                   key AS key_raw,
                   CASE WHEN length(key) <= 10 THEN repeat('*', length(key)) ELSE left(key, 5) || repeat('*', LEAST(GREATEST(length(key)-9, 0), 24)) || right(key, 4) END AS key_masked,
                   0 AS token_count,
                   models, "group", COALESCE(weight, 0) AS weight, COALESCE(priority, 0) AS priority,
                   balance, to_timestamp(balance_updated_time) AS balance_updated_at,
                   used_quota, to_timestamp(test_time) AS test_time, response_time, tag, remark,
                   CASE WHEN channel_info IS NULL THEN false ELSE COALESCE((channel_info::jsonb ->> 'is_multi_key')::boolean, false) END AS is_multi_key
            FROM channels
            """ + where + " ORDER BY priority DESC, id ASC LIMIT 200", args.toArray());
        for (Map<String, Object> row : rows) {
            List<String> keys = splitChannelKeys(String.valueOf(row.getOrDefault("key_raw", "")));
            row.put("token_count", keys.size());
            if (!keys.isEmpty()) row.put("key_masked", maskSecret(keys.get(0)) + (keys.size() > 1 ? " +" + (keys.size() - 1) : ""));
            row.remove("key_raw");
        }
        return Map.of("success", true, "data", rows);
    }

    @PatchMapping("/channels/{channelId}")
    public ResponseEntity<?> updateChannel(
        @RequestHeader(value = "Authorization", required = false) String authorization,
        @PathVariable long channelId,
        @RequestBody ChannelUpdateRequest request
    ) {
        authService.requireAdmin(authorization);
        ChannelUpdateRequest r = request == null ? new ChannelUpdateRequest(null, null, null, null, null, null, null) : request.normalized();
        long now = Instant.now().getEpochSecond();
        jdbc.update("""
            UPDATE channels SET name=COALESCE(?, name), status=COALESCE(?, status), base_url=COALESCE(?, base_url),
                   models=COALESCE(?, models), "group"=COALESCE(?, "group"), weight=COALESCE(?, weight),
                   priority=COALESCE(?, priority), test_time=?
            WHERE id=?
            """, r.name(), r.status(), r.baseUrl(), r.models() == null ? null : SqlUtil.uniqueCsv(r.models()), r.group(), r.weight(), r.priority(), now, channelId);
        List<Map<String, Object>> rows = jdbc.queryForList("SELECT id, name, status, base_url, models, \"group\", weight, priority, balance FROM channels WHERE id=?", channelId);
        return ResponseEntity.ok(Map.of("success", true, "data", rows.isEmpty() ? Map.of() : rows.get(0)));
    }

    public record ChannelUpdateRequest(String name, Integer status, String baseUrl, String models, String group, Integer weight, Long priority) {
        ChannelUpdateRequest normalized() {
            String safeName = name == null ? null : name.trim();
            if (safeName != null && (safeName.isBlank() || safeName.length() > 128)) throw new IllegalArgumentException("Invalid channel name");
            Integer safeStatus = status;
            if (safeStatus != null && safeStatus != 0 && safeStatus != 1 && safeStatus != 2) throw new IllegalArgumentException("Invalid channel status");
            String safeBase = baseUrl == null ? null : baseUrl.trim().replaceAll("/+$", "");
            if (safeBase != null && !safeBase.matches("https?://[^\\s]+")) throw new IllegalArgumentException("Invalid base URL");
            String safeModels = models == null ? null : models.trim();
            if (safeModels != null && safeModels.length() > 12000) throw new IllegalArgumentException("Model list too long");
            String safeGroup = group == null ? null : group.trim();
            if (safeGroup != null && (safeGroup.length() > 64 || !safeGroup.matches("[A-Za-z0-9_.-]*"))) throw new IllegalArgumentException("Invalid group");
            Integer safeWeight = weight;
            if (safeWeight != null && (safeWeight < 0 || safeWeight > 1_000_000)) throw new IllegalArgumentException("Invalid weight");
            return new ChannelUpdateRequest(safeName, safeStatus, safeBase, safeModels, safeGroup, safeWeight, priority);
        }
    }

    @PostMapping("/channels/{channelId}/credit")
    public ResponseEntity<?> checkChannelCredit(
        @RequestHeader(value = "Authorization", required = false) String authorization,
        @PathVariable long channelId
    ) throws Exception {
        authService.requireAdmin(authorization);
        List<Map<String, Object>> rows = jdbc.queryForList("SELECT id, name, COALESCE(base_url, '') AS base_url, key FROM channels WHERE id=?", channelId);
        if (rows.isEmpty()) throw new IllegalArgumentException("Channel not found");
        Map<String, Object> channel = rows.get(0);
        String baseUrl = String.valueOf(channel.getOrDefault("base_url", "https://api.vietapi.tech")).replaceAll("/+$", "");
        List<String> keys = splitChannelKeys(String.valueOf(channel.getOrDefault("key", "")));
        if (keys.isEmpty()) throw new IllegalArgumentException("Channel has no upstream token/key");
        List<Map<String, Object>> checks = new ArrayList<>();
        double total = 0;
        double totalUsed = 0;
        double totalDailyCap = 0;
        Long latestExpireTime = null;
        int success = 0;
        for (int i = 0; i < keys.size(); i++) {
            Map<String, Object> result = fetchVietApiCredit(baseUrl, keys.get(i));
            result.put("index", i);
            result.put("token_masked", maskSecret(keys.get(i)));
            checks.add(result);
            if (Boolean.TRUE.equals(result.get("success")) && result.get("total_available") instanceof Number n) {
                total += n.doubleValue();
                if (result.get("total_used") instanceof Number used) totalUsed += used.doubleValue();
                if (result.get("daily_cap") instanceof Number cap) totalDailyCap += cap.doubleValue();
                if (result.get("expire_time") instanceof Number exp) latestExpireTime = latestExpireTime == null ? exp.longValue() : Math.max(latestExpireTime, exp.longValue());
                success += 1;
            }
        }
        if (success > 0) jdbc.update("UPDATE channels SET balance=?, balance_updated_time=? WHERE id=?", total, Instant.now().getEpochSecond(), channelId);
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("channel_id", channel.get("id"));
        data.put("name", channel.get("name"));
        data.put("base_url", baseUrl);
        data.put("token_count", keys.size());
        data.put("checked_at", Instant.now().toString());
        data.put("credit_check_success", success > 0);
        data.put("total_available", success > 0 ? total : null);
        data.put("total_used", success > 0 ? totalUsed : null);
        data.put("daily_cap", success > 0 ? totalDailyCap : null);
        data.put("expire_time", latestExpireTime);
        data.put("expire_at", latestExpireTime == null ? null : Instant.ofEpochSecond(latestExpireTime).toString());
        data.put("unit", "corn");
        data.put("unit_divisor", 1_000_000);
        data.put("checks", checks);
        return ResponseEntity.ok(Map.of("success", true, "data", data));
    }

    private Map<String, Object> fetchVietApiCredit(String baseUrl, String key) throws Exception {
        List<Map<String, Object>> endpoints = List.of(
            Map.of("method", "POST", "base", portalBaseUrlForCredit(baseUrl), "endpoint", "/api/portal/login"),
            Map.of("method", "GET", "base", baseUrl, "endpoint", "/dashboard/billing/credit_grants"),
            Map.of("method", "GET", "base", baseUrl, "endpoint", "/v1/dashboard/billing/credit_grants")
        );
        List<String> errors = new ArrayList<>();
        for (Map<String, Object> ep : endpoints) {
            String method = String.valueOf(ep.get("method"));
            String endpoint = String.valueOf(ep.get("endpoint"));
            String url = String.valueOf(ep.get("base")) + endpoint;
            HttpRequest.Builder builder = HttpRequest.newBuilder(URI.create(url)).timeout(Duration.ofSeconds(20));
            if ("POST".equals(method)) {
                String body = objectMapper.writeValueAsString(Map.of("api_key", key));
                builder.header("content-type", "application/json").POST(HttpRequest.BodyPublishers.ofString(body));
            } else {
                builder.header("authorization", "Bearer " + key).GET();
            }
            HttpResponse<String> response = httpClient.send(builder.build(), HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                errors.add(endpoint + ": HTTP " + response.statusCode());
                continue;
            }
            Map<String, Object> json;
            try {
                json = objectMapper.readValue(response.body(), new TypeReference<Map<String, Object>>() {});
            } catch (Exception ex) {
                errors.add(endpoint + ": no JSON");
                continue;
            }
            Map<String, Object> parsed = parseCreditPayload(json);
            if (!Boolean.TRUE.equals(parsed.get("parsed"))) {
                errors.add(endpoint + ": no credit JSON");
                continue;
            }
            parsed.put("success", true);
            parsed.put("endpoint", endpoint);
            parsed.put("status", response.statusCode());
            return parsed;
        }
        return new LinkedHashMap<>(Map.of("success", false, "message", String.join("; ", errors)));
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> parseCreditPayload(Map<String, Object> payload) {
        List<Object> candidates = new ArrayList<>();
        candidates.add(payload);
        Object data = payload.get("data");
        if (data instanceof Map<?, ?> dataMap) {
            candidates.add(dataMap);
            Object usage = dataMap.get("usage");
            if (usage instanceof Map<?, ?>) candidates.add(usage);
        }
        Object usage = payload.get("usage");
        if (usage instanceof Map<?, ?>) candidates.add(usage);
        for (Object obj : candidates) {
            Map<String, Object> item = (Map<String, Object>) obj;
            Object totalAvailable = firstNonNull(item, "remain_quota", "user_remain_quota", "user_quota", "total_available", "total_remaining", "available", "balance", "credit");
            Object totalGranted = firstNonNull(item, "total_granted", "granted", "total", "total_quota");
            Object totalUsed = firstNonNull(item, "user_used_quota", "used_quota", "total_used", "used", "token_used_quota");
            Object dailyCap = firstNonNull(item, "group_daily_cap", "daily_cap", "daily_quota", "daily_limit");
            Object expireTime = firstNonNull(item, "user_quota_expire_time", "quota_expire_time", "expired_time", "expire_time");
            Double available = toDouble(totalAvailable);
            Double granted = toDouble(totalGranted);
            Double used = toDouble(totalUsed);
            Double cap = toDouble(dailyCap);
            Long expire = toLong(expireTime);
            if (available != null || granted != null || used != null || cap != null || expire != null) {
                Map<String, Object> parsed = new LinkedHashMap<>();
                parsed.put("parsed", true);
                parsed.put("object", item.getOrDefault("object", "vietapi_usage"));
                parsed.put("provider", "vietapi");
                parsed.put("total_available", available);
                parsed.put("total_granted", granted);
                parsed.put("total_used", used);
                parsed.put("daily_cap", cap);
                parsed.put("expire_time", expire);
                parsed.put("expire_at", expire == null ? null : Instant.ofEpochSecond(expire).toString());
                parsed.put("unit", "corn");
                parsed.put("unit_divisor", 1_000_000);
                return parsed;
            }
        }
        return new LinkedHashMap<>(Map.of("parsed", false, "object", payload.getOrDefault("object", "unknown")));
    }

    private static Object firstNonNull(Map<String, Object> item, String... keys) {
        for (String key : keys) {
            Object value = item.get(key);
            if (value != null && !String.valueOf(value).isBlank()) return value;
        }
        return null;
    }

    private static Double toDouble(Object value) {
        if (value == null) return null;
        try {
            double n = value instanceof Number number ? number.doubleValue() : Double.parseDouble(String.valueOf(value));
            return Double.isFinite(n) ? n : null;
        } catch (Exception ignored) { return null; }
    }

    private static Long toLong(Object value) {
        Double n = toDouble(value);
        return n == null ? null : n.longValue();
    }

    private static String portalBaseUrlForCredit(String baseUrl) {
        try {
            URI uri = URI.create(baseUrl);
            if ("api.vietapi.tech".equalsIgnoreCase(uri.getHost())) return "https://vietapi.tech";
            return uri.getScheme() + "://" + uri.getHost() + (uri.getPort() > 0 ? ":" + uri.getPort() : "");
        } catch (Exception ignored) { return "https://vietapi.tech"; }
    }

    private List<String> splitChannelKeys(String raw) {
        String trimmed = raw == null ? "" : raw.trim();
        if (trimmed.isBlank()) return List.of();
        if (trimmed.startsWith("[")) {
            try {
                List<String> values = objectMapper.readValue(trimmed, new TypeReference<List<String>>() {});
                return values.stream().map(String::trim).filter(s -> !s.isBlank()).toList();
            } catch (Exception ignored) {
                // fall back to newline parsing below
            }
        }
        return List.of(trimmed.split("\\R+")).stream().map(String::trim).filter(s -> !s.isBlank()).toList();
    }

    private static String maskSecret(String raw) {
        String value = raw == null ? "" : raw.trim();
        if (value.length() <= 10) return "*".repeat(value.length());
        return value.substring(0, 5) + "*".repeat(Math.min(value.length() - 9, 24)) + value.substring(value.length() - 4);
    }
}
