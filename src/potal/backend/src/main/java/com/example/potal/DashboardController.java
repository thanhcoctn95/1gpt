package com.example.potal;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.client.RestTemplate;

@RestController
@RequestMapping("/api/dashboard")
public class DashboardController {
    private static final String LOG_ERROR_CONDITION = "(COALESCE(l.content, '') ~ 'status_code=[45][0-9][0-9]' OR COALESCE(l.other, '') ILIKE '%\"error_code\"%' OR COALESCE(l.other, '') ILIKE '%\"error_type\"%')";
    // HTTP status code: prefer the one embedded in content, fall back to the JSON in `other`.
    private static final String LOG_STATUS_CODE_SQL =
        "NULLIF(COALESCE(substring(l.content from 'status_code=([0-9]{3})'), " +
        "substring(l.other from '\"status_code\"[[:space:]]*:[[:space:]]*([0-9]{3})')), '')";
    // Human-readable error message: strip the `status_code=NNN,` prefix and trailing
    // `(reset after ...)` / `(request id: ...)` noise from content.
    private static final String LOG_ERROR_MESSAGE_SQL =
        "NULLIF(regexp_replace(" +
        "COALESCE(substring(l.content from 'status_code=[0-9]{3},[[:space:]]*(.*)$'), l.content, ''), " +
        "'[[:space:]]*\\((reset after|request id)[^)]*\\)', '', 'g'), '')";
    private static final String LOG_ERROR_TYPE_SQL =
        "NULLIF(substring(l.other from '\"error_type\"[[:space:]]*:[[:space:]]*\"([^\"]+)\"'), '')";
    private static final String LOG_ERROR_CODE_SQL =
        "NULLIF(substring(l.other from '\"error_code\"[[:space:]]*:[[:space:]]*\"([^\"]+)\"'), '')";
    private final JdbcTemplate jdbc;
    private final RestTemplate restTemplate = new RestTemplate();
    private final AuthService authService;
    private final String newApiBaseUrl;

    public DashboardController(JdbcTemplate jdbc, AuthService authService, @Value("${new-api.base-url}") String newApiBaseUrl) {
        this.jdbc = jdbc;
        this.authService = authService;
        this.newApiBaseUrl = newApiBaseUrl;
    }

    @GetMapping("/me")
    public ResponseEntity<?> me(@RequestHeader(value = "Authorization", required = false) String authorization) {
        Map<String, Object> auth = authService.requireUser(authorization);
        long userId = ((Number) auth.get("user_id")).longValue();
        List<Map<String, Object>> subscriptions = jdbc.queryForList("""
            SELECT s.id, s.plan_id, p.title AS plan_title, p.subtitle AS plan_subtitle, p.price_amount, p.quota_reset_period,
                   s.amount_total, s.amount_used, (s.amount_total - s.amount_used) AS amount_left,
                   s.status, s.source, s.upgrade_group,
                   to_timestamp(s.start_time) AS start_time, to_timestamp(s.end_time) AS end_time,
                   to_timestamp(s.last_reset_time) AS last_reset_time, to_timestamp(s.next_reset_time) AS next_reset_time
            FROM user_subscriptions s
            LEFT JOIN subscription_plans p ON p.id = s.plan_id
            WHERE s.user_id=?
            ORDER BY CASE WHEN s.status='active' THEN 0 ELSE 1 END, s.id DESC
            LIMIT 10
            """, userId);
        Map<String, Object> stats24h = jdbc.queryForMap("""
            SELECT count(*)::bigint AS request_24h, COALESCE(sum(quota),0)::bigint AS quota_24h
            FROM logs WHERE user_id=? AND created_at >= extract(epoch from now())::bigint - 86400
            """, userId);
        return ResponseEntity.ok(Map.of("success", true, "data", Map.of("user", auth, "subscriptions", subscriptions, "stats24h", stats24h)));
    }

