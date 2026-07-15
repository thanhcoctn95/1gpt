-- Migration: raise premium INPUT token multiplier 1.2x -> 1.5x (2026-07-12)
--
-- Scope (exactly these six models, currently at input 1.2x):
--   gpt-5.5, gpt-5.5-xhigh,
--   opus-4.8, opus-4.8-thinking,
--   claude-opus-4.8, claude-opus-4.8-thinking
--
-- New API tiered_expr coefficient mapping in this deployment:
--   coefficient / 2 = user-facing multiplier.
--   input 1.2x => p * 2.4   ->   input 1.5x => p * 3
--   output stays 6x        =>   c * 12 (UNCHANGED)
--
-- Keeps the zero-output free-billing guard introduced on 2026-07-03:
--   c <= 0 ? tier("zero_output", 0) : (tier("openai_price_gpt55", p * 3 + c * 12))
--
-- INPUT MULTIPLIER ONLY. Output weighting (c * 12) is deliberately unchanged,
-- matching every prior input-multiplier migration
-- (migration-2026-06-29-...-1_5x.sql, migration-2026-07-01-...-1_2x.sql).
--
-- Does NOT touch any other model, billing_mode, channels, abilities, or the
-- ModelRatio/CompletionRatio options. Additive JSON merge, so unlisted models
-- keep their existing billing_expr byte-for-byte.
--
-- Idempotent: safe to re-run.
--
-- Run (Kubernetes):
--   kubectl -n oneapi exec -i deployment/new-api-postgres -- \
--     psql -U oneapi -d oneapi -f - \
--     < migration-2026-07-12-gpt55-opus48-input-1_5x.sql
--
-- Run (local docker compose):
--   docker exec -i new-api-postgres \
--     psql -U newapi -d newapi -f - \
--     < migration-2026-07-12-gpt55-opus48-input-1_5x.sql

\set ON_ERROR_STOP on

BEGIN;

-- Re-assert tiered_expr mode for the six models (no-op if already set). Additive merge.
INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_mode',
  '{"gpt-5.5":"tiered_expr","gpt-5.5-xhigh":"tiered_expr","opus-4.8":"tiered_expr","opus-4.8-thinking":"tiered_expr","claude-opus-4.8":"tiered_expr","claude-opus-4.8-thinking":"tiered_expr"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(options.value, '{}')::jsonb || EXCLUDED.value::jsonb)::text;

-- Input 1.5x (p * 3), output unchanged (c * 12), zero-output guard preserved.
-- Additive merge overwrites ONLY these six keys; all other models are untouched.
INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_expr',
  '{"gpt-5.5":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 3 + c * 12))","gpt-5.5-xhigh":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 3 + c * 12))","opus-4.8":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 3 + c * 12))","opus-4.8-thinking":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 3 + c * 12))","claude-opus-4.8":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 3 + c * 12))","claude-opus-4.8-thinking":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 3 + c * 12))"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(options.value, '{}')::jsonb || EXCLUDED.value::jsonb)::text;

-- Report: confirm the six models now show p * 3 and everything else is unchanged.
SELECT
  m.model,
  opt.value::jsonb ->> m.model AS billing_expr
FROM (
  VALUES
    ('gpt-5.5'), ('gpt-5.5-xhigh'),
    ('opus-4.8'), ('opus-4.8-thinking'),
    ('claude-opus-4.8'), ('claude-opus-4.8-thinking')
) AS m(model)
CROSS JOIN options opt
WHERE opt.key = 'billing_setting.billing_expr'
ORDER BY m.model;

COMMIT;
