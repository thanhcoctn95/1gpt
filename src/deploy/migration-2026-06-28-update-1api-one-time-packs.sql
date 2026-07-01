-- Migration: update 1API one-time packs (2026-06-28)
-- Purpose: align one-time pricing with monthly GPT-5.5 packages.
-- Run example:
--   docker exec -i oneapi-postgres psql -U newapi -d newapi -f - < migration-2026-06-28-update-1api-one-time-packs.sql

BEGIN;

ALTER TABLE subscription_plans ADD COLUMN IF NOT EXISTS model_list TEXT;
ALTER TABLE subscription_plans ALTER COLUMN price_amount TYPE numeric(14,2);

WITH desired(title, subtitle, price_amount, sort_order, total_amount) AS (
  VALUES
    ('Mini',     '50M token — gói one-time',  69000::numeric, 10,  50000000::bigint),
    ('Starter',  '100M token — gói one-time', 129000::numeric, 20, 100000000::bigint),
    ('Standard', '250M token — gói one-time', 299000::numeric, 30, 250000000::bigint),
    ('Power',    '500M token — gói one-time', 549000::numeric, 40, 500000000::bigint)
), matched AS (
  SELECT DISTINCT ON (d.title)
         d.*, sp.id
  FROM desired d
  LEFT JOIN subscription_plans sp
    ON upper(sp.title) = upper(d.title) AND sp.quota_reset_period = 'never'
  ORDER BY d.title, sp.id ASC NULLS LAST
), updated AS (
  UPDATE subscription_plans sp
  SET title = m.title,
      subtitle = m.subtitle,
      price_amount = m.price_amount,
      currency = 'VND',
      duration_unit = 'custom',
      duration_value = 0,
      custom_seconds = 3153600000,
      enabled = true,
      sort_order = m.sort_order,
      max_purchase_per_user = 0,
      upgrade_group = '',
      total_amount = m.total_amount,
      quota_reset_period = 'never',
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
SELECT d.title, d.subtitle, d.price_amount, 'VND', 'custom', 0, 3153600000,
       true, d.sort_order, '', '', 0, '', d.total_amount, 'never', 0,
       NULL, extract(epoch from now())::bigint, extract(epoch from now())::bigint
FROM desired d
WHERE NOT EXISTS (
  SELECT 1 FROM subscription_plans sp
  WHERE upper(sp.title) = upper(d.title) AND sp.quota_reset_period = 'never'
);

WITH ranked AS (
  SELECT id,
         row_number() OVER (PARTITION BY upper(title) ORDER BY id ASC) AS rn
  FROM subscription_plans
  WHERE quota_reset_period = 'never'
    AND upper(title) IN ('MINI', 'STARTER', 'STANDARD', 'POWER')
)
UPDATE subscription_plans sp
SET enabled = false,
    updated_at = extract(epoch from now())::bigint
FROM ranked r
WHERE sp.id = r.id
  AND r.rn > 1;

COMMIT;
