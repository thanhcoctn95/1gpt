-- Migration: OpenAI-price user billing for GPT models (2026-06-28)
-- Purpose:
--   Charge 1API users by OpenAI-style API price weighting to maximize margin:
--     gpt-5.5 / gpt-5.5-xhigh / opus-4.8-thinking: input 1.5x, output 6x
--     gpt-5.4:                  input 0.5x, output 3x
--   Keep partner/VietAPI actual cost as internal accounting only; do not expose provider details publicly.
--
-- New API tiered_expr coefficient mapping observed in this deployment:
--   coefficient 3 => 1.5 token credit/token
--   coefficient 2 => 1 token credit/token
--   coefficient 1 => 0.5 token credit/token
--   coefficient 0.5 => 0.25 token credit/token
--
-- Therefore:
--   gpt-5.5 / opus input  1.5x => p * 3
--   gpt-5.5 / opus output 6x => c * 12
--   gpt-5.4 input  0.5x => p * 1
--   gpt-5.4 output 3x => c * 6
--
-- Rollback to previous raw-token GPT billing:
--   update options set value = '{"gpt-5.4":"tier(\"user_token_1x\", p * 2 + c * 2)","gpt-5.5":"tier(\"user_token_1x\", p * 2 + c * 2)","gpt-5.5-xhigh":"tier(\"user_token_1x\", p * 2 + c * 2)","opus-4.8-thinking":"tier(\"user_token_1x\", p * 2 + c * 2)","minimax-m3":"tier(\"user_token_1x\", p * 2 + c * 2)","glm-5.2":"tier(\"user_token_0_5x\", p * 1 + c * 1)","glm-5.1":"tier(\"user_token_0_25x\", p * 0.5 + c * 0.5)"}'
--   where key = 'billing_setting.billing_expr';

BEGIN;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_mode',
  '{"gpt-5.4":"tiered_expr","gpt-5.5":"tiered_expr","gpt-5.5-xhigh":"tiered_expr","glm-5.1":"tiered_expr","glm-5.2":"tiered_expr","minimax-m3":"tiered_expr","opus-4.8":"tiered_expr","opus-4.8-thinking":"tiered_expr","claude-opus-4.8":"tiered_expr","claude-opus-4.8-thinking":"tiered_expr"}'
)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_expr',
  '{"gpt-5.4":"tier(\"openai_price_gpt54\", p * 1 + c * 6)","gpt-5.5":"tier(\"openai_price_gpt55\", p * 3 + c * 12)","gpt-5.5-xhigh":"tier(\"openai_price_gpt55\", p * 3 + c * 12)","opus-4.8":"tier(\"openai_price_gpt55\", p * 3 + c * 12)","opus-4.8-thinking":"tier(\"openai_price_gpt55\", p * 3 + c * 12)","claude-opus-4.8":"tier(\"openai_price_gpt55\", p * 3 + c * 12)","claude-opus-4.8-thinking":"tier(\"openai_price_gpt55\", p * 3 + c * 12)","minimax-m3":"tier(\"user_token_1x\", p * 2 + c * 2)","glm-5.2":"tier(\"user_token_0_5x\", p * 1 + c * 1)","glm-5.1":"tier(\"user_token_0_25x\", p * 0.5 + c * 0.5)"}'
)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

COMMIT;
