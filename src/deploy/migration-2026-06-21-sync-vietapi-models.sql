-- Migration: sync VietAPI models to channels (2026-06-21)
-- Fixes discrepancies between VietAPI provider and New API channels
--
-- Issues fixed:
--   1. Typos: deep-seek-* → deepseek-* (2 models)
--   2. Missing dot variants: claude-opus-4.x (dot) in addition to dash variants
--   3. Dash-thinking → dot-thinking: claude-opus-4-x-thinking → claude-opus-4.x-thinking
--   4. New models: qwen3.5, glm-5.1, claude-sonnet-4.5-lite, claude-haiku-4.5
--
-- Run: docker exec -i new-api-postgres psql -U newapi -d newapi -f - < migration-2026-06-21-sync-vietapi-models.sql

BEGIN;

-- =====================================================
-- 1. FIX TYPOS: deep-seek-* → deepseek-*
-- =====================================================
DO $$
DECLARE
  ch RECORD;
BEGIN
  FOR ch IN SELECT id, models FROM channels WHERE status = 1 AND models LIKE '%deep-seek-%' LOOP
    UPDATE channels
    SET models = regexp_replace(ch.models, 'deep-seek-', 'deepseek-', 'g')
    WHERE id = ch.id;
    RAISE NOTICE 'Channel id=%: fixed deep-seek-* typo', ch.id;
  END LOOP;
END $$;

-- Delete typo abilities if correct model name already exists (avoids dup key)
DELETE FROM abilities WHERE model = 'deep-seek-v4-flash'
  AND (channel_id, "group") IN (SELECT channel_id, "group" FROM abilities WHERE model = 'deepseek-v4-flash');
UPDATE abilities SET model = 'deepseek-v4-flash' WHERE model = 'deep-seek-v4-flash';

DELETE FROM abilities WHERE model = 'deep-seek-v4-pro'
  AND (channel_id, "group") IN (SELECT channel_id, "group" FROM abilities WHERE model = 'deepseek-v4-pro');
UPDATE abilities SET model = 'deepseek-v4-pro' WHERE model = 'deep-seek-v4-pro';

-- Fix models table typos (rename or insert correct name)
UPDATE models SET model_name = 'deepseek-v4-flash' WHERE model_name = 'deep-seek-v4-flash';
UPDATE models SET model_name = 'deepseek-v4-pro' WHERE model_name = 'deep-seek-v4-pro';


-- =====================================================
-- 2. ADD DOT VARIANTS of Claude Opus (VietAPI serves both dot and dash)
--    claude-opus-4.6, claude-opus-4.7, claude-opus-4.8
-- =====================================================
INSERT INTO models (model_name, description, icon, status, deleted_at) VALUES
  ('claude-opus-4.6', 'Claude Opus 4.6 (dot variant)', 'claude', 1, NULL),
  ('claude-opus-4.7', 'Claude Opus 4.7 (dot variant)', 'claude', 1, NULL),
  ('claude-opus-4.8', 'Claude Opus 4.8 (dot variant)', 'claude', 1, NULL)
ON CONFLICT (model_name, deleted_at) DO NOTHING;

-- Add to channels
DO $$
DECLARE
  ch RECORD;
  dot_models text[] := ARRAY['claude-opus-4.6','claude-opus-4.7','claude-opus-4.8'];
  m text;
  existing_models text[];
  full_models text;
BEGIN
  FOR ch IN SELECT id, models FROM channels WHERE status = 1 LOOP
    existing_models := string_to_array(COALESCE(ch.models, ''), ',');
    full_models := ch.models;

    FOREACH m IN ARRAY dot_models LOOP
      IF NOT (SELECT m = ANY(existing_models)) THEN
        full_models := full_models || CASE WHEN full_models IS NOT NULL AND full_models <> '' THEN ',' ELSE '' END || m;
        RAISE NOTICE 'Channel id=%: added %', ch.id, m;
      END IF;
    END LOOP;

    IF full_models IS DISTINCT FROM ch.models THEN
      UPDATE channels SET models = full_models WHERE id = ch.id;
    END IF;
  END LOOP;
