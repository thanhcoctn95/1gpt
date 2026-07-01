-- Migration: update GPT 5.5 input billing from 1.5x to 1x (2026-06-30)
-- New API tiered_expr coefficient mapping: p * 2 => input 1x, c * 12 => output 6x.
-- Scope: GPT models only. Claude/Opus rates stay unchanged.

BEGIN;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_mode',
  '{"gpt-5.5":"tiered_expr","gpt-5.5-xhigh":"tiered_expr"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (options.value::jsonb || EXCLUDED.value::jsonb)::text;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_expr',
  '{"gpt-5.5":"tier(\"openai_price_gpt55\", p * 2 + c * 12)","gpt-5.5-xhigh":"tier(\"openai_price_gpt55\", p * 2 + c * 12)"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (options.value::jsonb || EXCLUDED.value::jsonb)::text;

COMMIT;