    @GetMapping("/models")
    public ResponseEntity<?> models(@RequestHeader(value = "Authorization", required = false) String authorization) {
        Map<String, Object> auth = authService.requireUser(authorization);
        // Nguồn models duy nhất từ New API (channels.models), filter by status=1 (admin toggle)
        // và group match. Token model_limits không filter ở listing — New API enforce ở routing.
        String sql = """
            WITH channel_models AS (
              SELECT DISTINCT trim(model) AS model_name
              FROM channels c
              CROSS JOIN LATERAL regexp_split_to_table(COALESCE(c.models, ''), ',') AS model
              WHERE c.status = 1 AND trim(model) <> ''
                AND (c."group" IS NULL OR c."group" = '' OR c."group" = ? OR c."group" = ?)
            )
            SELECT DISTINCT ON (COALESCE(m.model_name, cm.model_name))
                   COALESCE(m.model_name, cm.model_name) AS model_name,
                   COALESCE(m.description, '') AS description,
                   COALESCE(m.icon, '') AS icon,
                   COALESCE(m.status, 1) AS status
            FROM channel_models cm
            LEFT JOIN models m ON m.model_name = cm.model_name AND m.deleted_at IS NULL
            WHERE COALESCE(m.status, 1) = 1
            ORDER BY COALESCE(m.model_name, cm.model_name) ASC, m.id DESC NULLS LAST LIMIT 200""";
        List<Map<String, Object>> rows = jdbc.queryForList(sql, auth.get("user_group"), auth.get("token_group"));
        return ResponseEntity.ok(Map.of("success", true, "data", rows));
    }

    @GetMapping("/model-ratios")
    public ResponseEntity<?> modelRatios(@RequestHeader(value = "Authorization", required = false) String authorization) {
        authService.requireUser(authorization);
        // Ratios are stored in the `options` table as JSON strings:
        //   key=ModelRatio      → {"model-name": ratio, ...}
        //   key=CompletionRatio → {"model-name": ratio, ...}
        //   key=GroupRatio      → {"group-name": ratio, ...}
        String modelRatioJson = "{}";
        String completionRatioJson = "{}";
        String groupRatioJson = "{}";
        try {
            List<Map<String, Object>> opts = jdbc.queryForList(
                "SELECT key, value FROM options WHERE key IN ('ModelRatio','CompletionRatio','GroupRatio')");
            for (Map<String, Object> opt : opts) {
                String key = String.valueOf(opt.get("key"));
                String value = String.valueOf(opt.getOrDefault("value", "{}"));
                switch (key) {
                    case "ModelRatio" -> modelRatioJson = value;
                    case "CompletionRatio" -> completionRatioJson = value;
                    case "GroupRatio" -> groupRatioJson = value;
                }
            }
        } catch (Exception ignored) {}

        // Parse JSON maps and build per-model ratio list
        var modelRatioMap = parseJsonNumberMap(modelRatioJson);
        var completionRatioMap = parseJsonNumberMap(completionRatioJson);
        var groupRatioMap = parseJsonNumberMap(groupRatioJson);

        List<Map<String, Object>> modelRows = new java.util.ArrayList<>();
        for (var entry : modelRatioMap.entrySet()) {
            String modelName = entry.getKey();
            double mr = entry.getValue();
            double cr = completionRatioMap.getOrDefault(modelName, 1.0);
            modelRows.add(Map.of("model_name", modelName, "model_ratio", mr, "completion_ratio", cr));
        }
        // Sort by model name
        modelRows.sort((a, b) -> String.valueOf(a.get("model_name")).compareTo(String.valueOf(b.get("model_name"))));

        List<Map<String, Object>> groupRows = new java.util.ArrayList<>();
        for (var entry : groupRatioMap.entrySet()) {
            groupRows.add(Map.of("name", entry.getKey(), "group_ratio", entry.getValue()));
        }
        groupRows.sort((a, b) -> String.valueOf(a.get("name")).compareTo(String.valueOf(b.get("name"))));

        return ResponseEntity.ok(Map.of("success", true, "data", Map.of(
            "models", modelRows,
            "groups", groupRows
        )));
    }

