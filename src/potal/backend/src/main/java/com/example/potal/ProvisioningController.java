package com.example.potal;

import java.security.SecureRandom;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/admin")
public class ProvisioningController {
    private static final Logger log = LoggerFactory.getLogger(ProvisioningController.class);
    private static final ZoneId RESET_ZONE = ZoneId.systemDefault();
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final long TOKEN_PACK_SECONDS = 100L * 365 * 24 * 60 * 60;
    private static final String LOG_ERROR_CONDITION = "(COALESCE(l.content, '') ~ 'status_code=[45][0-9][0-9]' OR COALESCE(l.other, '') ILIKE '%\"error_code\"%' OR COALESCE(l.other, '') ILIKE '%\"error_type\"%')";
    private final JdbcTemplate jdbc;
    private final AuthService authService;
    private final String newApiPublicBaseUrl;

    public ProvisioningController(JdbcTemplate jdbc, AuthService authService, @Value("${new-api.public-base-url}") String newApiPublicBaseUrl) {
        this.jdbc = jdbc;
        this.authService = authService;
        this.newApiPublicBaseUrl = newApiPublicBaseUrl;
        this.jdbc.execute("ALTER TABLE user_subscriptions ADD COLUMN IF NOT EXISTS daily_extra_quota BIGINT NOT NULL DEFAULT 0");
        // model_list: CSV of model names a plan grants access to. NULL = all active models from channels.
        this.jdbc.execute("ALTER TABLE subscription_plans ADD COLUMN IF NOT EXISTS model_list TEXT");
        // Widen price_amount so it can store full VND (was numeric(10,6) — max 9999, too small).
        this.jdbc.execute("ALTER TABLE subscription_plans ALTER COLUMN price_amount TYPE numeric(14,2)");
        seedDefaultPlans();
        seedTokenPacks();
    }

    /**
     * Seeds and updates the default monthly plans exposed on the portal.
     * Prices are full VND; total_amount is the daily GPT-5.5 token quota.
     */
    private void seedDefaultPlans() {
        long now = Instant.now().getEpochSecond();
        Object[][] defaults = {
            {"BASIC", "Plus",  "20M token GPT-5.5/ngày; API key riêng; Dashboard usage", 549_000, 10, "",    20_000_000},
            {"PRO",   "Pro",   "40M token GPT-5.5/ngày; Hỗ trợ setup code agent",       879_000, 20, "",    40_000_000},
            {"ULTRA", "Ultra", "60M token GPT-5.5/ngày; Log usage chi tiết; Hỗ trợ riêng", 1_199_000, 30, "", 60_000_000},
            {"S-UTRA", "Max",  "80M token GPT-5.5/ngày; Key phụ cho team; Quota rõ hằng ngày", 1_549_000, 40, "max", 80_000_000},
        };
        for (Object[] d : defaults) {
            String oldTitle = (String) d[0];
            String title = (String) d[1];
            List<Map<String, Object>> existing = jdbc.queryForList("""
                SELECT id FROM subscription_plans
                WHERE upper(title)=upper(?) OR upper(title)=upper(?)
                ORDER BY id ASC LIMIT 1
                """, oldTitle, title);
            long canonicalId;
            if (!existing.isEmpty()) {
                canonicalId = ((Number) existing.get(0).get("id")).longValue();
                jdbc.update("""
                    UPDATE subscription_plans
                    SET title=?, subtitle=?, price_amount=?, currency='VND', duration_unit='month', duration_value=1, custom_seconds=0,
                        enabled=true, sort_order=?, max_purchase_per_user=0, upgrade_group=?, total_amount=?,
                        quota_reset_period='daily', quota_reset_custom_seconds=0, model_list=NULL, updated_at=?
                    WHERE id=?
                    """, title, d[2], d[3], d[4], d[5], d[6], now, canonicalId);
            } else {
                canonicalId = jdbc.queryForObject("""
                    INSERT INTO subscription_plans
                      (title, subtitle, price_amount, currency, duration_unit, duration_value, custom_seconds,
                       enabled, sort_order, stripe_price_id, creem_product_id,
                       max_purchase_per_user, upgrade_group, total_amount, quota_reset_period, quota_reset_custom_seconds,
                       model_list, created_at, updated_at)
                    VALUES (?, ?, ?, 'VND', 'month', 1, 0, true, ?, '', '', 0, ?, ?, 'daily', 0, NULL, ?, ?)
                    RETURNING id
                    """, Long.class, title, d[2], d[3], d[4], d[5], d[6], now, now);
            }
            jdbc.update("""
                UPDATE subscription_plans
                SET enabled=false, updated_at=?
                WHERE id<>?
                  AND (upper(title)=upper(?) OR upper(title)=upper(?))
                """, now, canonicalId, oldTitle, title);
        }
    }
    private void seedTokenPacks() {
        long now = Instant.now().getEpochSecond();
        Object[][] defaults = {
            {"Mini",     "50M token — gói one-time",  69_000, 10,  50_000_000},
            {"Starter",  "100M token — gói one-time", 129_000, 20, 100_000_000},
            {"Standard", "250M token — gói one-time", 299_000, 30, 250_000_000},
            {"Power",    "500M token — gói one-time", 549_000, 40, 500_000_000},
        };
        for (Object[] d : defaults) {
            String title = (String) d[0];
            List<Map<String, Object>> existing = jdbc.queryForList("""
                SELECT id FROM subscription_plans
                WHERE upper(title)=upper(?) AND quota_reset_period='never'
                ORDER BY id ASC LIMIT 1
                """, title);
            long canonicalId;
            if (!existing.isEmpty()) {
                canonicalId = ((Number) existing.get(0).get("id")).longValue();
                jdbc.update("""
                    UPDATE subscription_plans
                    SET title=?, subtitle=?, price_amount=?, currency='VND', duration_unit='custom', duration_value=0,
                        custom_seconds=?, enabled=true, sort_order=?, max_purchase_per_user=0, upgrade_group='', total_amount=?,
                        quota_reset_period='never', quota_reset_custom_seconds=0, model_list=NULL, updated_at=?
                    WHERE id=?
                    """, title, d[1], d[2], TOKEN_PACK_SECONDS, d[3], d[4], now, canonicalId);
            } else {
                canonicalId = jdbc.queryForObject("""
                    INSERT INTO subscription_plans
                      (title, subtitle, price_amount, currency, duration_unit, duration_value, custom_seconds,
                       enabled, sort_order, stripe_price_id, creem_product_id,
                       max_purchase_per_user, upgrade_group, total_amount, quota_reset_period, quota_reset_custom_seconds,
                       model_list, created_at, updated_at)
                    VALUES (?, ?, ?, 'VND', 'custom', 0, ?, true, ?, '', '', 0, '', ?, 'never', 0, NULL, ?, ?)
                    RETURNING id
                    """, Long.class, title, d[1], d[2], TOKEN_PACK_SECONDS, d[3], d[4], now, now);
            }
            jdbc.update("""
                UPDATE subscription_plans
                SET enabled=false, updated_at=?
                WHERE id<>?
                  AND upper(title)=upper(?)
                  AND quota_reset_period='never'
                """, now, canonicalId, title);
        }
    }


