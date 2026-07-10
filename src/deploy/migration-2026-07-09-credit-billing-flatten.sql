-- Migration (OPTIONAL, REVENUE-CHANGING): flatten premium output billing so the
-- credit headline rate is literally flat per 1M tokens (2026-07-09)
--
-- ⚠️  DO NOT APPLY WITHOUT AN EXPLICIT PRICING DECISION. ⚠️
--
-- Context
-- -------
-- The portal now surfaces cost in CREDIT where 1 credit = 1,000,000 quota units
-- (see docs/internal/1api-gpt55-pricing.md). Credit balances are just a display
-- layer over the existing New API quota, so NO migration is required for the
-- credit switch itself.
--
-- However, premium models are still billed with output weighted ~6x input at the
-- billing_expr layer, e.g.:
--   gpt-5.5 / gpt-5.5-xhigh : tier("openai_price_gpt55", p * 2 + c * 12)
--   opus-4.8 (+thinking)    : tier("openai_price_gpt55", p * 2.4 + c * 12)
-- (New API tiered_expr coefficient / 2 = user-facing multiplier, so p*2 => 1.0x
--  input, c*12 => 6.0x output.)
--
-- That means the *effective* credits/1M output for these models is higher than
-- the 1.0 cr/1M headline. This file rewrites those expressions so BOTH input and
-- output bill at the flat headline rate (1.0x input, 1.0x output => p * 2 + c * 2).
--
-- Impact: this REDUCES premium output revenue by ~6x. Only run it if the business
-- intent is a genuinely flat per-token credit price. Otherwise keep the current
-- output-weighted billing_expr and rely on the credit DISPLAY layer only.
--
-- Run (only after decision):
--   docker exec -i new-api-postgres psql -U newapi -d newapi -f - < migration-2026-07-09-credit-billing-flatten.sql
--   # Kubernetes variant:
--   kubectl -n oneapi exec -i deployment/new-api-postgres -- psql -U oneapi -d oneapi -f - < migration-2026-07-09-credit-billing-flatten.sql

BEGIN;

-- Keep the zero-output free-billing guard consistent with prior migrations.
INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_mode',
  '{"gpt-5.5":"tiered_expr","gpt-5.5-xhigh":"tiered_expr","gpt-5.5-high":"tiered_expr"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(options.value, '{}')::jsonb || EXCLUDED.value::jsonb)::text;

-- 1.0x input, 1.0x output => p * 2 + c * 2 (flat 1.0 credit / 1M tokens).
INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_expr',
  '{"gpt-5.5":"c <= 0 ? tier(\"zero_output\", 0) : tier(\"openai_price_gpt55\", p * 2 + c * 2)","gpt-5.5-xhigh":"c <= 0 ? tier(\"zero_output\", 0) : tier(\"openai_price_gpt55\", p * 2 + c * 2)","gpt-5.5-high":"c <= 0 ? tier(\"zero_output\", 0) : tier(\"openai_price_gpt55\", p * 2 + c * 2)"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(options.value, '{}')::jsonb || EXCLUDED.value::jsonb)::text;

COMMIT;
