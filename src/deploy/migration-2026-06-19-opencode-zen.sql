-- Migration: add opencode/deepseek-v4-flash-free (Opencode Zen) as alias for deepseek-v4-flash
--
-- Maps opencode/deepseek-v4-flash-free → deepseek-v4-flash on channels that serve
-- DeepSeek models so 9router can route OpenCode's built-in model through existing channels.
--
-- Run: psql -U newapi -d newapi -f migration-2026-06-19-opencode-zen.sql

BEGIN;

-- 1. Register model in `models` table for display metadata + Potal admin visibility
INSERT INTO models (model_name, description, icon, status, deleted_at)
VALUES (
  'opencode/deepseek-v4-flash-free',
  'DeepSeek V4 Flash Free — Opencode Zen alias through 9router',
  'deepseek',
  1,
  NULL
)
ON CONFLICT (model_name, deleted_at) DO NOTHING;

-- 2. Add model to active channels that already serve deepseek-v4-flash
--    + update model_mapping: opencode/deepseek-v4-flash-free → deepseek-v4-flash
DO $$
DECLARE
  ch RECORD;
  new_model_name CONSTANT text := 'opencode/deepseek-v4-flash-free';
  mapped_to CONSTANT text := 'deepseek-v4-flash';
  existing_models text[];
  existing_mapping jsonb;
  updated_models text;
  updated_mapping jsonb;
BEGIN
  FOR ch IN
    SELECT id, models, model_mapping
    FROM channels
    WHERE status = 1
      AND models LIKE '%deepseek-v4-flash%'
  LOOP
    -- --- Update models CSV ---
    existing_models := string_to_array(COALESCE(ch.models, ''), ',');

    IF NOT (SELECT new_model_name = ANY(existing_models)) THEN
      updated_models := COALESCE(ch.models, '')
                        || CASE WHEN ch.models IS NOT NULL AND ch.models <> '' THEN ',' ELSE '' END
                        || new_model_name;

      UPDATE channels SET models = updated_models WHERE id = ch.id;
      RAISE NOTICE 'Channel id=%: added % to models', ch.id, new_model_name;
    ELSE
      RAISE NOTICE 'Channel id=%: % already in models', ch.id, new_model_name;
    END IF;

    -- --- Update model_mapping JSON ---
    -- Handle NULL or empty string model_mapping gracefully
    IF ch.model_mapping IS NULL OR ch.model_mapping = '' OR ch.model_mapping = '{}' THEN
      existing_mapping := '{}'::jsonb;
    ELSE
      existing_mapping := ch.model_mapping::jsonb;
    END IF;

    IF NOT (existing_mapping ? new_model_name) THEN
      updated_mapping := existing_mapping || jsonb_build_object(new_model_name, mapped_to);
      UPDATE channels SET model_mapping = updated_mapping::text WHERE id = ch.id;
      RAISE NOTICE 'Channel id=%: added model_mapping % → %', ch.id, new_model_name, mapped_to;
    ELSE
      RAISE NOTICE 'Channel id=%: model_mapping for % already exists', ch.id, new_model_name;
    END IF;
  END LOOP;
END $$;

-- 3. Add abilities entries so the model is routable
DO $$
DECLARE
  ch RECORD;
  groups text[];
  g text;
  new_model_name CONSTANT text := 'opencode/deepseek-v4-flash-free';
BEGIN
  FOR ch IN
    SELECT id, "group"
    FROM channels
    WHERE status = 1
      AND models LIKE '%deepseek-v4-flash%'
  LOOP
    groups := string_to_array(COALESCE(ch."group", 'default'), ',');

    FOREACH g IN ARRAY groups
    LOOP
      IF NOT EXISTS (
        SELECT 1 FROM abilities
        WHERE channel_id = ch.id
          AND model = new_model_name
          AND "group" = g
      ) THEN
        INSERT INTO abilities (channel_id, model, "group", enabled, priority, weight)
        VALUES (ch.id, new_model_name, g, true, 0, 0);
        RAISE NOTICE 'Channel id=%: added ability for group=% model=%', ch.id, g, new_model_name;
      END IF;
    END LOOP;
  END LOOP;
END $$;

-- 4. Update pricing ratios in options table
--    Use same ratio as deepseek-v4-flash for the new alias model
UPDATE options
SET value = (
  SELECT jsonb_object_agg(key, value) FROM (
    SELECT key, value FROM jsonb_each_text(value::jsonb)
    UNION ALL
    SELECT 'opencode/deepseek-v4-flash-free', COALESCE(
      (SELECT value::jsonb->>'deepseek-v4-flash'),
      '1'
    )
  ) AS combined
)::text
WHERE key IN ('ModelRatio', 'CompletionRatio', 'GroupRatio');

COMMIT;