    @GetMapping("/plans")
    public Map<String, Object> plans(@RequestHeader(value = "Authorization", required = false) String authorization) {
        authService.requireAdmin(authorization);
        List<Map<String, Object>> rows = jdbc.queryForList("""
            SELECT id, title, subtitle, price_amount, total_amount, quota_reset_period,
                   upgrade_group, sort_order, enabled, model_list
            FROM subscription_plans
            WHERE enabled = true
            ORDER BY sort_order ASC, id ASC
            LIMIT 100
            """);
        return Map.of("success", true, "data", rows);
    }

    // ---- plan CRUD (token pack + monthly) ----

    @PostMapping("/plans/create")
    @Transactional
    public ResponseEntity<?> createPlan(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @RequestBody PlanRequest request) {
        authService.requireAdmin(authorization);
        PlanRequest safe = (request == null ? PlanRequest.empty() : request).normalized();
        long now = Instant.now().getEpochSecond();
        long planId = upsertPlanRow(safe, 0, now);
        return ResponseEntity.ok(Map.of("success", true, "data", Map.of(
            "planId", planId,
            "title", safe.title(),
            "quotaResetPeriod", safe.quotaResetPeriod()
        )));
    }

    @PutMapping("/plans/{id}")
    @Transactional
    public ResponseEntity<?> updatePlan(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @PathVariable long id,
            @RequestBody PlanRequest request) {
        authService.requireAdmin(authorization);
        PlanRequest safe = (request == null ? PlanRequest.empty() : request).normalized();
        long now = Instant.now().getEpochSecond();
        long planId = upsertPlanRow(safe, id, now);
        return ResponseEntity.ok(Map.of("success", true, "data", Map.of(
            "planId", planId,
            "title", safe.title(),
            "quotaResetPeriod", safe.quotaResetPeriod()
        )));
    }

    /**
     * Insert (existingId <= 0) or update a subscription_plans row.
     * Derives duration_unit/custom_seconds from quota_reset_period:
     *   - "never" (token pack): duration_unit='custom', custom_seconds=100 years, no daily reset
     *   - "daily" (monthly): duration_unit='month', duration_value=1, daily reset
     */
    private long upsertPlanRow(PlanRequest safe, long existingId, long now) {
        boolean isTokenPack = "never".equals(safe.quotaResetPeriod());
        String durationUnit = isTokenPack ? "custom" : "month";
        int durationValue = isTokenPack ? 0 : 1;
        long customSeconds = isTokenPack ? (100L * 365 * 24 * 60 * 60) : 0L;
        String resetPeriod = isTokenPack ? "never" : "daily";
        String safeGroup = safe.upgradeGroup() == null ? "" : safe.upgradeGroup();
        // model_list: NULL means "all active models from channels". Empty string means no models.
        // Normalize: if the list is blank/null → store NULL (all models).
        String rawModelList = safe.modelList() == null ? "" : safe.modelList().trim();
        String modelListValue = rawModelList.isEmpty() ? null : SqlUtil.uniqueCsv(rawModelList);

        if (existingId > 0) {
            int rows = jdbc.update("""
                UPDATE subscription_plans
                SET title=?, subtitle=?, price_amount=?, currency='VND', duration_unit=?, duration_value=?, custom_seconds=?,
                    enabled=true, sort_order=?, upgrade_group=?, total_amount=?,
                    quota_reset_period=?, quota_reset_custom_seconds=0, model_list=?, updated_at=?
                WHERE id=? AND enabled=true
                """, safe.title(), safe.subtitle(), safe.priceAmount(), durationUnit, durationValue, customSeconds,
                safe.sortOrder(), safeGroup, safe.totalAmount(), resetPeriod, modelListValue, now, existingId);
            if (rows == 0) throw new IllegalArgumentException("Plan not found or disabled");
            return existingId;
        }
        return jdbc.queryForObject("""
            INSERT INTO subscription_plans
              (title, subtitle, price_amount, currency, duration_unit, duration_value, custom_seconds,
               enabled, sort_order, stripe_price_id, creem_product_id,
               max_purchase_per_user, upgrade_group, total_amount, quota_reset_period, quota_reset_custom_seconds,
               model_list, created_at, updated_at)
            VALUES (?, ?, ?, 'VND', ?, ?, ?, true, ?, '', '', 0, ?, ?, ?, 0, ?, ?, ?)
            RETURNING id
            """, Long.class, safe.title(), safe.subtitle(), safe.priceAmount(), durationUnit, durationValue,
            customSeconds, safe.sortOrder(), safeGroup, safe.totalAmount(), resetPeriod, modelListValue, now, now);
    }

