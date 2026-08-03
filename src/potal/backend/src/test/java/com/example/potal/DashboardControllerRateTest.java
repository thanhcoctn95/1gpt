package com.example.potal;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.util.Map;
import org.junit.jupiter.api.Test;

class DashboardControllerRateTest {
    @Test
    void billingExpressionsOverrideLegacyRatesPerModel() {
        Map<String, Double> modelRatios = Map.of(
            "gpt-5.6-luna", 1.0,
            "legacy-only", 0.5
        );
        Map<String, Double> completionRatios = Map.of(
            "gpt-5.6-luna", 1.0,
            "legacy-only", 2.0
        );
        Map<String, String> expressions = Map.of(
            "gpt-5.6-luna", "tier(\"openai_price_gpt55\", p * 1.6 + c * 12)",
            "gpt-5.6-sol", "tier(\"openai_price_gpt55\", p * 3.5 + c * 12)"
        );

        Map<String, DashboardController.CreditRate> rates = DashboardController.mergeCreditRates(
            modelRatios, completionRatios, expressions
        );

        assertEquals(0.8, rates.get("gpt-5.6-luna").input());
        assertEquals(6.0, rates.get("gpt-5.6-luna").output());
        assertEquals(1.75, rates.get("gpt-5.6-sol").input());
        assertEquals(6.0, rates.get("gpt-5.6-sol").output());
        assertEquals(0.5, rates.get("legacy-only").input());
        assertEquals(1.0, rates.get("legacy-only").output());
    }
}
