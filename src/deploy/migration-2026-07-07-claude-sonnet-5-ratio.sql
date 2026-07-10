-- Migration: align Claude Sonnet 5 billing ratio with token-based pricing (2026-07-07)
--
-- Target user-facing multiplier:
--   claude-sonnet-5 -> 0.5x input, 0.5x output
--
-- Target billing is 0.5 billed token/quota unit per real token. In this deployment
-- New API tiered_expr coefficient / 2 = user-facing multiplier, so
-- 0.5x => p * 1 + c * 1.
--
-- Keeps the zero-output free-billing guard introduced on 2026-07-03.
-- Does not change GPT 5.5 / Opus 4.8 ratios, which intentionally remain
-- input 1.2x / output 6x.
--
-- Run:
--   docker exec -i new-api-postgres psql -U newapi -d newapi -f - < migration-2026-07-07-claude-sonnet-5-ratio.sql
--   # Kubernetes variant:
--   kubectl -n oneapi exec -i deployment/new-api-postgres -- psql -U oneapi -d oneapi -f - < migration-2026-07-07-claude-sonnet-5-ratio.sql

BEGIN;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_mode',
  '{"claude-sonnet-5":"tiered_expr"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(options.value, '{}')::jsonb || EXCLUDED.value::jsonb)::text;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_expr',
  '{"claude-sonnet-5":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"user_token_0_5x\", p * 1 + c * 1))"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(options.value, '{}')::jsonb || EXCLUDED.value::jsonb)::text;

COMMIT;