    @GetMapping("/provisioned-users")
    public Map<String, Object> provisionedUsers(@RequestHeader(value = "Authorization", required = false) String authorization) {
        authService.requireAdmin(authorization);
        List<Map<String, Object>> rows = jdbc.queryForList("""
            SELECT u.id AS user_id, u.username, u.display_name, u.status AS user_status,
                   t.id AS token_id, t.name AS token_name, t.status AS token_status,
                   CASE WHEN length(t.key) <= 8 THEN repeat('*', length(t.key)) ELSE left(t.key, 4) || repeat('*', GREATEST(length(t.key)-8, 0)) || right(t.key, 4) END AS key_masked,
                   s.id AS subscription_id, s.status AS subscription_status,
                   p.title AS plan_title, s.amount_total, s.amount_used, COALESCE(s.daily_extra_quota, 0) AS daily_extra_quota,
                   COALESCE(p.quota_reset_period, 'daily') AS quota_reset_period,
                   (s.amount_total - s.amount_used) AS amount_left,
                   to_timestamp(s.start_time) AS start_time,
                   to_timestamp(s.end_time) AS end_time,
                   to_timestamp(s.last_reset_time) AS last_reset_time,
                   to_timestamp(s.next_reset_time) AS next_reset_time
            FROM users u
            LEFT JOIN tokens t ON t.user_id = u.id AND t.deleted_at IS NULL
            LEFT JOIN user_subscriptions s ON s.user_id = u.id AND s.status = 'active'
            LEFT JOIN subscription_plans p ON p.id = s.plan_id
            WHERE u.deleted_at IS NULL
            ORDER BY u.id DESC
            LIMIT 50
            """);
        return Map.of("success", true, "data", rows);
    }

    @GetMapping("/logs")
    public ResponseEntity<?> adminLogs(
        @RequestHeader(value = "Authorization", required = false) String authorization,
        @RequestParam(value = "page", defaultValue = "1") int page,
        @RequestParam(value = "size", defaultValue = "20") int size,
        @RequestParam(value = "userId", required = false) Long userId,
        @RequestParam(value = "username", required = false) String username,
        @RequestParam(value = "modelName", required = false) String modelName,
        @RequestParam(value = "status", required = false) String status,
        @RequestParam(value = "startTime", required = false) Long startTime,
        @RequestParam(value = "endTime", required = false) Long endTime
    ) {
        authService.requireAdmin(authorization);
        int safePage = Math.max(1, page);
        int safeSize = Math.max(1, Math.min(size, 100));
        int offset = (safePage - 1) * safeSize;

        StringBuilder where = new StringBuilder("WHERE 1=1");
        List<Object> args = new ArrayList<>();
        if (userId != null && userId > 0) {
            where.append(" AND l.user_id = ?");
            args.add(userId);
        }
        String safeUsername = username == null ? "" : username.trim();
        if (!safeUsername.isBlank()) {
            where.append(" AND u.username ILIKE ?");
            args.add("%" + safeUsername + "%");
        }
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
        }
        if (endTime != null && endTime > 0) {
            where.append(" AND l.created_at <= ?");
            args.add(endTime);
        }

        Long total = jdbc.queryForObject(
            "SELECT count(*)::bigint FROM logs l JOIN users u ON u.id = l.user_id " + where,
            Long.class, args.toArray());

        List<Object> rowArgs = new ArrayList<>(args);
        rowArgs.add(safeSize);
        rowArgs.add(offset);
        String rowsSql = "SELECT l.id, l.request_id, l.user_id, u.username, l.model_name, l.type, " +
            "l.prompt_tokens, l.completion_tokens, l.quota, l.use_time, " +
            "l.is_stream, l.channel_name, l.token_id, l.token_name, l.content, l.other, " +
            "CASE WHEN " + LOG_ERROR_CONDITION + " THEN 'error' ELSE 'success' END AS request_status, " +
            "NULLIF(substring(l.content from 'status_code=([0-9]{3})'), '') AS status_code, " +
            "substring(l.content from 'status_code=[0-9]{3},[[:space:]]*([^()]+)') AS error_message, " +
            "to_timestamp(l.created_at) AS created_at " +
            "FROM logs l JOIN users u ON u.id = l.user_id " + where +
            " ORDER BY l.id DESC LIMIT ? OFFSET ?";
        List<Map<String, Object>> rows = jdbc.queryForList(rowsSql,
            rowArgs.toArray());

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

