-- Migration: lower GPT-5.6 Luna input credit multiplier to 0.5x (2026-08-19)
--
-- Scope (exactly one model):
--   gpt-5.6-luna input 0.6x -> 0.5x; output remains 6.0x.
--
-- New API tiered_expr coefficient mapping: coefficient / 2 = input multiplier.
--   input 0.5x  => p * 1     (target, was p * 1.2)
--   output 6.0x => c * 12    (unchanged)
--
-- CompletionRatio is output/input, so it moves 10.0 -> 12.0 (6.0 / 0.5).
--
-- Supersedes migration-2026-08-03-gpt56-terra-1_0x-luna-0_6x.sql for Luna only.
-- Idempotent: JSON merges overwrite only the gpt-5.6-luna key.
-- Does not touch plans, users, subscriptions, channels, models, or abilities.

\set ON_ERROR_STOP on

BEGIN;

-- Displayed input rate (credit / 1M tokens) used by the portal pricing views.
UPDATE options
SET value = (COALESCE(NULLIF(value, ''), '{}')::jsonb ||
             '{"gpt-5.6-luna":0.5}'::jsonb)::text
WHERE key = 'ModelRatio';

-- Output / input = 6.0 / 0.5 = 12.0.
UPDATE options
SET value = (COALESCE(NULLIF(value, ''), '{}')::jsonb ||
             '{"gpt-5.6-luna":12.0}'::jsonb)::text
WHERE key = 'CompletionRatio';

-- Actual billing expression: p * 1 => 0.5x input. Output term c * 12 unchanged.
INSERT INTO options (key, value)
VALUES ('billing_setting.billing_expr', '{"gpt-5.6-luna":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 1 + c * 12))"}')
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(NULLIF(options.value, ''), '{}')::jsonb || EXCLUDED.value::jsonb)::text;

-- Keep the model on tiered_expr billing.
INSERT INTO options (key, value)
VALUES ('billing_setting.billing_mode', '{"gpt-5.6-luna":"tiered_expr"}')
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(NULLIF(options.value, ''), '{}')::jsonb || EXCLUDED.value::jsonb)::text;

-- Verification: Luna must show 0.5 / 12.0 / "p * 1 + c * 12" / "tiered_expr".
SELECT key, value::jsonb -> 'gpt-5.6-luna' AS luna
FROM options
WHERE key IN ('ModelRatio','CompletionRatio','billing_setting.billing_mode','billing_setting.billing_expr')
ORDER BY key;

COMMIT;
