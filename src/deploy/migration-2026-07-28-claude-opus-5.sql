-- Migration: enable Claude Opus 5 on the 3party channel and in every package.
--
-- Prerequisite: the 3party upstream already exposes `claude-opus-5`.
-- Billing follows the approved Claude Opus 5 policy in this deployment:
--   input  3.0 credit / 1M tokens -> p * 6
--   output 6.0 credit / 1M tokens -> c * 12
--
-- Package semantics are preserved:
--   model_list IS NULL/blank -> all active channel models (automatically includes Opus 5)
--   explicit model_list      -> append Opus 5 when missing
--
-- Idempotent: safe to re-run.
-- Run locally:
--   docker exec -i oneapi-postgres psql -U newapi -d newapi -f - \
--     < migration-2026-07-28-claude-opus-5.sql

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM channels
    WHERE lower(name) = '3party' AND status = 1
  ) THEN
    RAISE EXCEPTION 'No active 3party channel exists; refusing to create an unroutable model';
  END IF;
END $$;

-- 1. Register and activate the model in the New API catalog.
INSERT INTO models (
  model_name, description, icon, status, created_time, updated_time, deleted_at
)
SELECT
  'claude-opus-5',
  'Claude Opus 5 — flagship Anthropic reasoning and coding model',
  'claude',
  1,
  extract(epoch FROM now())::bigint,
  extract(epoch FROM now())::bigint,
  NULL
WHERE NOT EXISTS (
  SELECT 1
  FROM models
  WHERE model_name = 'claude-opus-5' AND deleted_at IS NULL
);

UPDATE models
SET status = 1,
    description = COALESCE(NULLIF(description, ''), 'Claude Opus 5 — flagship Anthropic reasoning and coding model'),
    icon = COALESCE(NULLIF(icon, ''), 'claude'),
    updated_time = extract(epoch FROM now())::bigint
WHERE model_name = 'claude-opus-5' AND deleted_at IS NULL;

-- 2. Expose the model only on the active 3party channel that serves it upstream.
UPDATE channels c
SET models = concat_ws(',', NULLIF(btrim(c.models), ''), 'claude-opus-5')
WHERE lower(c.name) = '3party'
  AND c.status = 1
  AND NOT EXISTS (
    SELECT 1
    FROM regexp_split_to_table(COALESCE(c.models, ''), ',') AS existing(model)
    WHERE btrim(existing.model) = 'claude-opus-5'
  );

-- 3. Enable routing for every group on the serving channel. Inherit the
-- channel priority/weight, matching the existing 3party Claude Opus routes.
INSERT INTO abilities (channel_id, model, "group", enabled, priority, weight)
SELECT
  c.id,
  'claude-opus-5',
  btrim(channel_group.name),
  true,
  COALESCE(c.priority, 0),
  COALESCE(c.weight, 0)
FROM channels c
CROSS JOIN LATERAL regexp_split_to_table(
  COALESCE(NULLIF(c."group", ''), 'default'), ','
) AS channel_group(name)
WHERE lower(c.name) = '3party'
  AND c.status = 1
  AND btrim(channel_group.name) <> ''
  AND EXISTS (
    SELECT 1
    FROM regexp_split_to_table(COALESCE(c.models, ''), ',') AS served(model)
    WHERE btrim(served.model) = 'claude-opus-5'
  )
ON CONFLICT ("group", model, channel_id) DO UPDATE
SET enabled = true,
    priority = EXCLUDED.priority,
    weight = EXCLUDED.weight;

-- 4. Add billing without changing any existing model's policy.
-- Do not create legacy ratio maps when this deployment does not use them.
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

-- 5. Include the model in every package while preserving the special NULL/blank
-- value that means "all active models". This also covers disabled legacy plans in
-- case an existing subscription still references one.
UPDATE subscription_plans p
SET model_list = concat_ws(',', NULLIF(btrim(p.model_list), ''), 'claude-opus-5'),
    updated_at = extract(epoch FROM now())::bigint
