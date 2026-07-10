-- Migration: add KIRO Pix4K as an OpenAI-compatible New API channel (2026-07-09)
--
-- Purpose:
--   Add one upstream channel for https://kiro.pix4k.com using OpenAI-compatible
--   /v1/chat/completions format (type=1). Do not use Anthropic channel/env style.
--
-- Defaults:
--   Public/New API model: claude-opus-4.8
--   Base URL:             https://kiro.pix4k.com
--
-- Secret handling:
--   This migration intentionally does not store the API key in the repository.
--   Pass it at apply time with psql -v KIRO_API_KEY=...
--
-- Run (Kubernetes):
--   read -rsp "KIRO_API_KEY: " KIRO_API_KEY; echo
--   kubectl -n oneapi exec -i deployment/new-api-postgres -- \
--     psql -U oneapi -d oneapi -v KIRO_API_KEY="$KIRO_API_KEY" -f - \
--     < migration-2026-07-09-kiro-pix4k-openai-claude-opus-48.sql
--
-- Run (local docker compose):
--   read -rsp "KIRO_API_KEY: " KIRO_API_KEY; echo
--   docker exec -i new-api-postgres \
--     psql -U newapi -d newapi -v KIRO_API_KEY="$KIRO_API_KEY" -f - \
--     < migration-2026-07-09-kiro-pix4k-openai-claude-opus-48.sql
--
-- Optional model override if KIRO exposes a different model name, for example:
--   psql ... -v KIRO_API_KEY="$KIRO_API_KEY" -v KIRO_MODEL="claude-sonnet-4-5" -f - < ...

\set ON_ERROR_STOP on

\if :{?KIRO_API_KEY}
\else
  \echo 'ERROR: missing required psql variable KIRO_API_KEY. Pass it with -v KIRO_API_KEY=...'
  \quit 1
\endif

\if :{?KIRO_MODEL}
\else
  \set KIRO_MODEL 'claude-opus-4.8'
\endif

BEGIN;

-- 1. Register the exposed model for New API/admin UI discovery.
INSERT INTO models (model_name, description, icon, status, deleted_at)
VALUES (
  :'KIRO_MODEL',
  'KIRO Pix4K — OpenAI-compatible Claude upstream',
  'claude',
  1,
  NULL
)
ON CONFLICT (model_name, deleted_at) DO UPDATE
SET description = EXCLUDED.description,
    icon = EXCLUDED.icon,
    status = 1,
    updated_time = EXTRACT(EPOCH FROM NOW())::bigint;

-- 2. Insert or update the KIRO channel. The OpenAI adaptor appends /v1/chat/completions,
--    so base_url must stay host-only here, not include /v1.
CREATE TEMP TABLE _kiro_pix4k_target_channel (id int PRIMARY KEY) ON COMMIT DROP;

WITH desired AS (
  SELECT
    1::int AS type,
    :'KIRO_API_KEY'::text AS api_key,
    1::int AS status,
    'kiro-pix4k-openai'::text AS name,
    :'KIRO_MODEL'::text AS model_name,
    'default'::text AS channel_group,
    'https://kiro.pix4k.com'::text AS base_url
), existing AS (
  SELECT c.id
  FROM channels c
  CROSS JOIN desired d
  WHERE c.name = d.name
     OR (COALESCE(c.base_url, '') = d.base_url AND COALESCE(c.models, '') = d.model_name)
  ORDER BY CASE WHEN c.name = d.name THEN 0 ELSE 1 END, c.id
  LIMIT 1
), updated AS (
  UPDATE channels c
     SET type = d.type,
         key = d.api_key,
         status = d.status,
         name = d.name,
         models = d.model_name,
         "group" = d.channel_group,
         base_url = d.base_url,
         auto_ban = 1,
         priority = 0,
         weight = 0,
         channel_info = '{}'::jsonb
    FROM desired d, existing e
   WHERE c.id = e.id
   RETURNING c.id
), inserted AS (
  INSERT INTO channels (
    type, key, status, name, models, "group", base_url, created_time,
    test_time, response_time, other, balance, balance_updated_time,
    used_quota, auto_ban, priority, weight, channel_info
  )
  SELECT
    d.type,
    d.api_key,
    d.status,
    d.name,
    d.model_name,
    d.channel_group,
    d.base_url,
    EXTRACT(EPOCH FROM NOW())::bigint,
    0, 0, '', 0, 0, 0, 1, 0, 0,
    '{}'::jsonb
  FROM desired d
  WHERE NOT EXISTS (SELECT 1 FROM existing)
  RETURNING id
)
INSERT INTO _kiro_pix4k_target_channel (id)
SELECT id FROM updated
UNION ALL
SELECT id FROM inserted;

-- 3. Ensure the model is routable for the channel/group.
INSERT INTO abilities (channel_id, model, "group", enabled, priority, weight)
SELECT c.id, :'KIRO_MODEL'::text, 'default', true, 0, 0
FROM _kiro_pix4k_target_channel c
ON CONFLICT ("group", model, channel_id) DO UPDATE
SET enabled = true,
    priority = EXCLUDED.priority,
    weight = EXCLUDED.weight;

-- 4. Confirm without printing the secret.
SELECT
  c.id,
  c.name,
  c.type,
  c.status,
  c.models,
  c."group",
  c.base_url,
  CASE WHEN c.key IS NULL OR c.key = '' THEN 'missing' ELSE 'set' END AS key_status
FROM channels c
JOIN _kiro_pix4k_target_channel t ON t.id = c.id;

SELECT a.channel_id, a.model, a."group", a.enabled, a.priority, a.weight
FROM abilities a
JOIN _kiro_pix4k_target_channel t ON t.id = a.channel_id
WHERE a.model = :'KIRO_MODEL'::text;

COMMIT;
