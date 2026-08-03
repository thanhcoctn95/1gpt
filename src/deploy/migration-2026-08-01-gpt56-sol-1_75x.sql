-- Migration: lower GPT-5.6 Sol input credit rate (2026-08-01)
--
-- Effective rate:
--   input  1.75 credit / 1M tokens -> p * 3.5
--   output 6.00 credit / 1M tokens -> c * 12
--
-- This migration only overwrites the gpt-5.6-sol billing keys. It does not
-- change channels, models, plans, balances, or any other model's policy.
-- Idempotent: safe to re-run.

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_mode',
  '{"gpt-5.6-sol":"tiered_expr"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (
  COALESCE(NULLIF(options.value, ''), '{}')::jsonb
  || EXCLUDED.value::jsonb
)::text;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_expr',
  '{"gpt-5.6-sol":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 3.5 + c * 12))"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (
  COALESCE(NULLIF(options.value, ''), '{}')::jsonb
  || EXCLUDED.value::jsonb
)::text;

-- Keep legacy maps aligned when they exist. Output/input = 6 / 1.75 = 24/7.
UPDATE options
SET value = (
  COALESCE(NULLIF(value, ''), '{}')::jsonb
  || '{"gpt-5.6-sol":1.75}'::jsonb
)::text
WHERE key = 'ModelRatio';

UPDATE options
SET value = (
  COALESCE(NULLIF(value, ''), '{}')::jsonb
  || jsonb_build_object('gpt-5.6-sol', 24.0 / 7.0)
)::text
WHERE key = 'CompletionRatio';

SELECT key, value::jsonb -> 'gpt-5.6-sol' AS sol
FROM options
WHERE key IN (
  'ModelRatio',
  'CompletionRatio',
  'billing_setting.billing_mode',
  'billing_setting.billing_expr'
)
ORDER BY key;

COMMIT;
