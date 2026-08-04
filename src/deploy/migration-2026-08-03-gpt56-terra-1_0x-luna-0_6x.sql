-- Migration: lower GPT-5.6 Terra and Luna input credit rates (2026-08-03)
--
-- Effective rates:
--   Terra input 1.00 credit / 1M tokens -> p * 2
--   Luna  input 0.60 credit / 1M tokens -> p * 1.2
--   Both output 6.00 credit / 1M tokens -> c * 12
--
-- Only the two named model keys are changed. Other models and settings are preserved.
-- Idempotent: safe to re-run.

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO options (key, value)
VALUES ('billing_setting.billing_mode', '{"gpt-5.6-terra":"tiered_expr","gpt-5.6-luna":"tiered_expr"}')
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(NULLIF(options.value, ''), '{}')::jsonb || EXCLUDED.value::jsonb)::text;

INSERT INTO options (key, value)
VALUES ('billing_setting.billing_expr', '{"gpt-5.6-terra":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 2 + c * 12))","gpt-5.6-luna":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 1.2 + c * 12))"}')
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(NULLIF(options.value, ''), '{}')::jsonb || EXCLUDED.value::jsonb)::text;

UPDATE options
SET value = (COALESCE(NULLIF(value, ''), '{}')::jsonb || '{"gpt-5.6-terra":1.0,"gpt-5.6-luna":0.6}'::jsonb)::text
WHERE key = 'ModelRatio';

UPDATE options
SET value = (COALESCE(NULLIF(value, ''), '{}')::jsonb || '{"gpt-5.6-terra":6.0,"gpt-5.6-luna":10.0}'::jsonb)::text
WHERE key = 'CompletionRatio';

SELECT key, value::jsonb -> 'gpt-5.6-terra' AS terra,
       value::jsonb -> 'gpt-5.6-luna' AS luna
FROM options
WHERE key IN ('ModelRatio','CompletionRatio','billing_setting.billing_mode','billing_setting.billing_expr')
ORDER BY key;

COMMIT;
