-- Migration: lower GPT-5.6 Terra input credit multiplier to 1.0x (2026-08-07)
--
-- Scope (exactly one model):
--   gpt-5.6-terra input 1.2x -> 1.0x; output remains 6.0x.
--
-- New API tiered_expr coefficient mapping: coefficient / 2 = input multiplier.
--   input 1.0x => p * 2    (target)
--   output 6.0x => c * 12  (unchanged)
--
-- Supersedes migration-2026-08-06-gpt56-terra-1_2x.sql.
-- Idempotent: JSON merges overwrite only the gpt-5.6-terra key.
-- Does not touch plans, users, subscriptions, channels, models, or abilities.

\set ON_ERROR_STOP on

BEGIN;

-- Displayed input rate (credit / 1M tokens) used by the portal pricing views.
UPDATE options
SET value = (COALESCE(NULLIF(value, ''), '{}')::jsonb ||
             '{"gpt-5.6-terra":1.0}'::jsonb)::text
WHERE key = 'ModelRatio';

-- Output rate remains 6.0x.
UPDATE options
SET value = (COALESCE(NULLIF(value, ''), '{}')::jsonb ||
             '{"gpt-5.6-terra":6.0}'::jsonb)::text
WHERE key = 'CompletionRatio';

-- Actual billing expression: p * 2 => 1.0x input. Output term c * 12 unchanged.
INSERT INTO options (key, value)
VALUES ('billing_setting.billing_expr', '{"gpt-5.6-terra":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 2 + c * 12))"}')
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(NULLIF(options.value, ''), '{}')::jsonb || EXCLUDED.value::jsonb)::text;

-- Keep the model on tiered_expr billing.
INSERT INTO options (key, value)
VALUES ('billing_setting.billing_mode', '{"gpt-5.6-terra":"tiered_expr"}')
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(NULLIF(options.value, ''), '{}')::jsonb || EXCLUDED.value::jsonb)::text;

-- Verification: Terra must show 1.0 / 6.0 / "p * 2 + c * 12" / "tiered_expr".
SELECT key, value::jsonb -> 'gpt-5.6-terra' AS terra
FROM options
WHERE key IN ('ModelRatio','CompletionRatio','billing_setting.billing_mode','billing_setting.billing_expr')
ORDER BY key;

COMMIT;
