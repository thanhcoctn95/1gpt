-- Migration: lower GPT-5.6 input multipliers (2026-07-21)
--
-- Scope (exactly these two models):
--   gpt-5.6-sol   input 3.0x -> 2.0x
--   gpt-5.6-terra input 2.0x -> 1.5x
--
-- Output stays 6.0x for both models. New API tiered_expr coefficient mapping:
--   coefficient / 2 = user-facing multiplier
--   sol input 2.0x   => p * 4
--   terra input 1.5x => p * 3
--   output 6.0x      => c * 12 (UNCHANGED)
--
-- Updates legacy ModelRatio/CompletionRatio maps when they exist so their
-- input/output display remains consistent with billing_expr. Does not create
-- those legacy options when absent. Does not touch channels, abilities, plans,
-- or any other model.
--
-- Idempotent: safe to re-run.
--
-- Run (Kubernetes):
--   kubectl -n oneapi exec -i deployment/new-api-postgres -- \
--     psql -U oneapi -d oneapi -f - \
--     < migration-2026-07-21-gpt56-sol-terra-input-rates.sql
--
-- Run (local docker compose):
--   docker exec -i new-api-postgres \
--     psql -U newapi -d newapi -f - \
--     < migration-2026-07-21-gpt56-sol-terra-input-rates.sql

\set ON_ERROR_STOP on

BEGIN;

-- Keep legacy ratio maps consistent when this deployment uses them.
-- completion_ratio = output multiplier / input multiplier:
--   sol: 6 / 2 = 3; terra: 6 / 1.5 = 4.
UPDATE options
SET value = (
  value::jsonb || jsonb_build_object(
    'gpt-5.6-sol', 2.0,
    'gpt-5.6-terra', 1.5
  )
)::text
WHERE key = 'ModelRatio';

UPDATE options
SET value = (
  value::jsonb || jsonb_build_object(
    'gpt-5.6-sol', 3.0,
    'gpt-5.6-terra', 4.0
  )
)::text
WHERE key = 'CompletionRatio';

-- Re-assert tiered_expr mode for only these two models.
INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_mode',
  '{"gpt-5.6-sol":"tiered_expr","gpt-5.6-terra":"tiered_expr"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(options.value, '{}')::jsonb || EXCLUDED.value::jsonb)::text;

-- Lower input only; preserve output weighting and zero-output guard.
INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_expr',
  '{"gpt-5.6-sol":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 4 + c * 12))","gpt-5.6-terra":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 3 + c * 12))"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(options.value, '{}')::jsonb || EXCLUDED.value::jsonb)::text;

-- Report the resulting runtime values for both supported configuration paths.
SELECT key, value::jsonb -> 'gpt-5.6-sol' AS gpt_5_6_sol,
       value::jsonb -> 'gpt-5.6-terra' AS gpt_5_6_terra
FROM options
WHERE key IN (
  'ModelRatio',
  'CompletionRatio',
  'billing_setting.billing_mode',
  'billing_setting.billing_expr'
)
ORDER BY key;

COMMIT;
