-- Migration: consolidate Claude Opus 4.8 routing onto a single public model (2026-07-09)
--
-- Purpose:
--   Make BOTH upstream channels serve the same public model `claude-opus-4.8`
--   so New API can load-balance / failover between them:
--     - pix4k channel      (OpenAI-compatible, added in
--                            migration-2026-07-09-kiro-pix4k-openai-claude-opus-48.sql)
--     - VietAPI channels    (previously exposed only as `opus-4.8-thinking`)
--
--   The VietAPI upstream accepts the plain `claude-opus-4.8` string directly,
--   so NO model_mapping is added — New API forwards the model name as-is.
--
-- Routing model (New API):
--   A request is routable to a channel only when an abilities row exists for
--   (group, model, channel_id) with enabled = true. Within the same (model, group),
--   New API prefers the highest ability.priority, then load-balances by weight.
--   This migration puts the new `claude-opus-4.8` ability at priority = 0, weight = 0
--   on every serving channel so both sit in the same tier and share traffic.
--
-- Idempotent: safe to re-run.
--
-- Run (Kubernetes):
--   kubectl -n oneapi exec -i deployment/new-api-postgres -- \
--     psql -U oneapi -d oneapi -f - \
--     < migration-2026-07-09-consolidate-claude-opus-48-routing.sql
--
-- Run (local docker compose):
--   docker exec -i new-api-postgres \
--     psql -U newapi -d newapi -f - \
--     < migration-2026-07-09-consolidate-claude-opus-48-routing.sql

\set ON_ERROR_STOP on

BEGIN;

-- 1. Ensure the public model exists and is discoverable in the admin/user portal.
INSERT INTO models (model_name, description, icon, status, deleted_at)
VALUES ('claude-opus-4.8', 'Claude Opus 4.8 — consolidated upstream (load-balanced)', 'claude', 1, NULL)
ON CONFLICT (model_name, deleted_at) DO UPDATE
SET description = EXCLUDED.description,
    icon = EXCLUDED.icon,
    status = 1,
    updated_time = EXTRACT(EPOCH FROM NOW())::bigint;

-- 2. Add `claude-opus-4.8` to the CSV models list of every active channel that can
--    serve Opus 4.8: channels already serving the thinking variant (VietAPI KIRO)
--    or already serving claude-opus-4.8 (pix4k). Do not touch unrelated channels.
DO $$
DECLARE
  ch RECORD;
  target_model    CONSTANT text := 'claude-opus-4.8';
  existing_models text[];
  updated_models  text;
BEGIN
  -- Target every active channel that can serve Opus 4.8 in THIS deployment:
  -- VietAPI channels expose `opus-4.8-thinking`; pix4k exposes `claude-opus-4.8`.
  FOR ch IN
    SELECT id, models
    FROM channels
    WHERE status = 1
      AND (
        'opus-4.8-thinking' = ANY(string_to_array(COALESCE(models, ''), ','))
        OR 'claude-opus-4.8' = ANY(string_to_array(COALESCE(models, ''), ','))
      )
  LOOP
    existing_models := string_to_array(COALESCE(ch.models, ''), ',');

    IF NOT (target_model = ANY(existing_models)) THEN
      updated_models := COALESCE(NULLIF(ch.models, ''), '');
      updated_models := updated_models
        || CASE WHEN updated_models <> '' THEN ',' ELSE '' END
        || target_model;

      UPDATE channels SET models = updated_models WHERE id = ch.id;
      RAISE NOTICE 'Channel id=%: added model %', ch.id, target_model;
    ELSE
      RAISE NOTICE 'Channel id=%: model % already present', ch.id, target_model;
    END IF;
  END LOOP;
END $$;

-- 3. Ensure a routing ability exists for `claude-opus-4.8` on every serving channel,
--    for each of the channel's groups. New ability sits at priority = 0, weight = 0
--    so all serving channels share the same load-balance tier.
DO $$
DECLARE
  ch RECORD;
  g  text;
  groups text[];
  target_model CONSTANT text := 'claude-opus-4.8';
