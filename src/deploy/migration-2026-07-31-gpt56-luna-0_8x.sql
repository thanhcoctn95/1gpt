-- Migration: update GPT-5.6 Luna credit rate (2026-07-31)
--
-- Effective rate:
--   input  0.8 credit / 1M tokens -> p * 1.6
--   output 6.0 credit / 1M tokens -> c * 12
--
-- This migration only overwrites the gpt-5.6-luna billing keys. It does not
-- change channels, models, plans, balances, or any other model's policy.
-- Idempotent: safe to re-run.

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_mode',
  '{"gpt-5.6-luna":"tiered_expr"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (
  COALESCE(NULLIF(options.value, ''), '{}')::jsonb
  || EXCLUDED.value::jsonb
)::text;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_expr',
  '{"gpt-5.6-luna":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 1.6 + c * 12))"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (
  COALESCE(NULLIF(options.value, ''), '{}')::jsonb
  || EXCLUDED.value::jsonb
)::text;

-- Keep legacy maps aligned when they exist. Output/input = 6 / 0.8 = 7.5.
UPDATE options
SET value = (
  COALESCE(NULLIF(value, ''), '{}')::jsonb
  || '{"gpt-5.6-luna":0.8}'::jsonb
)::text
WHERE key = 'ModelRatio';

UPDATE options
SET value = (
  COALESCE(NULLIF(value, ''), '{}')::jsonb
  || '{"gpt-5.6-luna":7.5}'::jsonb
)::text
WHERE key = 'CompletionRatio';

SELECT key, value::jsonb -> 'gpt-5.6-luna' AS luna
FROM options
WHERE key IN (
  'ModelRatio',
  'CompletionRatio',
  'billing_setting.billing_mode',
  'billing_setting.billing_expr'
)
ORDER BY key;

COMMIT;
