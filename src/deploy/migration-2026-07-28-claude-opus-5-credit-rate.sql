-- Migration: update Claude Opus 5 credit multiplier (2026-07-28)
--
-- Effective rate:
--   input  3.0 credit / 1M tokens -> p * 6
--   output 6.0 credit / 1M tokens -> c * 12
--
-- New API tiered_expr coefficients are twice the user-facing multiplier.
-- This migration only overwrites the claude-opus-5 billing keys. It does not
-- change channels, packages, balances, or any other model's billing policy.
-- Idempotent: safe to re-run.
--
-- Run on Kubernetes production:
--   kubectl -n oneapi exec -i deployment/new-api-postgres -- \
--     sh -lc 'PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
--     < migration-2026-07-28-claude-opus-5-credit-rate.sql

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_mode',
  '{"claude-opus-5":"tiered_expr"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (
  COALESCE(NULLIF(options.value, ''), '{}')::jsonb
  || EXCLUDED.value::jsonb
)::text;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_expr',
  '{"claude-opus-5":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 6 + c * 12))"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (
  COALESCE(NULLIF(options.value, ''), '{}')::jsonb
  || EXCLUDED.value::jsonb
)::text;

-- Keep legacy ratio maps aligned when present. The runtime billing expression
-- above remains authoritative. Input 3.0 × completion ratio 2.0 = output 6.0.
UPDATE options
SET value = (
  COALESCE(NULLIF(value, ''), '{}')::jsonb
  || '{"claude-opus-5":3.0}'::jsonb
)::text
WHERE key = 'ModelRatio';

UPDATE options
SET value = (
  COALESCE(NULLIF(value, ''), '{}')::jsonb
  || '{"claude-opus-5":2.0}'::jsonb
)::text
WHERE key = 'CompletionRatio';

SELECT key, value::jsonb -> 'claude-opus-5' AS claude_opus_5
FROM options
WHERE key IN (
  'ModelRatio',
  'CompletionRatio',
  'billing_setting.billing_mode',
  'billing_setting.billing_expr'
)
ORDER BY key;

COMMIT;