WHERE p.model_list IS NOT NULL
  AND btrim(p.model_list) <> ''
  AND NOT EXISTS (
    SELECT 1
    FROM regexp_split_to_table(p.model_list, ',') AS granted(model)
    WHERE btrim(granted.model) = 'claude-opus-5'
  );

-- 6a. Refresh tokens for active subscriptions whose package grants all models.
WITH active_models AS (
  SELECT string_agg(model_name, ',' ORDER BY model_name) AS model_limits
  FROM (
    SELECT DISTINCT btrim(channel_model.name) AS model_name
    FROM channels c
    CROSS JOIN LATERAL regexp_split_to_table(
      COALESCE(c.models, ''), ','
    ) AS channel_model(name)
    LEFT JOIN models m
      ON m.model_name = btrim(channel_model.name)
     AND m.deleted_at IS NULL
    WHERE c.status = 1
      AND btrim(channel_model.name) <> ''
      AND COALESCE(m.status, 1) = 1
  ) active
), full_model_users AS (
  SELECT DISTINCT s.user_id
  FROM user_subscriptions s
  JOIN subscription_plans p ON p.id = s.plan_id
  WHERE s.status = 'active'
    AND s.end_time > extract(epoch FROM now())::bigint
    AND (p.model_list IS NULL OR btrim(p.model_list) = '')
)
UPDATE tokens t
SET model_limits_enabled = true,
    model_limits = active_models.model_limits
FROM active_models
WHERE t.user_id IN (SELECT user_id FROM full_model_users)
  AND t.deleted_at IS NULL;

-- 6b. Refresh tokens for users whose active packages all use explicit lists.
WITH active_plan_users AS (
  SELECT s.user_id
  FROM user_subscriptions s
  JOIN subscription_plans p ON p.id = s.plan_id
  WHERE s.status = 'active'
    AND s.end_time > extract(epoch FROM now())::bigint
  GROUP BY s.user_id
  HAVING bool_and(p.model_list IS NOT NULL AND btrim(p.model_list) <> '')
), explicit_models AS (
  SELECT DISTINCT
    s.user_id,
    btrim(granted.model) AS model_name
  FROM user_subscriptions s
  JOIN subscription_plans p ON p.id = s.plan_id
  CROSS JOIN LATERAL regexp_split_to_table(
    COALESCE(p.model_list, ''), ','
  ) AS granted(model)
  WHERE s.status = 'active'
    AND s.end_time > extract(epoch FROM now())::bigint
    AND s.user_id IN (SELECT user_id FROM active_plan_users)
    AND btrim(granted.model) <> ''
), explicit_limits AS (
  SELECT user_id, string_agg(model_name, ',' ORDER BY model_name) AS model_limits
  FROM explicit_models
  GROUP BY user_id
)
UPDATE tokens t
SET model_limits_enabled = true,
    model_limits = limits.model_limits
FROM explicit_limits limits
WHERE t.user_id = limits.user_id
  AND t.deleted_at IS NULL;

-- 7. Verification report.
SELECT model_name, status, description
FROM models
WHERE model_name = 'claude-opus-5' AND deleted_at IS NULL;

SELECT c.id, c.name, c.status, a.model, a."group", a.enabled, a.priority, a.weight
FROM channels c
JOIN abilities a ON a.channel_id = c.id
WHERE a.model = 'claude-opus-5'
ORDER BY c.id, a."group";

SELECT
  id,
  title,
  enabled,
  CASE
    WHEN model_list IS NULL OR btrim(model_list) = '' THEN true
    ELSE EXISTS (
      SELECT 1
      FROM regexp_split_to_table(model_list, ',') AS granted(model)
      WHERE btrim(granted.model) = 'claude-opus-5'
    )
  END AS grants_claude_opus_5
FROM subscription_plans
ORDER BY enabled DESC, sort_order, id;

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