    @GetMapping("/logs/stats")
    public ResponseEntity<?> adminLogsStats(
        @RequestHeader(value = "Authorization", required = false) String authorization,
        @RequestParam(value = "userId", required = false) Long userId,
        @RequestParam(value = "username", required = false) String username,
        @RequestParam(value = "modelName", required = false) String modelName,
        @RequestParam(value = "status", required = false) String status,
        @RequestParam(value = "startTime", required = false) Long startTime,
        @RequestParam(value = "endTime", required = false) Long endTime
    ) {
        authService.requireAdmin(authorization);

        StringBuilder where = new StringBuilder("WHERE 1=1");
        List<Object> args = new ArrayList<>();
        if (userId != null && userId > 0) {
            where.append(" AND l.user_id = ?");
            args.add(userId);
        }
        String safeUsername = username == null ? "" : username.trim();
        if (!safeUsername.isBlank()) {
            where.append(" AND u.username ILIKE ?");
            args.add("%" + safeUsername + "%");
        }
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
        }
        if (endTime != null && endTime > 0) {
            where.append(" AND l.created_at <= ?");
            args.add(endTime);
        }

        List<Map<String, Object>> byModel = jdbc.queryForList(
            "SELECT l.model_name AS model, " +
            "       COUNT(*)::bigint AS req_count, " +
            "       COALESCE(SUM(l.quota), 0)::bigint AS total_quota, " +
            "       COALESCE(SUM(l.prompt_tokens), 0)::bigint AS tokens_in, " +
            "       COALESCE(SUM(l.completion_tokens), 0)::bigint AS tokens_out, " +
            "       SUM(CASE WHEN " + LOG_ERROR_CONDITION + " THEN 1 ELSE 0 END)::bigint AS error_count " +
            "FROM logs l JOIN users u ON u.id = l.user_id " + where + " " +
            "GROUP BY l.model_name ORDER BY total_quota DESC LIMIT 20",
            args.toArray());

        Map<String, Object> totals = jdbc.queryForMap(
            "SELECT COUNT(*)::bigint AS req_count, " +
            "       COALESCE(SUM(l.quota), 0)::bigint AS total_quota, " +
            "       COALESCE(SUM(l.prompt_tokens), 0)::bigint AS tokens_in, " +
            "       COALESCE(SUM(l.completion_tokens), 0)::bigint AS tokens_out, " +
            "       SUM(CASE WHEN " + LOG_ERROR_CONDITION + " THEN 1 ELSE 0 END)::bigint AS error_count " +
            "FROM logs l JOIN users u ON u.id = l.user_id " + where,
            args.toArray());

        List<Map<String, Object>> byUser = jdbc.queryForList(
            "SELECT u.username AS username, u.id AS user_id, " +
            "       COUNT(*)::bigint AS req_count, " +
            "       COALESCE(SUM(l.quota), 0)::bigint AS total_quota " +
            "FROM logs l JOIN users u ON u.id = l.user_id " + where + " " +
            "GROUP BY u.username, u.id ORDER BY total_quota DESC LIMIT 10",
            args.toArray());

