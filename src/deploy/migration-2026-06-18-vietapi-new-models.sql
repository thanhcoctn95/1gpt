-- Migration: add new models from VietAPI (2026-06-18)
-- 
-- New models from https://api.vietapi.tech:
--   deepseek-v4-pro (new)
--   claude-opus-4-6, claude-opus-4-7, claude-opus-4-8 (hyphen variants)
--   claude-opus-4-6-thinking, claude-opus-4-7-thinking, claude-opus-4-8-thinking (hyphen variants)
--
-- Run: psql -U newapi -d newapi -f migration-2026-06-18-vietapi-new-models.sql

BEGIN;

-- 1. Insert new models into `models` table for display metadata
INSERT INTO models (model_name, description, icon, status, deleted_at) VALUES
  ('deepseek-v4-pro', 'DeepSeek V4 Pro - reasoning nâng cao', 'deepseek', 1, NULL),
  ('claude-opus-4-6', 'Claude Opus 4-6 (dấu gạch ngang)', 'claude', 1, NULL),
  ('claude-opus-4-6-thinking', 'Claude Opus 4-6 thinking (dấu gạch ngang)', 'claude', 1, NULL),
  ('claude-opus-4-7', 'Claude Opus 4-7 (dấu gạch ngang)', 'claude', 1, NULL),
  ('claude-opus-4-7-thinking', 'Claude Opus 4-7 thinking (dấu gạch ngang)', 'claude', 1, NULL),
  ('claude-opus-4-8', 'Claude Opus 4-8 (dấu gạch ngang)', 'claude', 1, NULL),
  ('claude-opus-4-8-thinking', 'Claude Opus 4-8 thinking (dấu gạch ngang)', 'claude', 1, NULL)
ON CONFLICT (model_name, deleted_at) DO NOTHING;

-- 2. Add new models to existing channels' model lists
--    We append to the models column of each active channel
--    Adjust the WHERE clause if you have specific channels to target
DO $$
DECLARE
  ch RECORD;
  new_models text[];
  existing_models text[];
  full_models text;
BEGIN
  FOR ch IN SELECT id, models FROM channels WHERE status = 1 LOOP
    existing_models := string_to_array(COALESCE(ch.models, ''), ',');
    new_models := ARRAY[]::text[];

    -- Only add models not already in the channel
    IF NOT (SELECT 'deepseek-v4-pro' = ANY(existing_models)) THEN
      new_models := array_append(new_models, 'deepseek-v4-pro');
    END IF;
    IF NOT (SELECT 'claude-opus-4-6' = ANY(existing_models)) THEN
      new_models := array_append(new_models, 'claude-opus-4-6');
    END IF;
    IF NOT (SELECT 'claude-opus-4-6-thinking' = ANY(existing_models)) THEN
      new_models := array_append(new_models, 'claude-opus-4-6-thinking');
    END IF;
    IF NOT (SELECT 'claude-opus-4-7' = ANY(existing_models)) THEN
      new_models := array_append(new_models, 'claude-opus-4-7');
    END IF;
    IF NOT (SELECT 'claude-opus-4-7-thinking' = ANY(existing_models)) THEN
      new_models := array_append(new_models, 'claude-opus-4-7-thinking');
    END IF;
    IF NOT (SELECT 'claude-opus-4-8' = ANY(existing_models)) THEN
      new_models := array_append(new_models, 'claude-opus-4-8');
    END IF;
    IF NOT (SELECT 'claude-opus-4-8-thinking' = ANY(existing_models)) THEN
      new_models := array_append(new_models, 'claude-opus-4-8-thinking');
    END IF;

    IF array_length(new_models, 1) > 0 THEN
      full_models := COALESCE(ch.models, '') || CASE WHEN ch.models IS NOT NULL AND ch.models <> '' THEN ',' ELSE '' END || array_to_string(new_models, ',');
      UPDATE channels SET models = full_models WHERE id = ch.id;
      RAISE NOTICE 'Channel id=%: added %', ch.id, array_to_string(new_models, ', ');
    ELSE
      RAISE NOTICE 'Channel id=%: no new models to add (all already present)', ch.id;
    END IF;
  END LOOP;
END $$;

-- 3. Update options table with ModelRatio for new models (use same ratio as existing variants)
--    deepseek-v4-pro: use same ratio as deepseek-v4-flash
--    claude-opus-4-6/7/8: use same ratios as claude-opus-4.6/4.7/4.8
UPDATE options
SET value = (
  SELECT jsonb_object_agg(key, value) FROM (
    SELECT key, value FROM jsonb_each_text(value::jsonb)
    UNION ALL
    SELECT 'deepseek-v4-pro', COALESCE(
      (SELECT value::jsonb->>'deepseek-v4-flash'),
      '1'
    )
    UNION ALL
    SELECT 'claude-opus-4-6', COALESCE(
      (SELECT value::jsonb->>'claude-opus-4.6'),
      '1'
    )
    UNION ALL
    SELECT 'claude-opus-4-6-thinking', COALESCE(
      (SELECT value::jsonb->>'claude-opus-4.6-thinking'),
      '1'
    )
    UNION ALL
    SELECT 'claude-opus-4-7', COALESCE(
      (SELECT value::jsonb->>'claude-opus-4.7'),
      '1'
    )
    UNION ALL
    SELECT 'claude-opus-4-7-thinking', COALESCE(
      (SELECT value::jsonb->>'claude-opus-4.7-thinking'),
      '1'
    )
    UNION ALL
    SELECT 'claude-opus-4-8', COALESCE(
      (SELECT value::jsonb->>'claude-opus-4.8'),
      '1'
    )
    UNION ALL
    SELECT 'claude-opus-4-8-thinking', COALESCE(
      (SELECT value::jsonb->>'claude-opus-4.8-thinking'),
      '1'
    )
  ) AS combined
)::text
WHERE key IN ('ModelRatio', 'CompletionRatio', 'GroupRatio');

COMMIT;
