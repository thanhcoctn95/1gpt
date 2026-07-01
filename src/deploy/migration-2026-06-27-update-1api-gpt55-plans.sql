-- Migration: update public 1API GPT-5.5 monthly plans (2026-06-27)
-- Purpose: expose the current Plus/Pro/Ultra/Max packages in New API subscription_plans.
-- Run example:
--   docker exec -i new-api-postgres psql -U newapi -d newapi -f - < migration-2026-06-27-update-1api-gpt55-plans.sql

BEGIN;

ALTER TABLE subscription_plans ADD COLUMN IF NOT EXISTS model_list TEXT;
ALTER TABLE subscription_plans ALTER COLUMN price_amount TYPE numeric(14,2);

WITH desired(old_title, title, subtitle, price_amount, sort_order, upgrade_group, total_amount) AS (
  VALUES
    ('BASIC', 'Plus',  '20M token GPT-5.5/ngày; API key riêng; Dashboard usage', 549000::numeric, 10, '',    20000000::bigint),
    ('PRO',   'Pro',   '40M token GPT-5.5/ngày; Hỗ trợ setup code agent',       879000::numeric, 20, '',    40000000::bigint),
    ('ULTRA', 'Ultra', '60M token GPT-5.5/ngày; Log usage chi tiết; Hỗ trợ riêng', 1199000::numeric, 30, '', 60000000::bigint),
    ('S-UTRA','Max',   '80M token GPT-5.5/ngày; Key phụ cho team; Quota rõ hằng ngày', 1549000::numeric, 40, 'max', 80000000::bigint)
), matched AS (
  SELECT DISTINCT ON (d.title)
         d.*, sp.id
  FROM desired d
  LEFT JOIN subscription_plans sp
    ON upper(sp.title) = upper(d.old_title) OR upper(sp.title) = upper(d.title)
  ORDER BY d.title, sp.id ASC NULLS LAST
), updated AS (
  UPDATE subscription_plans sp
  SET title = m.title,
      subtitle = m.subtitle,
      price_amount = m.price_amount,
      currency = 'VND',
      duration_unit = 'month',
      duration_value = 1,
      custom_seconds = 0,
      enabled = true,
      sort_order = m.sort_order,
      max_purchase_per_user = 0,
      upgrade_group = m.upgrade_group,
      total_amount = m.total_amount,
      quota_reset_period = 'daily',
      quota_reset_custom_seconds = 0,
      model_list = NULL,
      updated_at = extract(epoch from now())::bigint
  FROM matched m
  WHERE sp.id = m.id
  RETURNING sp.title
)
INSERT INTO subscription_plans (
  title, subtitle, price_amount, currency, duration_unit, duration_value, custom_seconds,
  enabled, sort_order, stripe_price_id, creem_product_id,
  max_purchase_per_user, upgrade_group, total_amount, quota_reset_period, quota_reset_custom_seconds,
  model_list, created_at, updated_at
)
SELECT d.title, d.subtitle, d.price_amount, 'VND', 'month', 1, 0,
       true, d.sort_order, '', '', 0, d.upgrade_group, d.total_amount, 'daily', 0,
       NULL, extract(epoch from now())::bigint, extract(epoch from now())::bigint
FROM desired d
WHERE NOT EXISTS (
  SELECT 1 FROM subscription_plans sp WHERE upper(sp.title) = upper(d.title)
);

WITH ranked AS (
  SELECT id,
         row_number() OVER (PARTITION BY upper(title) ORDER BY id ASC) AS rn
  FROM subscription_plans
  WHERE upper(title) IN ('PLUS', 'PRO', 'ULTRA', 'MAX')
)
UPDATE subscription_plans sp
SET enabled = false,
    updated_at = extract(epoch from now())::bigint
FROM ranked r
WHERE sp.id = r.id
  AND r.rn > 1;

UPDATE subscription_plans
SET enabled = false,
    updated_at = extract(epoch from now())::bigint
WHERE upper(title) IN ('BASIC', 'S-UTRA');

COMMIT;
