-- Migration: update GPT 5.5 and Claude Opus 4.8 input billing to 1.5x (2026-06-29)
-- New API tiered_expr coefficient mapping: p * 3 => input 1.5x, c * 12 => output 6x.

BEGIN;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_mode',
  '{"gpt-5.5":"tiered_expr","gpt-5.5-xhigh":"tiered_expr","opus-4.8":"tiered_expr","opus-4.8-thinking":"tiered_expr","claude-opus-4.8":"tiered_expr","claude-opus-4.8-thinking":"tiered_expr"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (options.value::jsonb || EXCLUDED.value::jsonb)::text;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_expr',
  '{"gpt-5.5":"tier(\"openai_price_gpt55\", p * 3 + c * 12)","gpt-5.5-xhigh":"tier(\"openai_price_gpt55\", p * 3 + c * 12)","opus-4.8":"tier(\"openai_price_gpt55\", p * 3 + c * 12)","opus-4.8-thinking":"tier(\"openai_price_gpt55\", p * 3 + c * 12)","claude-opus-4.8":"tier(\"openai_price_gpt55\", p * 3 + c * 12)","claude-opus-4.8-thinking":"tier(\"openai_price_gpt55\", p * 3 + c * 12)"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (options.value::jsonb || EXCLUDED.value::jsonb)::text;

COMMIT;
