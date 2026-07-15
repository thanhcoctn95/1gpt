-- Migration: add gpt-5.6-sol + gpt-5.6-terra with credit billing (2026-07-10)
--
-- Credit pricing (user-facing, input reference rate; output metered like gpt-5.5):
--   gpt-5.6-sol   -> 3 credit / 1M input tokens, output metered like gpt-5.5
--   gpt-5.6-terra -> 2 credit / 1M input tokens, output metered like gpt-5.5
--
-- New API tiered_expr coefficient mapping in this deployment:
--   expression coefficient / 2 = user-facing multiplier, and displayed credit/1M
--   = coefficient * 0.5 (see PricingController/DashboardController.modelRatios,
--   which derives display rates from billing_expr when the ModelRatio option is
--   empty). Therefore:
--     3 cr/1M input  => p * 6
--     2 cr/1M input  => p * 4
--     output like gpt-5.5 (6 cr/1M output) => c * 12
--
--   gpt-5.6-sol   : c <= 0 ? tier("zero_output", 0) : (tier("openai_price_gpt55", p * 6 + c * 12))
--   gpt-5.6-terra : c <= 0 ? tier("zero_output", 0) : (tier("openai_price_gpt55", p * 4 + c * 12))
--
-- Keeps the zero-output free-billing guard introduced on 2026-07-03.
-- Does not change any existing model's ratios or billing.
--
-- REQUIREMENT: New API must have MEMORY_CACHE_ENABLED=true (set in k8s/04-new-api.yaml).
--   Without it, the in-memory channel cache is disabled and the DB-mode fallback
--   does not pick up newly added models from the abilities table.
--
-- Idempotent: safe to re-run.
--
-- Run (Kubernetes):
--   kubectl -n oneapi exec -i deployment/new-api-postgres -- \
--     psql -U oneapi -d oneapi -f - \
--     < migration-2026-07-10-gpt56-sol-terra.sql
--
-- Run (local docker compose):
--   docker exec -i new-api-postgres \
--     psql -U newapi -d newapi -f - \
--     < migration-2026-07-10-gpt56-sol-terra.sql

\set ON_ERROR_STOP on

BEGIN;

-- =====================================================
-- 1. INSERT MODELS into models table (metadata for admin/user UI)
--    NOTE: the unique index uk_model_name_delete_at is on (model_name, deleted_at).
--    Because deleted_at is NULL here and NULL != NULL in Postgres, ON CONFLICT DO
--    NOTHING does NOT dedupe existing live rows. Guard each insert with NOT EXISTS
--    against the live (deleted_at IS NULL) row instead so re-runs never duplicate.
-- =====================================================
INSERT INTO models (model_name, description, icon, status, deleted_at)
SELECT 'gpt-5.6-sol', 'GPT 5.6 Sol — flagship reasoning & coding', 'openai', 1, NULL
WHERE NOT EXISTS (
  SELECT 1 FROM models WHERE model_name = 'gpt-5.6-sol' AND deleted_at IS NULL
);

INSERT INTO models (model_name, description, icon, status, deleted_at)
SELECT 'gpt-5.6-terra', 'GPT 5.6 Terra — balanced reasoning & coding', 'openai', 1, NULL
WHERE NOT EXISTS (
  SELECT 1 FROM models WHERE model_name = 'gpt-5.6-terra' AND deleted_at IS NULL
);

-- =====================================================
-- 2. ADD MODELS TO ALL ACTIVE CHANNELS (CSV models list)
-- =====================================================
DO $$
DECLARE
  ch RECORD;
  new_models text[] := ARRAY['gpt-5.6-sol','gpt-5.6-terra'];
  m text;
  existing_models text[];
  full_models text;
BEGIN
  FOR ch IN SELECT id, models FROM channels WHERE status = 1 LOOP
    existing_models := string_to_array(COALESCE(ch.models, ''), ',');
    full_models := ch.models;

    FOREACH m IN ARRAY new_models LOOP
      IF NOT (SELECT m = ANY(existing_models)) THEN
        full_models := full_models || CASE WHEN full_models IS NOT NULL AND full_models <> '' THEN ',' ELSE '' END || m;
        RAISE NOTICE 'Channel id=%: added model %', ch.id, m;
      ELSE
        RAISE NOTICE 'Channel id=%: model % already present, skipping', ch.id, m;
      END IF;
    END LOOP;

    IF full_models IS DISTINCT FROM ch.models THEN
      UPDATE channels SET models = full_models WHERE id = ch.id;
    END IF;
  END LOOP;
END $$;