END $$;


-- =====================================================
-- 3. ADD DOT-THINKING VARIANTS (replace dash-thinking)
--    claude-opus-4.x-thinking (dot) replaces claude-opus-4-x-thinking (dash)
-- =====================================================
INSERT INTO models (model_name, description, icon, status, deleted_at) VALUES
  ('claude-opus-4.6-thinking', 'Claude Opus 4.6 thinking (dot variant)', 'claude', 1, NULL),
  ('claude-opus-4.7-thinking', 'Claude Opus 4.7 thinking (dot variant)', 'claude', 1, NULL),
  ('claude-opus-4.8-thinking', 'Claude Opus 4.8 thinking (dot variant)', 'claude', 1, NULL)
ON CONFLICT (model_name, deleted_at) DO NOTHING;

-- Add dot-thinking + remove dash-thinking from channels
DO $$
DECLARE
  ch RECORD;
  dash_thinking text[] := ARRAY['claude-opus-4-6-thinking','claude-opus-4-7-thinking','claude-opus-4-8-thinking'];
  dot_thinking text[] := ARRAY['claude-opus-4.6-thinking','claude-opus-4.7-thinking','claude-opus-4.8-thinking'];
  existing_models text[];
  full_models text;
  i int;
BEGIN
  FOR ch IN SELECT id, models FROM channels WHERE status = 1 LOOP
    existing_models := string_to_array(COALESCE(ch.models, ''), ',');
    full_models := ch.models;

    FOR i IN 1..array_length(dot_thinking, 1) LOOP
      -- Add dot variant if not present
      IF NOT (SELECT dot_thinking[i] = ANY(existing_models)) THEN
        full_models := full_models || ',' || dot_thinking[i];
        RAISE NOTICE 'Channel id=%: added %', ch.id, dot_thinking[i];
      END IF;
      -- Remove dash variant (VietAPI uses dots for thinking)
      IF (SELECT dash_thinking[i] = ANY(existing_models)) THEN
        full_models := regexp_replace(full_models, '\m' || dash_thinking[i] || '\M', '', 'g');
        full_models := regexp_replace(full_models, ',,', ',', 'g');
        full_models := trim(both ',' from full_models);
        RAISE NOTICE 'Channel id=%: removed % (replaced with dot variant)', ch.id, dash_thinking[i];
      END IF;
    END LOOP;

    IF full_models IS DISTINCT FROM ch.models THEN
      UPDATE channels SET models = full_models WHERE id = ch.id;
    END IF;
  END LOOP;
END $$;

-- Replace dash-thinking abilities with dot-thinking (delete dupes first)
DELETE FROM abilities WHERE model = 'claude-opus-4-6-thinking'
  AND (channel_id, "group") IN (SELECT channel_id, "group" FROM abilities WHERE model = 'claude-opus-4.6-thinking');
UPDATE abilities SET model = 'claude-opus-4.6-thinking' WHERE model = 'claude-opus-4-6-thinking';
UPDATE models SET status = 0, updated_time = EXTRACT(EPOCH FROM NOW())::bigint WHERE model_name = 'claude-opus-4-6-thinking' AND deleted_at IS NULL;

DELETE FROM abilities WHERE model = 'claude-opus-4-7-thinking'
  AND (channel_id, "group") IN (SELECT channel_id, "group" FROM abilities WHERE model = 'claude-opus-4.7-thinking');
UPDATE abilities SET model = 'claude-opus-4.7-thinking' WHERE model = 'claude-opus-4-7-thinking';
UPDATE models SET status = 0, updated_time = EXTRACT(EPOCH FROM NOW())::bigint WHERE model_name = 'claude-opus-4-7-thinking' AND deleted_at IS NULL;

DELETE FROM abilities WHERE model = 'claude-opus-4-8-thinking'
  AND (channel_id, "group") IN (SELECT channel_id, "group" FROM abilities WHERE model = 'claude-opus-4.8-thinking');
