-- Migration: add claude-sonnet-5, deepseek-v4-flash, deepseek-v4-pro from VietAPI (2026-07-02)
--
-- Pricing:
--   deepseek-v4-flash -> user_token_1x (p * 0.001 + c * 0.001) — input & output * 1/1000
--   deepseek-v4-pro   -> user_token_0_5x (p * 1 + c * 1) — same as glm-5.2 (* 0.5)
--   claude-sonnet-5   -> openai_price_gpt55 (p * 2.4 + c * 12) — input 1.2x, output 6x
--
-- REQUIREMENT: New API must have MEMORY_CACHE_ENABLED=true env var (set in k8s/04-new-api.yaml).
--   Without it, the in-memory channel cache is disabled and the DB-mode fallback
--   does not pick up newly added models from the abilities table.
--
-- Run: kubectl -n oneapi exec deployment/new-api-postgres -- psql -U oneapi -d oneapi -f - < migration-2026-07-02-vietapi-new-models.sql

BEGIN;

-- =====================================================
-- 1. INSERT MODELS into models table (metadata for admin UI)
-- =====================================================
INSERT INTO models (model_name, description, icon, status, deleted_at) VALUES
  ('claude-sonnet-5', 'Claude Sonnet 5 — latest Anthropic coding & reasoning model', 'claude', 1, NULL),
  ('deepseek-v4-flash', 'DeepSeek V4 Flash — fast, lightweight', 'deepseek', 1, NULL),
  ('deepseek-v4-pro', 'DeepSeek V4 Pro — reasoning nâng cao', 'deepseek', 1, NULL)
ON CONFLICT (model_name, deleted_at) DO NOTHING;

-- =====================================================
-- 2. ADD MODELS TO ALL ACTIVE CHANNELS
-- =====================================================
DO $$
DECLARE
  ch RECORD;
  new_models text[] := ARRAY['claude-sonnet-5','deepseek-v4-flash','deepseek-v4-pro'];
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
-- 3. UPDATE BILLING SETTINGS
--    deepseek-v4-flash -> user_token_1x
--    deepseek-v4-pro   -> user_token_0_5x (same as glm-5.2)
--    claude-sonnet-5   -> openai_price_gpt55 (input 1.2x, output 6x)
-- =====================================================
DO $$
DECLARE
  mode_json jsonb;
  expr_json jsonb;
BEGIN
  -- billing_setting.billing_mode
  SELECT COALESCE(value::jsonb, '{}'::jsonb) INTO mode_json FROM options WHERE key = 'billing_setting.billing_mode';

  IF NOT (mode_json ? 'claude-sonnet-5') THEN
    mode_json := mode_json || '{"claude-sonnet-5": "tiered_expr"}'::jsonb;
  END IF;
  IF NOT (mode_json ? 'deepseek-v4-flash') THEN
    mode_json := mode_json || '{"deepseek-v4-flash": "tiered_expr"}'::jsonb;
  END IF;
  IF NOT (mode_json ? 'deepseek-v4-pro') THEN
    mode_json := mode_json || '{"deepseek-v4-pro": "tiered_expr"}'::jsonb;
  END IF;

  UPDATE options SET value = mode_json::text WHERE key = 'billing_setting.billing_mode';

  -- billing_setting.billing_expr
  SELECT COALESCE(value::jsonb, '{}'::jsonb) INTO expr_json FROM options WHERE key = 'billing_setting.billing_expr';

  IF NOT (expr_json ? 'claude-sonnet-5') THEN
    expr_json := expr_json || '{"claude-sonnet-5": "tier(\"openai_price_gpt55\", p * 2.4 + c * 12)"}'::jsonb;
  END IF;
  IF NOT (expr_json ? 'deepseek-v4-flash') THEN
    expr_json := expr_json || '{"deepseek-v4-flash": "tier(\"user_token_1x\", p * 2 + c * 2)"}'::jsonb;
  END IF;
  IF NOT (expr_json ? 'deepseek-v4-pro') THEN
    expr_json := expr_json || '{"deepseek-v4-pro": "tier(\"user_token_0_5x\", p * 1 + c * 1)"}'::jsonb;
  END IF;

  UPDATE options SET value = expr_json::text WHERE key = 'billing_setting.billing_expr';

  RAISE NOTICE 'Updated billing settings: claude-sonnet-5=openai_price_gpt55, deepseek-v4-flash=user_token_1x, deepseek-v4-pro=user_token_0_5x';
END $$;

COMMIT;
