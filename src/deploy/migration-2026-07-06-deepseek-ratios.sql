-- Migration: update DeepSeek V4 billing ratios (2026-07-06)
--
-- Target user-facing multipliers:
--   deepseek-v4-flash -> 0.1x input, 0.1x output
--   deepseek-v4-pro   -> 0.5x input, 0.5x output (unchanged)
--
-- New API tiered_expr coefficient mapping in this deployment:
--   expression coefficient / 2 = user-facing multiplier.
-- Therefore:
--   0.1x => p * 0.2 + c * 0.2
--   0.5x => p * 1   + c * 1
--
-- Keeps the zero-output free-billing guard introduced on 2026-07-03.
--
-- Run:
--   docker exec -i new-api-postgres psql -U newapi -d newapi -f - < migration-2026-07-06-deepseek-ratios.sql
--   # Kubernetes variant:
--   kubectl -n oneapi exec -i deployment/new-api-postgres -- psql -U oneapi -d oneapi -f - < migration-2026-07-06-deepseek-ratios.sql

BEGIN;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_mode',
  '{"deepseek-v4-flash":"tiered_expr","deepseek-v4-pro":"tiered_expr"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(options.value, '{}')::jsonb || EXCLUDED.value::jsonb)::text;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_expr',
  '{"deepseek-v4-flash":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"user_token_0_1x\", p * 0.2 + c * 0.2))","deepseek-v4-pro":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"user_token_0_5x\", p * 1 + c * 1))"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(options.value, '{}')::jsonb || EXCLUDED.value::jsonb)::text;

COMMIT;