BEGIN
  FOR ch IN
    SELECT id, "group"
    FROM channels
    WHERE status = 1
      AND target_model = ANY(string_to_array(COALESCE(models, ''), ','))
  LOOP
    groups := string_to_array(COALESCE(NULLIF(ch."group", ''), 'default'), ',');

    FOREACH g IN ARRAY groups LOOP
      INSERT INTO abilities (channel_id, model, "group", enabled, priority, weight)
      VALUES (ch.id, target_model, g, true, 0, 0)
      ON CONFLICT ("group", model, channel_id) DO UPDATE
      SET enabled = true;
      RAISE NOTICE 'Channel id=%: ensured ability group=% model=%', ch.id, g, target_model;
    END LOOP;
  END LOOP;
END $$;

-- 4. Ensure billing covers `claude-opus-4.8`.
--    4a. Legacy ratio maps (only fill if missing; never overwrite existing values).
DO $$
DECLARE
  opt_key text;
  current_value jsonb;
  target_model CONSTANT text := 'claude-opus-4.8';
BEGIN
  FOR opt_key IN
    SELECT key FROM options WHERE key IN ('ModelRatio','CompletionRatio','GroupRatio')
  LOOP
    SELECT value::jsonb INTO current_value FROM options WHERE key = opt_key;
    IF current_value IS NULL THEN CONTINUE; END IF;

    IF current_value ? target_model THEN
      CONTINUE;  -- already configured, leave as-is
    END IF;

    current_value := current_value || jsonb_build_object(
      target_model,
      COALESCE(
        current_value->>'claude-opus-4.8-thinking (KIRO)',
        current_value->>'claude-opus-4.8-thinking',
        current_value->>'opus-4.8-thinking',
        current_value->>'opus-4.8',
        current_value->>'gpt-5.5',
        '1'
      )
    );

    UPDATE options SET value = current_value::text WHERE key = opt_key;
    RAISE NOTICE 'Updated % for %', opt_key, target_model;
  END LOOP;
END $$;

--    4b. tiered_expr billing (billing_mode / billing_expr). Match the current premium
--        Claude/GPT-5.5 tier: input 1.2x, output 6x. Only fill if missing.
DO $$
DECLARE
  current_mode jsonb;
  current_expr jsonb;
  target_model CONSTANT text := 'claude-opus-4.8';
BEGIN
  SELECT value::jsonb INTO current_mode FROM options WHERE key = 'billing_setting.billing_mode';
  SELECT value::jsonb INTO current_expr FROM options WHERE key = 'billing_setting.billing_expr';

  IF current_mode IS NOT NULL AND NOT (current_mode ? target_model) THEN
    current_mode := current_mode || jsonb_build_object(target_model, 'tiered_expr');
    UPDATE options SET value = current_mode::text WHERE key = 'billing_setting.billing_mode';
    RAISE NOTICE 'Added billing_mode tiered_expr for %', target_model;
  END IF;

  IF current_expr IS NOT NULL AND NOT (current_expr ? target_model) THEN
    current_expr := current_expr || jsonb_build_object(
      target_model,
      COALESCE(
        current_expr->>'claude-opus-4.8-thinking',
        current_expr->>'opus-4.8-thinking',
        current_expr->>'gpt-5.5',
        'tier("openai_price_gpt55", p * 2.4 + c * 12)'
      )
    );
    UPDATE options SET value = current_expr::text WHERE key = 'billing_setting.billing_expr';
    RAISE NOTICE 'Added billing_expr for %', target_model;
  END IF;
END $$;

-- 5. Report: which channels now serve `claude-opus-4.8` and how they route.
SELECT
  c.id,
  c.name,
  c.type,
  c.status,
  c."group",
  c.base_url,
  CASE WHEN c.key IS NULL OR c.key = '' THEN 'missing' ELSE 'set' END AS key_status
FROM channels c
WHERE c.status = 1
  AND c.models LIKE '%claude-opus-4.8%'
ORDER BY c.id;

SELECT
  a.channel_id,
  a.model,
  a."group",
  a.enabled,
  a.priority,
  a.weight
FROM abilities a
WHERE a.model = 'claude-opus-4.8'
ORDER BY a."group", a.priority DESC, a.channel_id;

COMMIT;
