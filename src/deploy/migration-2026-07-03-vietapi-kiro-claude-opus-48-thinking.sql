-- Migration: ensure VietAPI KIRO Claude Opus 4.8 Thinking is available in New API (2026-07-03)
-- Model: claude-opus-4.8-thinking (KIRO)
-- Run: docker exec -i new-api-postgres psql -U newapi -d newapi -f - < migration-2026-07-03-vietapi-kiro-claude-opus-48-thinking.sql

BEGIN;

-- 1. Ensure the user/admin portal can discover the model from New API's models table.
INSERT INTO models (model_name, description, icon, status, deleted_at)
VALUES ('claude-opus-4.8-thinking (KIRO)', 'VietAPI KIRO — Claude Opus 4.8 Thinking', 'claude', 1, NULL)
ON CONFLICT (model_name, deleted_at) DO UPDATE
SET description = EXCLUDED.description,
    icon = EXCLUDED.icon,
    status = 1,
    updated_time = EXTRACT(EPOCH FROM NOW())::bigint;

-- 2. Add model to every active VietAPI/New API channel if it is not listed yet.
DO $$
DECLARE
  ch RECORD;
  target_model CONSTANT text := 'claude-opus-4.8-thinking (KIRO)';
  existing_models text[];
  updated_models text;
BEGIN
  FOR ch IN SELECT id, models FROM channels WHERE status = 1 LOOP
    existing_models := string_to_array(COALESCE(ch.models, ''), ',');

    IF NOT (target_model = ANY(existing_models)) THEN
      updated_models := COALESCE(NULLIF(ch.models, ''), '');
      updated_models := updated_models || CASE WHEN updated_models <> '' THEN ',' ELSE '' END || target_model;

      UPDATE channels SET models = updated_models WHERE id = ch.id;
      RAISE NOTICE 'Channel id=%: added %', ch.id, target_model;
    ELSE
      RAISE NOTICE 'Channel id=%: % already present', ch.id, target_model;
    END IF;
  END LOOP;
END $$;

-- 3. Ensure routing abilities exist for each active channel/group serving the model.
DO $$
DECLARE
  ch RECORD;
  g text;
  groups text[];
  target_model CONSTANT text := 'claude-opus-4.8-thinking (KIRO)';
BEGIN
  FOR ch IN
    SELECT id, "group"
    FROM channels
    WHERE status = 1
      AND models LIKE '%' || target_model || '%'
  LOOP
    groups := string_to_array(COALESCE(NULLIF(ch."group", ''), 'default'), ',');

    FOREACH g IN ARRAY groups LOOP
      IF NOT EXISTS (
        SELECT 1
        FROM abilities
        WHERE channel_id = ch.id
          AND model = target_model
          AND "group" = g
      ) THEN
        INSERT INTO abilities (channel_id, model, "group", enabled, priority, weight)
        VALUES (ch.id, target_model, g, true, 0, 0);
        RAISE NOTICE 'Channel id=%: added ability group=% model=%', ch.id, g, target_model;
      END IF;
    END LOOP;
  END LOOP;
END $$;

-- 4. Keep billing ratios aligned with the current premium Claude/GPT-5.5 tier.
DO $$
DECLARE
  opt_key text;
  current_value jsonb;
  target_model CONSTANT text := 'claude-opus-4.8-thinking (KIRO)';
BEGIN
  FOR opt_key IN SELECT key FROM options WHERE key IN ('ModelRatio','CompletionRatio','GroupRatio') LOOP
    SELECT value::jsonb INTO current_value FROM options WHERE key = opt_key;

    current_value := current_value || jsonb_build_object(
      target_model,
      COALESCE(
        current_value->>target_model,
        current_value->>'opus-4.8-thinking',
        current_value->>'claude-opus-4.8',
        current_value->>'gpt-5.5-xhigh',
        current_value->>'gpt-5.5',
        '1'
      )
    );

    UPDATE options SET value = current_value::text WHERE key = opt_key;
    RAISE NOTICE 'Updated % for %', opt_key, target_model;
  END LOOP;
END $$;

COMMIT;