-- =====================================================
-- 3. ENSURE ROUTING ABILITIES for both models on every serving channel/group.
--    priority = 0, weight = 0 so serving channels share one load-balance tier.
-- =====================================================
DO $$
DECLARE
  ch RECORD;
  g  text;
  groups text[];
  m text;
  new_models text[] := ARRAY['gpt-5.6-sol','gpt-5.6-terra'];
BEGIN
  FOR ch IN
    SELECT id, "group", models
    FROM channels
    WHERE status = 1
  LOOP
    groups := string_to_array(COALESCE(NULLIF(ch."group", ''), 'default'), ',');

    FOREACH m IN ARRAY new_models LOOP
      -- only add abilities for models actually present on this channel's CSV list
      IF m = ANY(string_to_array(COALESCE(ch.models, ''), ',')) THEN
        FOREACH g IN ARRAY groups LOOP
          INSERT INTO abilities (channel_id, model, "group", enabled, priority, weight)
          VALUES (ch.id, m, g, true, 0, 0)
          ON CONFLICT ("group", model, channel_id) DO UPDATE
          SET enabled = true;
          RAISE NOTICE 'Channel id=%: ensured ability group=% model=%', ch.id, g, m;
        END LOOP;
      END IF;
    END LOOP;
  END LOOP;
END $$;

-- =====================================================
-- 4. BILLING
--    4a. Legacy ratio maps (ModelRatio / CompletionRatio): only fill an entry when
--        the option already exists and lacks the model. Never CREATE the option.
--        The portal derives display rates from billing_expr when ModelRatio is
--        empty; creating a ModelRatio map here would flip that path and hide every
--        model that lacks a map entry.
-- =====================================================
DO $$
DECLARE
  current_ratio jsonb;
  current_completion jsonb;
BEGIN
  SELECT value::jsonb INTO current_ratio FROM options WHERE key = 'ModelRatio';
  IF current_ratio IS NOT NULL THEN
    IF NOT (current_ratio ? 'gpt-5.6-sol') THEN
      current_ratio := current_ratio || jsonb_build_object('gpt-5.6-sol', 3);
    END IF;
    IF NOT (current_ratio ? 'gpt-5.6-terra') THEN
      current_ratio := current_ratio || jsonb_build_object('gpt-5.6-terra', 2);
    END IF;
    UPDATE options SET value = current_ratio::text WHERE key = 'ModelRatio';
    RAISE NOTICE 'ModelRatio updated for gpt-5.6-sol/gpt-5.6-terra';
  END IF;

  SELECT value::jsonb INTO current_completion FROM options WHERE key = 'CompletionRatio';
  IF current_completion IS NOT NULL THEN
    -- completion_ratio = output credit / input credit. Output = 6 cr/1M for both;
    -- input = 3 (sol) / 2 (terra), so completion_ratio = 2 (sol) and 3 (terra).
    IF NOT (current_completion ? 'gpt-5.6-sol') THEN
      current_completion := current_completion || jsonb_build_object('gpt-5.6-sol', 2);
    END IF;
    IF NOT (current_completion ? 'gpt-5.6-terra') THEN
      current_completion := current_completion || jsonb_build_object('gpt-5.6-terra', 3);
    END IF;
    UPDATE options SET value = current_completion::text WHERE key = 'CompletionRatio';
    RAISE NOTICE 'CompletionRatio updated for gpt-5.6-sol/gpt-5.6-terra';
  END IF;
END $$;

-- 4b. tiered_expr billing (billing_mode / billing_expr). Source of truth for both
--     charging and portal display. Additive merge; INSERT the option if absent.
INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_mode',
  '{"gpt-5.6-sol":"tiered_expr","gpt-5.6-terra":"tiered_expr"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(options.value, '{}')::jsonb || EXCLUDED.value::jsonb)::text;

INSERT INTO options (key, value)
VALUES (
  'billing_setting.billing_expr',
  '{"gpt-5.6-sol":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 6 + c * 12))","gpt-5.6-terra":"c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 4 + c * 12))"}'
)
ON CONFLICT (key) DO UPDATE
SET value = (COALESCE(options.value, '{}')::jsonb || EXCLUDED.value::jsonb)::text;

-- =====================================================
-- 5. REPORT
-- =====================================================
SELECT id, name, status, "group", models
FROM channels
WHERE status = 1
  AND (models LIKE '%gpt-5.6-sol%' OR models LIKE '%gpt-5.6-terra%')
ORDER BY id;

SELECT a.channel_id, a.model, a."group", a.enabled, a.priority, a.weight
FROM abilities a
WHERE a.model IN ('gpt-5.6-sol','gpt-5.6-terra')
ORDER BY a.model, a."group", a.channel_id;

SELECT value FROM options WHERE key IN ('billing_setting.billing_mode','billing_setting.billing_expr');

COMMIT;
