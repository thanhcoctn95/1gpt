package com.example.potal;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/pricing")
public class PricingController {
    private static final ZoneId RESET_ZONE = ZoneId.systemDefault();
    private final JdbcTemplate jdbc;
    private final AuthService authService;

    public PricingController(JdbcTemplate jdbc, AuthService authService) {
        this.jdbc = jdbc;
        this.authService = authService;
    }

    @PostMapping("/apply")
    @Transactional
    public ResponseEntity<?> apply(@RequestHeader(value = "Authorization", required = false) String authorization, @RequestBody ApplyPlanRequest request) {
        Map<String, Object> auth = authService.requireUser(authorization);
        long userId = ((Number) auth.get("user_id")).longValue();
        PricingPlan plan = PricingPlan.from(request == null ? null : request.plan());

        long now = Instant.now().getEpochSecond();
        long end = Instant.now().plusSeconds(31L * 24 * 60 * 60).getEpochSecond();
        long nextReset = LocalDate.now(RESET_ZONE).plusDays(1).atStartOfDay(RESET_ZONE).toEpochSecond();
        seedAllPlans(now);
        long planId = upsertPlan(plan, now);

        jdbc.update("""
            UPDATE user_subscriptions SET status='cancelled', updated_at=?
            WHERE user_id=? AND status='active'
            """, now, userId);

        long subscriptionId = insertSubscription(userId, planId, plan.dailyQuota(), now, end, nextReset, plan.upgradeGroup());

        // Cập nhật users.group nếu plan có upgrade_group
        if (!plan.upgradeGroup().isBlank()) {
            jdbc.update("UPDATE users SET \"group\"=? WHERE id=?", plan.upgradeGroup(), userId);
        }

        List<Map<String, Object>> rows = jdbc.queryForList("""
            SELECT s.id, s.plan_id, p.title AS plan_title, p.subtitle AS plan_subtitle, p.quota_reset_period,
                   s.amount_total, s.amount_used, (s.amount_total - s.amount_used) AS amount_left,
                   s.status, s.source, s.upgrade_group,
                   to_timestamp(s.start_time) AS start_time, to_timestamp(s.end_time) AS end_time,
                   to_timestamp(s.last_reset_time) AS last_reset_time, to_timestamp(s.next_reset_time) AS next_reset_time
            FROM user_subscriptions s
            LEFT JOIN subscription_plans p ON p.id = s.plan_id
            WHERE s.id=?
            """, subscriptionId);
        return ResponseEntity.ok(Map.of("success", true, "data", Map.of(
            "message", "Đã áp dụng gói " + plan.title(),
            "subscription", rows.isEmpty() ? Map.of() : rows.get(0)
        )));
    }

    private void seedAllPlans(long now) {
        for (PricingPlan plan : PricingPlan.all()) upsertPlan(plan, now);
    }

    private long upsertPlan(PricingPlan plan, long now) {
        List<Map<String, Object>> existing = jdbc.queryForList("SELECT id FROM subscription_plans WHERE title=? ORDER BY id ASC LIMIT 1", plan.title());
        if (!existing.isEmpty()) {
            long id = ((Number) existing.get(0).get("id")).longValue();
            jdbc.update("""
                UPDATE subscription_plans
                SET subtitle=?, price_amount=?, currency='VND', duration_unit='month', duration_value=1,
                    enabled=true, sort_order=?, max_purchase_per_user=0,
                    total_amount=?, quota_reset_period='daily', quota_reset_custom_seconds=0,
                    upgrade_group=?, updated_at=?
                WHERE id=?
                """, plan.subtitle(), plan.priceAmount(), plan.sortOrder(), plan.dailyQuota(), plan.upgradeGroup(), now, id);
            return id;
        }
        return jdbc.queryForObject("""
            INSERT INTO subscription_plans
              (title, subtitle, price_amount, currency, duration_unit, duration_value, custom_seconds,
               enabled, sort_order, stripe_price_id, creem_product_id,
               max_purchase_per_user, upgrade_group, total_amount, quota_reset_period, quota_reset_custom_seconds,
               created_at, updated_at)
            VALUES (?, ?, ?, 'VND', 'month', 1, 0, true, ?, '', '', 0, ?, ?, 'daily', 0, ?, ?)
            RETURNING id
            """, Long.class, plan.title(), plan.subtitle(), plan.priceAmount(), plan.sortOrder(), plan.upgradeGroup(), plan.dailyQuota(), now, now);
    }

    private long insertSubscription(long userId, long planId, long dailyQuota, long now, long end, long nextReset, String upgradeGroup) {
        String safeUpgradeGroup = (upgradeGroup == null || upgradeGroup.isBlank()) ? "" : upgradeGroup;
        return jdbc.queryForObject("""
            INSERT INTO user_subscriptions
              (user_id, plan_id, amount_total, amount_used, start_time, end_time, status, source,
               last_reset_time, next_reset_time, upgrade_group, prev_user_group, created_at, updated_at)
            VALUES (?, ?, ?, 0, ?, ?, 'active', 'potal', ?, ?, ?, '', ?, ?)
            RETURNING id
            """, Long.class, userId, planId, dailyQuota, now, end, now, nextReset, safeUpgradeGroup, now, now);
    }

    public record ApplyPlanRequest(String plan) {}

    private record PricingPlan(String code, String title, String subtitle, double priceAmount, long dailyQuota, int sortOrder, String upgradeGroup) {
        static List<PricingPlan> all() {
            return List.of(
                new PricingPlan("plus", "Plus", "20 credit GPT-5.5/ngày", 549_000, 20_000_000, 10, ""),
                new PricingPlan("pro", "Pro", "40 credit GPT-5.5/ngày", 879_000, 40_000_000, 20, ""),
                new PricingPlan("ultra", "Ultra", "60 credit GPT-5.5/ngày", 1_199_000, 60_000_000, 30, ""),
                new PricingPlan("max", "Max", "80 credit GPT-5.5/ngày", 1_549_000, 80_000_000, 40, "max")
            );
        }

        static PricingPlan from(String code) {
            String normalized = code == null ? "" : code.trim().toLowerCase(Locale.ROOT);
            return all().stream().filter(plan -> plan.code().equals(normalized)).findFirst().orElseThrow(() -> new IllegalArgumentException("Invalid pricing plan"));
        }
    }
}
