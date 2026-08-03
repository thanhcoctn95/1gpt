-- Migration: activate GPT-5.6 Luna on 9router (2026-07-23)
--
-- Billing: 0.8 credit / 1M input tokens, 6 credit / 1M output tokens.
-- tiered_expr coefficient mapping: input p * 1.6, output c * 12.
-- Idempotent: safe to re-run.

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO models (model_name, description, icon, status, deleted_at)
SELECT 'gpt-5.6-luna', 'GPT 5.6 Luna — efficient reasoning & coding', 'openai', 1, NULL
WHERE NOT EXISTS (
  SELECT 1 FROM models WHERE model_name = 'gpt-5.6-luna' AND deleted_at IS NULL
);

UPDATE models
SET status = 1, updated_time = extract(epoch from now())::bigint
WHERE model_name = 'gpt-5.6-luna' AND deleted_at IS NULL;

UPDATE channels
SET models = concat_ws(',', NULLIF(models, ''), 'gpt-5.6-luna')
WHERE name = '9router'
  AND status = 1
  AND NOT ('gpt-5.6-luna' = ANY(string_to_array(COALESCE(models, ''), ',')));

INSERT INTO abilities (channel_id, model, "group", enabled, priority, weight)
SELECT id, 'gpt-5.6-luna', COALESCE(NULLIF("group", ''), 'default'), true, 12, 1
FROM channels
WHERE name = '9router' AND status = 1
ON CONFLICT ("group", model, channel_id) DO UPDATE
SET enabled = true, priority = EXCLUDED.priority, weight = EXCLUDED.weight;

UPDATE options
SET value = (value::jsonb || jsonb_build_object('gpt-5.6-luna', 0.8))::text
WHERE key = 'ModelRatio';

UPDATE options
SET value = (value::jsonb || jsonb_build_object('gpt-5.6-luna', 7.5))::text
WHERE key = 'CompletionRatio';

INSERT INTO options (key, value)
VALUES ('billing_setting.billing_mode', '{"gpt-5.6-luna":"tiered_expr"}')
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(options.value, '{}')::jsonb || EXCLUDED.value::jsonb)::text;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_expr',
  '{"gpt-5.6-luna":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 1.6 + c * 12))"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(options.value, '{}')::jsonb || EXCLUDED.value::jsonb)::text;

-- Refresh native New API model support for users whose plan grants all active models.
WITH active_models AS (
  SELECT string_agg(cm.model_name, ',' ORDER BY cm.model_name) AS model_limits
  FROM (
    SELECT DISTINCT trim(model) AS model_name
    FROM channels c
    CROSS JOIN LATERAL regexp_split_to_table(COALESCE(c.models, ''), ',') AS model
    LEFT JOIN models m ON m.model_name = trim(model) AND m.deleted_at IS NULL
    WHERE c.status = 1 AND trim(model) <> '' AND COALESCE(m.status, 1) = 1
  ) cm
), full_model_users AS (
  SELECT DISTINCT s.user_id
  FROM user_subscriptions s
  JOIN subscription_plans p ON p.id = s.plan_id
  WHERE s.status = 'active'
    AND s.end_time > extract(epoch from now())::bigint
    AND (p.model_list IS NULL OR btrim(p.model_list) = '')
)
UPDATE tokens t
SET model_limits_enabled = true,
    model_limits = (SELECT model_limits FROM active_models)
WHERE t.user_id IN (SELECT user_id FROM full_model_users)
  AND t.deleted_at IS NULL;

SELECT model_name, status FROM models
WHERE model_name = 'gpt-5.6-luna' AND deleted_at IS NULL;

SELECT c.id, c.name, c.status, a.model, a.enabled, a.priority, a.weight
FROM channels c
JOIN abilities a ON a.channel_id = c.id
WHERE a.model = 'gpt-5.6-luna';

SELECT key, value::jsonb -> 'gpt-5.6-luna' AS luna
FROM options
WHERE key IN ('ModelRatio', 'CompletionRatio', 'billing_setting.billing_mode', 'billing_setting.billing_expr')
ORDER BY key;

COMMIT;
