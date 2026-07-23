-- Repair canonical monthly plan quotas and stale active subscription totals.
-- REVIEW ONLY: run the diagnostics first; do not apply directly without a backup/change window.
-- Units: 1 displayed credit = 1,000,000 raw quota.

-- Dry run: plan rows that disagree with the portal contract.
WITH canonical(title, total_amount) AS (
  VALUES ('Plus', 20000000::bigint), ('Pro', 40000000::bigint),
         ('Ultra', 60000000::bigint), ('Max', 80000000::bigint)
)
SELECT p.id, p.title, p.total_amount AS current_total, c.total_amount AS expected_total
FROM subscription_plans p JOIN canonical c ON lower(c.title) = lower(p.title)
WHERE COALESCE(p.quota_reset_period, 'daily') <> 'never'
  AND p.total_amount <> c.total_amount;

-- Dry run: active monthly subscriptions to reconcile. Daily extras are retained;
-- amount_used is intentionally untouched because usage history/reset ownership belongs
-- to the external New API billing scheduler.
SELECT s.id, s.user_id, p.title, s.amount_total AS current_total,
       p.total_amount + COALESCE(s.daily_extra_quota, 0) AS expected_total,
       s.amount_used, COALESCE(s.daily_extra_quota, 0) AS daily_extra_quota
FROM user_subscriptions s JOIN subscription_plans p ON p.id = s.plan_id
WHERE s.status = 'active' AND COALESCE(p.quota_reset_period, 'daily') <> 'never'
  AND s.amount_total <> p.total_amount + COALESCE(s.daily_extra_quota, 0);

BEGIN;
WITH canonical(title, total_amount) AS (
  VALUES ('Plus', 20000000::bigint), ('Pro', 40000000::bigint),
         ('Ultra', 60000000::bigint), ('Max', 80000000::bigint)
)
UPDATE subscription_plans p
SET total_amount = c.total_amount, updated_at = extract(epoch FROM now())::bigint
FROM canonical c
WHERE lower(c.title) = lower(p.title)
  AND COALESCE(p.quota_reset_period, 'daily') <> 'never'
  AND p.total_amount IS DISTINCT FROM c.total_amount;

UPDATE user_subscriptions s
SET amount_total = p.total_amount + COALESCE(s.daily_extra_quota, 0),
    updated_at = extract(epoch FROM now())::bigint
FROM subscription_plans p
WHERE p.id = s.plan_id AND s.status = 'active'
  AND COALESCE(p.quota_reset_period, 'daily') <> 'never'
  AND s.amount_total IS DISTINCT FROM p.total_amount + COALESCE(s.daily_extra_quota, 0);
COMMIT;

-- Verification: both queries must return zero rows.
WITH canonical(title, total_amount) AS (
  VALUES ('Plus', 20000000::bigint), ('Pro', 40000000::bigint),
         ('Ultra', 60000000::bigint), ('Max', 80000000::bigint)
)
SELECT p.id, p.title, p.total_amount, c.total_amount AS expected
FROM subscription_plans p JOIN canonical c ON lower(c.title) = lower(p.title)
WHERE COALESCE(p.quota_reset_period, 'daily') <> 'never'
  AND p.total_amount <> c.total_amount;

SELECT s.id, s.user_id, p.title, s.amount_total,
       p.total_amount + COALESCE(s.daily_extra_quota, 0) AS expected
FROM user_subscriptions s JOIN subscription_plans p ON p.id = s.plan_id
WHERE s.status = 'active' AND COALESCE(p.quota_reset_period, 'daily') <> 'never'
  AND s.amount_total <> p.total_amount + COALESCE(s.daily_extra_quota, 0);