    private static Map<String, Double> parseJsonNumberMap(String json) {
        Map<String, Double> result = new java.util.LinkedHashMap<>();
        if (json == null || json.isBlank() || json.equals("{}")) return result;
        // Simple JSON object parser for {"key": number, ...} — no nested objects
        String trimmed = json.trim();
        if (trimmed.startsWith("{")) trimmed = trimmed.substring(1);
        if (trimmed.endsWith("}")) trimmed = trimmed.substring(0, trimmed.length() - 1);
        for (String pair : trimmed.split(",")) {
            String[] kv = pair.split(":", 2);
            if (kv.length != 2) continue;
            String key = kv[0].trim().replaceAll("^\"|\"$", "");
            String val = kv[1].trim().replaceAll("^\"|\"$", "");
            if (key.isEmpty()) continue;
            try {
                result.put(key, Double.parseDouble(val));
            } catch (NumberFormatException ignored) {}
        }
        return result;
    }

    @GetMapping("/claude-opus-usage")
    public ResponseEntity<?> claudeOpusUsage(@RequestHeader(value = "Authorization", required = false) String authorization) {
        // Claude Opus thinking is now unlimited for every plan, so this endpoint
        // simply confirms the model is available without tracking remaining requests.
        authService.requireUser(authorization);
        return ResponseEntity.ok(Map.of("success", true, "data", Map.of(
            "active", true,
            "limit", 0,
            "used", 0,
            "remaining", 0,
            "unlimited", true
        )));
    }

    @GetMapping("/logs")
    public ResponseEntity<?> logs(
        @RequestHeader(value = "Authorization", required = false) String authorization,
        @RequestParam(value = "page", defaultValue = "1") int page,
        @RequestParam(value = "size", defaultValue = "10") int size,
        @RequestParam(value = "modelName", required = false) String modelName,
        @RequestParam(value = "status", required = false) String status,
        @RequestParam(value = "startTime", required = false) Long startTime,
        @RequestParam(value = "endTime", required = false) Long endTime
    ) {
        Map<String, Object> auth = authService.requireUser(authorization);
        int safePage = Math.max(1, page);
        int safeSize = Math.max(1, Math.min(size, 1000));
        int offset = (safePage - 1) * safeSize;

        StringBuilder where = new StringBuilder("WHERE l.user_id=?");
        List<Object> args = new ArrayList<>();
        args.add(auth.get("user_id"));

        String safeModel = modelName == null ? "" : modelName.trim();
        if (!safeModel.isBlank()) {
            where.append(" AND l.model_name ILIKE ?");
            args.add("%" + safeModel + "%");
        }

        String safeStatus = status == null ? "" : status.trim().toLowerCase(Locale.ROOT);
        if ("error".equals(safeStatus)) {
            where.append(" AND ").append(LOG_ERROR_CONDITION);
        } else if ("success".equals(safeStatus)) {
            where.append(" AND NOT ").append(LOG_ERROR_CONDITION);
        }

        if (startTime != null && startTime > 0) {
            where.append(" AND l.created_at >= ?");
            args.add(startTime);
        } else {
            where.append(" AND l.created_at >= extract(epoch from now())::bigint - 86400");
        }
        if (endTime != null && endTime > 0) {
            where.append(" AND l.created_at <= ?");
            args.add(endTime);
        }

        Long total = jdbc.queryForObject(
            "SELECT count(*)::bigint FROM logs l " + where,
            Long.class,
            args.toArray()
        );

        List<Object> rowArgs = new ArrayList<>(args);
        rowArgs.add(safeSize);
        rowArgs.add(offset);
        List<Map<String, Object>> rows = jdbc.queryForList("""
            SELECT l.id, l.request_id, l.model_name, l.type, l.prompt_tokens, l.completion_tokens, l.quota, l.use_time,
                   l.is_stream, l.channel_name, l.token_id, l.token_name, l.content, l.other,
                   CASE WHEN %s THEN 'error' ELSE 'success' END AS request_status,
                   %s AS status_code,
                   %s AS error_message,
                   %s AS error_type,
                   %s AS error_code,
                   to_timestamp(l.created_at) AS created_at
            FROM logs l
            %s
            ORDER BY l.id DESC LIMIT ? OFFSET ?
            """.formatted(LOG_ERROR_CONDITION, LOG_STATUS_CODE_SQL, LOG_ERROR_MESSAGE_SQL,
                    LOG_ERROR_TYPE_SQL, LOG_ERROR_CODE_SQL, where), rowArgs.toArray());
        return ResponseEntity.ok(Map.of(
            "success", true,
            "data", Map.of(
                "page", safePage,
                "size", safeSize,
                "total", total == null ? 0 : total,
                "items", rows
            )
        ));
    }