UPDATE abilities SET model = 'claude-opus-4.8-thinking' WHERE model = 'claude-opus-4-8-thinking';
UPDATE models SET status = 0, updated_time = EXTRACT(EPOCH FROM NOW())::bigint WHERE model_name = 'claude-opus-4-8-thinking' AND deleted_at IS NULL;


-- =====================================================
-- 4. ADD BRAND NEW MODELS (not in any channel)
--    qwen3.5, glm-5.1, claude-sonnet-4.5-lite, claude-haiku-4.5
-- =====================================================
INSERT INTO models (model_name, description, icon, status, deleted_at) VALUES
  ('qwen3.5', 'Qwen 3.5 — Alibaba LLM', 'qwen', 1, NULL),
  ('glm-5.1', 'GLM 5.1 — Zhipu AI', 'glm', 1, NULL),
  ('claude-sonnet-4.5-lite', 'Claude Sonnet 4.5 Lite', 'claude', 1, NULL),
  ('claude-haiku-4.5', 'Claude Haiku 4.5 — fast lightweight model', 'claude', 1, NULL)
ON CONFLICT (model_name, deleted_at) DO NOTHING;

-- Add to channel 1 (primary channel) — find the first active channel
DO $$
DECLARE
  ch RECORD;
  new_models text[] := ARRAY['qwen3.5','glm-5.1','claude-sonnet-4.5-lite','claude-haiku-4.5'];
  m text;
  existing_models text[];
  full_models text;
BEGIN
  -- Add to ALL active channels
  FOR ch IN SELECT id, models FROM channels WHERE status = 1 LOOP
    existing_models := string_to_array(COALESCE(ch.models, ''), ',');
    full_models := ch.models;

    FOREACH m IN ARRAY new_models LOOP
      IF NOT (SELECT m = ANY(existing_models)) THEN
        full_models := full_models || CASE WHEN full_models IS NOT NULL AND full_models <> '' THEN ',' ELSE '' END || m;
        RAISE NOTICE 'Channel id=%: added new model %', ch.id, m;
      END IF;
    END LOOP;

    IF full_models IS DISTINCT FROM ch.models THEN
      UPDATE channels SET models = full_models WHERE id = ch.id;
    END IF;
  END LOOP;
END $$;


-- =====================================================
-- 5. UPDATE PRICING RATIOS for new models
-- =====================================================
DO $$
DECLARE
  ratio_map jsonb := '{
    "claude-opus-4.6": "claude-opus-4-6",
    "claude-opus-4.7": "claude-opus-4-7",
    "claude-opus-4.8": "claude-opus-4-8",
    "claude-opus-4.6-thinking": "claude-opus-4-6-thinking",
    "claude-opus-4.7-thinking": "claude-opus-4-7-thinking",
    "claude-opus-4.8-thinking": "claude-opus-4-8-thinking",
    "qwen3.5": "qwen-3.5",
    "glm-5.1": "glm-5",
    "claude-sonnet-4.5-lite": "claude-sonnet-4.5",
    "claude-haiku-4.5": "claude-haiku-4.5"
  }'::jsonb;
  pair RECORD;
  model_key text;
  fallback_key text;
  opt_key text;
  current_value jsonb;
BEGIN
  FOR opt_key IN SELECT key FROM options WHERE key IN ('ModelRatio','CompletionRatio','GroupRatio') LOOP
    SELECT value::jsonb INTO current_value FROM options WHERE key = opt_key;

    FOR model_key, fallback_key IN SELECT * FROM jsonb_each_text(ratio_map) LOOP
      IF NOT (current_value ? model_key) THEN
        current_value := current_value || jsonb_build_object(
          model_key,
          COALESCE(current_value->>fallback_key, '1')
        );
        RAISE NOTICE 'Set % ratio for % = %', opt_key, model_key, COALESCE(current_value->>fallback_key, '1');
      END IF;
    END LOOP;

    UPDATE options SET value = current_value::text WHERE key = opt_key;
  END LOOP;
END $$;

COMMIT;
