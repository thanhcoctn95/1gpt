-- Migration: set GPT-5.5 and GPT-5.6 Terra input credit multipliers (2026-07-30)
--
-- Scope (exactly these models):
--   gpt-5.5       input 1.0x; output remains 6.0x
--   gpt-5.5-xhigh input 1.0x; output remains 6.0x
--   gpt-5.6-terra input 1.2x; output remains 6.0x
--
-- New API tiered_expr coefficient mapping: coefficient / 2 = input multiplier.
--   input 1.0x => p * 2
--   input 1.2x => p * 2.4
--   output 6.0x => c * 12 (unchanged)
--
-- Idempotent: JSON merges overwrite only the three listed model keys.
-- Does not touch plans, users, channels, models, or abilities.

\set ON_ERROR_STOP on

BEGIN;

UPDATE options
SET value = (COALESCE(value, '{}')::jsonb ||
             '{"gpt-5.5":1.0,"gpt-5.5-xhigh":1.0,"gpt-5.6-terra":1.2}'::jsonb)::text
WHERE key = 'ModelRatio';

UPDATE options
SET value = (COALESCE(value, '{}')::jsonb ||
             '{"gpt-5.5":6.0,"gpt-5.5-xhigh":6.0,"gpt-5.6-terra":5.0}'::jsonb)::text
WHERE key = 'CompletionRatio';

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_mode',
  '{"gpt-5.5":"tiered_expr","gpt-5.5-xhigh":"tiered_expr","gpt-5.6-terra":"tiered_expr"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(options.value, '{}')::jsonb || EXCLUDED.value::jsonb)::text;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_expr',
  '{"gpt-5.5":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 2 + c * 12))","gpt-5.5-xhigh":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 2 + c * 12))","gpt-5.6-terra":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 2.4 + c * 12))"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(options.value, '{}')::jsonb || EXCLUDED.value::jsonb)::text;

SELECT key,
       value::jsonb -> 'gpt-5.5' AS gpt_5_5,
       value::jsonb -> 'gpt-5.5-xhigh' AS gpt_5_5_xhigh,
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