        return ResponseEntity.ok(Map.of(
            "success", true,
            "data", Map.of(
                "totals", totals,
                "byModel", byModel,
                "byUser", byUser
            )
        ));
    }

    @PostMapping("/provision-user")
    @Transactional
    public ResponseEntity<?> provisionUser(@RequestHeader(value = "Authorization", required = false) String authorization, @RequestBody ProvisionRequest request) {
        authService.requireAdmin(authorization);
        ProvisionRequest safeRequest = (request == null ? new ProvisionRequest("", null) : request).normalized();
        long now = Instant.now().getEpochSecond();
        long end = Instant.now().plusSeconds(31L * 24 * 60 * 60).getEpochSecond();
        long nextReset = LocalDate.now(RESET_ZONE).plusDays(1).atStartOfDay(RESET_ZONE).toEpochSecond();

        Map<String, Object> plan = getPlan(safeRequest.planId());
        long totalAmount = ((Number) plan.get("total_amount")).longValue();
        String upgradeGroup = String.valueOf(plan.getOrDefault("upgrade_group", ""));
        String resetPeriod = String.valueOf(plan.getOrDefault("quota_reset_period", "daily"));
        long userId = ensureUser(safeRequest.username(), now);

        // Token pack (quota_reset_period='never'): always CREATE a new subscription row
        // so the user can stack a token pack on top of an existing monthly plan.
        // Monthly (daily reset): reuse existing active sub (update in place).
        long subscriptionId;
        if ("never".equals(resetPeriod)) {
            subscriptionId = createTokenPackSubscription(userId, safeRequest.planId(), totalAmount, now, upgradeGroup);
        } else {
            subscriptionId = ensureSubscription(userId, safeRequest.planId(), totalAmount, now, end, nextReset, upgradeGroup);
        }

        // Cập nhật users.group nếu plan có upgrade_group
        if (!upgradeGroup.isBlank()) {
            jdbc.update("UPDATE users SET \"group\"=? WHERE id=?", upgradeGroup, userId);
        }

        return ResponseEntity.ok(Map.of("success", true, "data", Map.of(
            "userId", userId,
            "username", safeRequest.username(),
            "planId", safeRequest.planId(),
            "planTitle", plan.get("title"),
            "subscriptionId", subscriptionId,
            "planType", "never".equals(resetPeriod) ? "token" : "monthly"
        )));
    }

    @PostMapping("/user-token")
    @Transactional
    public ResponseEntity<?> userToken(@RequestHeader(value = "Authorization", required = false) String authorization, @RequestBody UserTokenRequest request) {
        authService.requireAdmin(authorization);
        UserTokenRequest safeRequest = (request == null ? new UserTokenRequest(0L, "") : request).normalized();
        Map<String, Object> user = findUser(safeRequest);
        long userId = ((Number) user.get("id")).longValue();
        String username = String.valueOf(user.get("username"));
        Map<String, Object> token = ensureSingleToken(userId, username, Instant.now().getEpochSecond());
        String rawKey = String.valueOf(token.get("key"));
        String fullKey = rawKey.startsWith("sk-") ? rawKey : "sk-" + rawKey;
        String openAiBaseUrl = newApiPublicBaseUrl.endsWith("/v1") ? newApiPublicBaseUrl : newApiPublicBaseUrl + "/v1";

        return ResponseEntity.ok(Map.of("success", true, "data", Map.of(
            "userId", userId,
            "username", username,
            "tokenId", token.get("id"),
            "tokenName", token.get("name"),
            "apiKey", fullKey,
            "keyMasked", maskKey(fullKey),
            "baseUrl", openAiBaseUrl
        )));
    }

    @PostMapping("/grant-daily-extra-quota")
    @Transactional
    public ResponseEntity<?> grantDailyExtraQuota(@RequestHeader(value = "Authorization", required = false) String authorization, @RequestBody DailyExtraQuotaRequest request) {
        authService.requireAdmin(authorization);
        DailyExtraQuotaRequest safeRequest = (request == null ? new DailyExtraQuotaRequest(0L, null) : request).normalized();
        Map<String, Object> user = findUser(new UserTokenRequest(safeRequest.userId(), ""));
        long now = Instant.now().getEpochSecond();

        List<Map<String, Object>> rows = jdbc.queryForList("""
            SELECT s.id, s.amount_total, s.amount_used, COALESCE(s.daily_extra_quota, 0) AS daily_extra_quota,
                   COALESCE(p.quota_reset_period, 'daily') AS quota_reset_period
            FROM user_subscriptions s
            LEFT JOIN subscription_plans p ON p.id = s.plan_id
            WHERE s.user_id=? AND s.status='active' AND s.end_time > ?
            ORDER BY s.id DESC LIMIT 1
            FOR UPDATE OF s
            """, safeRequest.userId(), now);
        if (rows.isEmpty()) throw new IllegalArgumentException("User has no active subscription");

        long subscriptionId = ((Number) rows.get(0).get("id")).longValue();
        long currentTotal = ((Number) rows.get(0).get("amount_total")).longValue();
        long currentUsed = ((Number) rows.get(0).get("amount_used")).longValue();
        long currentExtra = ((Number) rows.get(0).get("daily_extra_quota")).longValue();
        String resetPeriod = String.valueOf(rows.get(0).get("quota_reset_period"));
        long nextTotal = currentTotal + safeRequest.amount();

        if ("never".equals(resetPeriod)) {
            // Token pack: increase amount_total permanently. Do NOT set daily_extra_quota —
            // the midnight cron reverts amount_total to plan_total for rows with daily_extra_quota > 0,
            // which would erase the granted tokens.
            jdbc.update("""
                UPDATE user_subscriptions
                SET amount_total=?, updated_at=?
                WHERE id=?
                """, nextTotal, now, subscriptionId);
            return ResponseEntity.ok(Map.of("success", true, "data", Map.of(
                "userId", safeRequest.userId(),
                "username", user.get("username"),
                "subscriptionId", subscriptionId,
                "grantedAmount", safeRequest.amount(),
                "dailyExtraQuota", currentExtra,
                "amountTotal", nextTotal,
                "amountUsed", currentUsed,
                "amountLeft", nextTotal - currentUsed,
                "planType", "token"
            )));
        }

        // Monthly plan: daily bonus — increase amount_total AND daily_extra_quota (reverted at midnight).
        long nextExtra = currentExtra + safeRequest.amount();
        jdbc.update("""
            UPDATE user_subscriptions
            SET amount_total=?, daily_extra_quota=?, updated_at=?
            WHERE id=?
            """, nextTotal, nextExtra, now, subscriptionId);

        return ResponseEntity.ok(Map.of("success", true, "data", Map.of(
            "userId", safeRequest.userId(),
            "username", user.get("username"),
            "subscriptionId", subscriptionId,
            "grantedAmount", safeRequest.amount(),
            "dailyExtraQuota", nextExtra,
            "amountTotal", nextTotal,
            "amountUsed", currentUsed,
            "amountLeft", nextTotal - currentUsed,
            "planType", "monthly"
        )));
    }

    private Map<String, Object> getPlan(long planId) {
        List<Map<String, Object>> rows = jdbc.queryForList("SELECT id, title, total_amount, upgrade_group, quota_reset_period, model_list FROM subscription_plans WHERE id=? AND enabled=true LIMIT 1", planId);
        if (rows.isEmpty()) throw new IllegalArgumentException("Invalid plan");
        return rows.get(0);
    }

    private Map<String, Object> findUser(UserTokenRequest request) {
        List<Map<String, Object>> rows;
        if (request.userId() > 0) {
            rows = jdbc.queryForList("SELECT id, username FROM users WHERE id=? AND deleted_at IS NULL LIMIT 1", request.userId());
        } else {
            rows = jdbc.queryForList("SELECT id, username FROM users WHERE username=? AND deleted_at IS NULL LIMIT 1", request.username());
        }
        if (rows.isEmpty()) throw new IllegalArgumentException("User not found");
        return rows.get(0);
    }

    private long ensureUser(String username, long now) {
        List<Map<String, Object>> existing = jdbc.queryForList("SELECT id FROM users WHERE username=? AND deleted_at IS NULL LIMIT 1", username);
        if (!existing.isEmpty()) return ((Number) existing.get(0).get("id")).longValue();
        return jdbc.queryForObject("""
            INSERT INTO users
              (username, password, display_name, role, status, email, quota, used_quota, request_count, "group", aff_code, aff_count, aff_quota, aff_history, inviter_id, linux_do_id, setting, remark, stripe_customer, created_at, last_login_at)
            VALUES (?, ?, ?, 1, 1, '', 0, 0, 0, 'default', ?, 0, 0, 0, 0, '', '', 'Provisioned by portal admin', '', ?, 0)
            RETURNING id
            """, Long.class, username, randomPassword(), username, generateAffCode(), now);
    }

    private long ensureSubscription(long userId, long planId, long amountTotal, long now, long end, long nextReset, String upgradeGroup) {
        String safeUpgradeGroup = (upgradeGroup == null || upgradeGroup.isBlank()) ? "" : upgradeGroup;
        // Only find existing MONTHLY subs to update in place. Token packs (quota_reset_period='never')
        // must never be clobbered — if a user has a token pack (higher id) and admin re-provisions a
        // monthly plan, we insert a new monthly sub rather than overwriting the token pack.
        List<Map<String, Object>> existing = jdbc.queryForList("""
            SELECT s.id FROM user_subscriptions s
            LEFT JOIN subscription_plans p ON p.id = s.plan_id
            WHERE s.user_id=? AND s.status='active'
              AND COALESCE(p.quota_reset_period, 'daily') != 'never'
            ORDER BY s.id DESC LIMIT 1
            """, userId);
        if (!existing.isEmpty()) {
            long id = ((Number) existing.get(0).get("id")).longValue();
            // Capture current user group as prev_user_group for potential rollback
            String prevGroup = jdbc.queryForObject(
                "SELECT COALESCE(\"group\", 'default') FROM users WHERE id = ?", String.class, userId);
            jdbc.update("""
                UPDATE user_subscriptions
                SET plan_id=?, amount_total=?, amount_used=0, daily_extra_quota=0, start_time=?, end_time=?,
                    last_reset_time=?, next_reset_time=?, upgrade_group=?, prev_user_group=?, source='portal-admin', updated_at=?
                WHERE id=?
                """, planId, amountTotal, now, end, now, nextReset, safeUpgradeGroup, prevGroup, now, id);
            return id;
        }
        return jdbc.queryForObject("""
            INSERT INTO user_subscriptions
              (user_id, plan_id, amount_total, amount_used, start_time, end_time, status, source,
               last_reset_time, next_reset_time, upgrade_group, prev_user_group, created_at, updated_at)
            VALUES (?, ?, ?, 0, ?, ?, 'active', 'portal-admin', ?, ?, ?, '', ?, ?)
            RETURNING id
            """, Long.class, userId, planId, amountTotal, now, end, now, nextReset, safeUpgradeGroup, now, now);
    }

    /**
     * Create a NEW token-pack subscription row (quota_reset_period='never').
     * Unlike ensureSubscription, this always inserts — allowing a user to stack
     * a token pack on top of an existing monthly subscription.
     * - end_time = now + 100 years (effectively no expiry; New API billing requires end_time > now)
     * - next_reset_time = 0 (New API ResetDueSubscriptions skips next_reset_time=0 rows)
     * - daily_extra_quota = 0 (never set, so midnight cron never reverts amount_total)
     */
    private long createTokenPackSubscription(long userId, long planId, long amountTotal, long now, String upgradeGroup) {
        String safeUpgradeGroup = (upgradeGroup == null || upgradeGroup.isBlank()) ? "" : upgradeGroup;
        long endTime = now + 100L * 365 * 24 * 60 * 60;
        String prevGroup = "";
        if (!safeUpgradeGroup.isBlank()) {
            prevGroup = jdbc.queryForObject("SELECT COALESCE(\"group\", 'default') FROM users WHERE id = ?", String.class, userId);
        }
        return jdbc.queryForObject("""
            INSERT INTO user_subscriptions
              (user_id, plan_id, amount_total, amount_used, start_time, end_time, status, source,
               last_reset_time, next_reset_time, upgrade_group, prev_user_group, daily_extra_quota, created_at, updated_at)
            VALUES (?, ?, ?, 0, ?, ?, 'active', 'portal-admin', 0, 0, ?, ?, 0, ?, ?)
            RETURNING id
            """, Long.class, userId, planId, amountTotal, now, endTime, safeUpgradeGroup, prevGroup, now, now);
    }

    /**
     * Ensure the user has exactly one token, with model_limits derived from their active
     * subscription plan(s). If ANY active plan has model_list=NULL, the token gets
     * model_limits_enabled=false (access to all active models from New API channels —
     * dynamic, not hardcoded). Otherwise, the token is restricted to the union of all
     * active plans' model_list values.
     */
    private Map<String, Object> ensureSingleToken(long userId, String username, long now) {
        // Query all active subscriptions' plan model_list values.
        List<Map<String, Object>> planRows = jdbc.queryForList("""
            SELECT p.model_list
            FROM user_subscriptions s
            JOIN subscription_plans p ON p.id = s.plan_id
            WHERE s.user_id=? AND s.status='active' AND s.end_time > ?
            """, userId, now);

        // If any plan has model_list=NULL → all models (no restriction).
        boolean hasNullModelList = false;
        java.util.Set<String> modelSet = new java.util.LinkedHashSet<>();
        for (Map<String, Object> row : planRows) {
            Object ml = row.get("model_list");
            if (ml == null) {
                hasNullModelList = true;
                break;
            }
            String csv = String.valueOf(ml).trim();
            if (csv.isEmpty()) {
                hasNullModelList = true;
                break;
            }
            for (String m : csv.split(",")) {
                String trimmed = m.trim();
                if (!trimmed.isEmpty()) modelSet.add(trimmed);
            }
        }

        boolean modelLimitsEnabled = !hasNullModelList && !modelSet.isEmpty();
        String modelLimits = modelLimitsEnabled ? String.join(",", modelSet) : null;

        List<Map<String, Object>> existing = jdbc.queryForList("SELECT id, name, key FROM tokens WHERE user_id=? AND deleted_at IS NULL ORDER BY id ASC LIMIT 1", userId);
        if (!existing.isEmpty()) {
            long tokenId = ((Number) existing.get(0).get("id")).longValue();
            jdbc.update("""
                UPDATE tokens
                SET model_limits_enabled=?, model_limits=?
                WHERE id=?
                """, modelLimitsEnabled, modelLimits, tokenId);
            return jdbc.queryForMap("SELECT id, name, key FROM tokens WHERE id=?", tokenId);
        }
        String rawKey = generateRawTokenKey();
        return jdbc.queryForMap("""
            INSERT INTO tokens
              (user_id, key, status, name, created_time, accessed_time, expired_time, remain_quota, unlimited_quota,
               model_limits_enabled, model_limits, allow_ips, used_quota, "group", cross_group_retry)
            VALUES (?, ?, 1, ?, ?, ?, -1, 0, true, ?, ?, '', 0, 'default', false)
            RETURNING id, name, key
            """, userId, rawKey, username + "-token", now, now, modelLimitsEnabled, modelLimits);
    }

    private static String generateRawTokenKey() {
        byte[] bytes = new byte[24];
        RANDOM.nextBytes(bytes);
        return HexFormat.of().formatHex(bytes);
    }

    private static String randomPassword() {
        return "portal-provisioned";
    }

    private static String generateAffCode() {
        return generateRawTokenKey().substring(0, 16);
    }

    private static String maskKey(String key) {
        if (key == null || key.isBlank()) return "";
        if (key.length() <= 8) return "*".repeat(key.length());
        return key.substring(0, 6) + "********" + key.substring(key.length() - 4);
    }

    // ---- manual quota reset endpoint (Bug #6) ----

    /**
     * Manually reset a subscription's used quota to 0 and revert any daily extra quota
     * back to the plan's original amount_total. Useful when the New API cron fails
     * or the admin needs to force a reset.
     */
    @PostMapping("/subscriptions/{subId}/reset-quota")
    @Transactional
    public ResponseEntity<?> resetSubscriptionQuota(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @org.springframework.web.bind.annotation.PathVariable long subId) {
        authService.requireAdmin(authorization);

        // Get subscription and its plan's original total
        List<Map<String, Object>> rows = jdbc.queryForList("""
            SELECT s.id, s.user_id, s.plan_id, s.amount_total, s.amount_used,
                   COALESCE(s.daily_extra_quota, 0) AS daily_extra_quota,
                   p.total_amount AS plan_total, p.quota_reset_period
            FROM user_subscriptions s
            LEFT JOIN subscription_plans p ON p.id = s.plan_id
            WHERE s.id = ?
            """, subId);

        if (rows.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("success", false, "message", "Subscription not found"));
        }

        Map<String, Object> sub = rows.get(0);
        long planTotal = ((Number) sub.getOrDefault("plan_total", 0)).longValue();
        long dailyExtra = ((Number) sub.get("daily_extra_quota")).longValue();
        long usedBefore = ((Number) sub.get("amount_used")).longValue();
        String resetPeriod = String.valueOf(sub.getOrDefault("quota_reset_period", "daily"));

        // Token packs (quota_reset_period='never') use quota until exhausted — resetting
        // would grant free tokens. Refuse; admin should use "Cấp thêm" to add tokens instead.
        if ("never".equals(resetPeriod)) {
            return ResponseEntity.badRequest().body(Map.of("success", false,
                "message", "Không thể reset gói token (dùng đến khi hết). Dùng 'Cấp thêm' để bổ sung token."));
        }

        long now = Instant.now().getEpochSecond();
        long nextReset = 0;
        if ("daily".equals(resetPeriod)) {
            nextReset = LocalDate.now(RESET_ZONE).plusDays(1).atStartOfDay(RESET_ZONE).toEpochSecond();
        }

        // Reset: amount_used=0, amount_total back to plan original (without extra),
        // daily_extra_quota=0
        jdbc.update("""
            UPDATE user_subscriptions
            SET amount_used = 0,
                amount_total = ?,
                daily_extra_quota = 0,
                last_reset_time = ?,
                next_reset_time = ?,
                updated_at = ?
            WHERE id = ?
            """, planTotal, now, nextReset, now, subId);

        log.info("Manual quota reset for subscription {}: used {} → 0, extra {} → 0, total → {}",
                subId, usedBefore, dailyExtra, planTotal);

        return ResponseEntity.ok(Map.of("success", true, "data", Map.of(
            "subscriptionId", subId,
            "amountTotal", planTotal,
            "amountUsed", 0,
            "dailyExtraQuota", 0,
            "amountLeft", planTotal,
            "usedBefore", usedBefore,
            "extraBefore", dailyExtra,
            "nextResetTime", nextReset
        )));
    }

    // ---- daily extra quota midnight reset (Bug #2) ----

    /**
     * Runs at 00:00 local time to reset daily_extra_quota back to 0 and revert
     * amount_total to the plan's original value for all subscriptions that have
     * extra quota granted.
     */
    @Scheduled(cron = "0 0 0 * * *", zone = "${user.timezone:Asia/Ho_Chi_Minh}")
    public void resetDailyExtraQuota() {
        long now = Instant.now().getEpochSecond();
        try {
            List<Map<String, Object>> subs = jdbc.queryForList("""
                SELECT s.id, s.plan_id, s.amount_total, s.daily_extra_quota,
                       p.total_amount AS plan_total
                FROM user_subscriptions s
                LEFT JOIN subscription_plans p ON p.id = s.plan_id
                WHERE s.status = 'active'
                  AND COALESCE(s.daily_extra_quota, 0) > 0
                  AND COALESCE(p.quota_reset_period, 'daily') != 'never'
                """);

            int reset = 0;
            for (Map<String, Object> sub : subs) {
                long subId = ((Number) sub.get("id")).longValue();
                long planTotal = ((Number) sub.getOrDefault("plan_total", 0)).longValue();
                long dailyExtra = ((Number) sub.get("daily_extra_quota")).longValue();

                if (planTotal <= 0) {
                    log.warn("Daily extra reset skipped for sub {}: plan_total is 0", subId);
                    continue;
                }

                jdbc.update("""
                    UPDATE user_subscriptions
                    SET amount_total = ?,
                        daily_extra_quota = 0,
                        updated_at = ?
                    WHERE id = ?
                    """, planTotal, now, subId);
                reset++;
                log.info("Daily extra quota reset for sub {}: extra {} → 0, total → {}",
                        subId, dailyExtra, planTotal);
            }

            log.info("Daily extra quota reset complete: {} subscriptions reset", reset);
        } catch (Exception e) {
            log.error("Daily extra quota reset failed", e);
        }
    }

    public record ProvisionRequest(String username, Long planId) {
        ProvisionRequest normalized() {
            String safeUsername = username == null ? "" : username.trim();
            if (safeUsername.length() < 3 || safeUsername.length() > 20 || !safeUsername.matches("[A-Za-z0-9_.-]+")) {
                throw new IllegalArgumentException("Invalid username");
            }
            if (planId == null || planId <= 0) throw new IllegalArgumentException("Invalid plan");
            return new ProvisionRequest(safeUsername, planId);
        }
    }

    public record UserTokenRequest(Long userId, String username) {
        UserTokenRequest normalized() {
            long safeUserId = userId == null ? 0 : userId;
            String safeUsername = username == null ? "" : username.trim();
            if (safeUserId <= 0 && (safeUsername.length() < 3 || safeUsername.length() > 20 || !safeUsername.matches("[A-Za-z0-9_.-]+"))) {
                throw new IllegalArgumentException("Invalid user");
            }
            return new UserTokenRequest(safeUserId, safeUsername);
        }
    }

    public record DailyExtraQuotaRequest(Long userId, Long amount) {
        DailyExtraQuotaRequest normalized() {
            long safeUserId = userId == null ? 0 : userId;
            long safeAmount = amount == null ? 0 : amount;
            if (safeUserId <= 0) throw new IllegalArgumentException("Invalid user");
            if (safeAmount <= 0 || safeAmount > 1_000_000_000_000L) throw new IllegalArgumentException("Invalid extra quota amount");
            return new DailyExtraQuotaRequest(safeUserId, safeAmount);
        }
    }

    public record PlanRequest(String title, String subtitle, Double priceAmount, Long totalAmount,
                              String quotaResetPeriod, String upgradeGroup, Integer sortOrder, String modelList) {
        static PlanRequest empty() {
            return new PlanRequest("", "", 0.0, 0L, "daily", "", 50, null);
        }

        PlanRequest normalized() {
            String safeTitle = title == null ? "" : title.trim();
            if (safeTitle.isEmpty() || safeTitle.length() > 128) throw new IllegalArgumentException("Invalid title");
            String safeSubtitle = subtitle == null ? "" : subtitle.trim();
            if (safeSubtitle.length() > 255) throw new IllegalArgumentException("Subtitle too long");
            double safePrice = priceAmount == null ? 0 : priceAmount;
            if (safePrice < 0) throw new IllegalArgumentException("Invalid price");
            long safeTotal = totalAmount == null ? 0 : totalAmount;
            if (safeTotal <= 0) throw new IllegalArgumentException("total_amount must be > 0");
            if (safeTotal > 1_000_000_000_000L) throw new IllegalArgumentException("total_amount too large");
            String safePeriod = quotaResetPeriod == null ? "daily" : quotaResetPeriod.trim().toLowerCase(Locale.ROOT);
            if (!safePeriod.equals("daily") && !safePeriod.equals("never")) {
                throw new IllegalArgumentException("quota_reset_period must be 'daily' or 'never'");
            }
            String safeGroup = upgradeGroup == null ? "" : upgradeGroup.trim();
            if (safeGroup.length() > 64) throw new IllegalArgumentException("upgrade_group too long");
            int safeSort = sortOrder == null ? 50 : sortOrder;
            // model_list: null or blank → all models (stored as NULL). Otherwise CSV of model names.
            String safeModelList = modelList == null ? null : modelList.trim();
            if (safeModelList != null && safeModelList.length() > 8000) {
                throw new IllegalArgumentException("model_list too long");
            }
            return new PlanRequest(safeTitle, safeSubtitle, safePrice, safeTotal, safePeriod, safeGroup, safeSort, safeModelList);
        }
    }
}
