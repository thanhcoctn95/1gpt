package com.example.potal;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

class ProvisioningControllerDailyQuotaTest {
    @Test
    void mixedPlanExpiryExcludesTheTokenPackTechnicalExpiry() {
        assertEquals(
            "max(active.end_time) FILTER (WHERE active.quota_reset_period != 'never')",
            ProvisioningController.ACTIVE_MONTHLY_EXPIRY_SQL
        );
    }

    @Test
    void dailyReconciliationUsesOnlyTheLatestActiveMonthlySubscription() {
        String sql = ProvisioningController.DAILY_QUOTA_RECONCILIATION_SQL;

        assertTrue(sql.contains("amount_total = p.total_amount"));
        assertTrue(sql.contains("daily_extra_quota = 0"));
        assertTrue(sql.contains("s.id = ("));
        assertTrue(sql.contains("ORDER BY current_s.start_time DESC, current_s.id DESC"));
        assertTrue(sql.contains("COALESCE(current_p.quota_reset_period, 'daily') != 'never'"));
    }

    @Test
    void dailyReconciliationCancelsOtherActiveMonthlySubscriptions() {
        String sql = ProvisioningController.STALE_DAILY_SUBSCRIPTIONS_SQL;

        assertTrue(sql.contains("SET status = 'cancelled'"));
        assertTrue(sql.contains("stale.id <> ("));
        assertTrue(sql.contains("ORDER BY current_s.start_time DESC, current_s.id DESC"));
        assertTrue(sql.contains("COALESCE(current_p.quota_reset_period, 'daily') != 'never'"));
    }
}
