package com.example.potal;

import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Public endpoints — no auth required. Used by the landing/pricing page to display
 * available plans and their model access without requiring the user to log in.
 */
@RestController
@RequestMapping("/api/public")
public class PublicController {
    private final JdbcTemplate jdbc;

    public PublicController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /**
     * Returns all enabled plans with their model_list and a computed model_count.
     * model_list=NULL means "all active models from channels" — in that case
     * model_count is the current count of distinct active models across all
     * active channels (read live from New API's channels table).
     */
    @GetMapping("/plans")
    public Map<String, Object> publicPlans() {
        List<Map<String, Object>> plans = jdbc.queryForList("""
            SELECT id, title, subtitle, price_amount, total_amount, quota_reset_period,
                   upgrade_group, sort_order, model_list
            FROM subscription_plans
            WHERE enabled = true
            ORDER BY sort_order ASC, id ASC
            LIMIT 100
            """);

        // Count distinct active models from channels (for plans with model_list=NULL).
        Integer allModelCountRaw = jdbc.queryForObject("""
            SELECT count(DISTINCT trim(model))::int
            FROM channels c
            CROSS JOIN LATERAL regexp_split_to_table(COALESCE(c.models, ''), ',') AS model
            WHERE c.status = 1 AND trim(model) <> ''
            """, Integer.class);
        final int allModelCount = allModelCountRaw == null ? 0 : allModelCountRaw;

        // Enrich each plan with model_count.
        List<Map<String, Object>> enriched = plans.stream().map(p -> {
            Map<String, Object> mutable = new java.util.HashMap<>(p);
            Object ml = p.get("model_list");
            if (ml == null || String.valueOf(ml).trim().isEmpty()) {
                mutable.put("model_count", allModelCount);
                mutable.put("model_list", null);
            } else {
                String[] parts = String.valueOf(ml).trim().split(",");
                int count = 0;
                for (String part : parts) {
                    if (!part.trim().isEmpty()) count++;
                }
                mutable.put("model_count", count);
            }
            return mutable;
        }).toList();

        return Map.of("success", true, "data", enriched);
    }
}
