-- Migration: update approved model INPUT credit multipliers (2026-07-21)
--
-- Effective rates after this migration:
--   gpt-5.5, gpt-5.5-xhigh                         input 1.2x, output 6x
--   opus-4.8, opus-4.8-thinking,
--   claude-opus-4.8, claude-opus-4.8-thinking      input 2.0x, output 6x
--   claude-sonnet-5                                 input 1.0x, output 0.5x
--
-- New API tiered_expr coefficient mapping in this deployment:
--   coefficient / 2 = user-facing multiplier.
--   input 1.2x => p * 2.4
--   input 2.0x => p * 4
--   input 1.0x => p * 2
--   output 6x  => c * 12
--   output 0.5x => c * 1
--
-- INPUT MULTIPLIER ONLY. Existing output rates and zero-output guard remain.
-- Additive JSON merge overwrites only these seven keys. It does not change
-- channels, abilities, plans, balances, ModelRatio, or other model expressions.
-- Idempotent: safe to re-run.

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_mode',
  '{"gpt-5.5":"tiered_expr","gpt-5.5-xhigh":"tiered_expr","opus-4.8":"tiered_expr","opus-4.8-thinking":"tiered_expr","claude-opus-4.8":"tiered_expr","claude-opus-4.8-thinking":"tiered_expr","claude-sonnet-5":"tiered_expr"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(options.value, '{}')::jsonb || EXCLUDED.value::jsonb)::text;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_expr',
  '{"gpt-5.5":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 2.4 + c * 12))","gpt-5.5-xhigh":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 2.4 + c * 12))","opus-4.8":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 4 + c * 12))","opus-4.8-thinking":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 4 + c * 12))","claude-opus-4.8":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 4 + c * 12))","claude-opus-4.8-thinking":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 4 + c * 12))","claude-sonnet-5":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"user_token_0_5x\", p * 2 + c * 1))"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(options.value, '{}')::jsonb || EXCLUDED.value::jsonb)::text;

SELECT
  m.model,
  opt.value::jsonb ->> m.model AS billing_expr
FROM (
  VALUES
    ('gpt-5.5'), ('gpt-5.5-xhigh'),
    ('opus-4.8'), ('opus-4.8-thinking'),
    ('claude-opus-4.8'), ('claude-opus-4.8-thinking'),
    ('claude-sonnet-5')
) AS m(model)
CROSS JOIN options opt
WHERE opt.key = 'billing_setting.billing_expr'
ORDER BY m.model;

COMMIT;