    @PostMapping("/test")
    public ResponseEntity<?> test(@RequestHeader(value = "Authorization", required = false) String authorization, @RequestBody TestRequest request) {
        if (authorization == null || authorization.isBlank()) return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("success", false, "message", "Missing Authorization"));
        request = request.normalized();
        authService.requireUser(authorization);
        Map<String, Object> payload = Map.of(
            "model", request.model(),
            "messages", List.of(Map.of("role", "user", "content", request.prompt())),
            "stream", false,
            "max_tokens", request.maxTokens()
        );
        org.springframework.http.HttpHeaders headers = new org.springframework.http.HttpHeaders();
        headers.set("Authorization", authorization);
        headers.set("Content-Type", "application/json");
        var entity = new org.springframework.http.HttpEntity<>(payload, headers);
        try {
            ResponseEntity<Map> response = restTemplate.postForEntity(newApiBaseUrl + "/v1/chat/completions", entity, Map.class);
            return ResponseEntity.status(response.getStatusCode()).body(Map.of("success", response.getStatusCode().is2xxSuccessful(), "status", response.getStatusCode().value(), "data", response.getBody()));
        } catch (RestClientResponseException err) {
            return ResponseEntity.status(err.getStatusCode()).body(Map.of(
                "success", false,
                "status", err.getStatusCode().value(),
                "message", vietnameseUpstreamMessage(err.getResponseBodyAsString())
            ));
        }
    }



    private static String vietnameseUpstreamMessage(String upstreamBody) {
        String body = upstreamBody == null ? "" : upstreamBody;
        if (body.contains("用户额度不足") || body.contains("subscription quota insufficient") || body.contains("insufficient_user_quota") || body.contains("Gói token") || body.contains("Gói quota")) {
            return "Quota trong ngày không đủ hoặc đã hết. Vui lòng chờ reset quota hằng ngày hoặc nâng gói.";
        }
        return "Request tới New API thất bại. Vui lòng kiểm tra lại model, quota hoặc API key.";
    }

    public record TestRequest(String model, String prompt, Integer maxTokens) {
        TestRequest normalized() {
            String safeModel = model == null || model.isBlank() ? "gpt-5.5" : model.trim();
            if (safeModel.length() > 120 || !safeModel.matches("[A-Za-z0-9._:/\\-]+")) throw new IllegalArgumentException("Invalid model");
            String safePrompt = prompt == null || prompt.isBlank() ? "reply exactly: pong" : prompt.trim();
            if (safePrompt.length() > 4000) throw new IllegalArgumentException("Prompt too long");
            int safeMaxTokens = maxTokens == null ? 20 : Math.max(1, Math.min(maxTokens, 4096));
            return new TestRequest(safeModel, safePrompt, safeMaxTokens);
        }
    }
}
