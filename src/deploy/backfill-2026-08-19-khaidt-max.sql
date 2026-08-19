-- Backfill: upgrade khaidt from Ultra to Max (2026-08-19)
--
-- Mirrors POST /api/admin/provision-user with planId=11 (Max) exactly:
--   ProvisioningController.provisionUser -> ensureSubscription (monthly branch, line ~905)
--   followed by  UPDATE users SET "group" = plan.upgrade_group.
--
-- Target row: the single active monthly subscription of khaidt, selected with the
-- same predicate and ordering the Java code uses (status='active',
-- quota_reset_period != 'never', ORDER BY id DESC LIMIT 1) -> subscription 6.
--
-- Effect on subscription 6:
--   plan_id            10 (Ultra)   -> 11 (Max)
--   amount_total       80,000,000   -> 80,000,000  (was 60M Ultra + 20M daily grant; now 80M Max plan total)
--   amount_used        79,236,626   -> 0           (new billing cycle starts now)
--   daily_extra_quota  20,000,000   -> 0           (temporary grant folded into the plan)
--   start_time         2026-07-30   -> now
--   end_time           2026-08-30   -> now + 1 month
--   last_reset_time                 -> now
--   next_reset_time                 -> tomorrow 00:00 Asia/Ho_Chi_Minh
--   upgrade_group      ''           -> 'max'
--   prev_user_group    ''           -> current users."group" ('default'), kept for rollback
--   source             manual-admin -> portal-admin
--   users."group"      default      -> max
--
-- Does NOT touch subscription 12 (cancelled Standard token pack), other users,
-- plans, channels, models, or billing options.
--
-- NOT idempotent by design: re-running restarts the billing cycle and shifts end_time again.

\set ON_ERROR_STOP on

BEGIN;

-- Resolve the target subscription exactly as ensureSubscription does.
CREATE TEMP TABLE target_sub ON COMMIT DROP AS
SELECT s.id
FROM user_subscriptions s
JOIN users u ON u.id = s.user_id
LEFT JOIN subscription_plans p ON p.id = s.plan_id
WHERE u.username = 'khaidt'
  AND s.status = 'active'
  AND COALESCE(p.quota_reset_period, 'daily') != 'never'
ORDER BY s.id DESC
LIMIT 1;

-- Guard: abort the whole transaction unless exactly one target row was resolved.
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM target_sub;
  IF n <> 1 THEN
    RAISE EXCEPTION 'Expected exactly 1 active monthly subscription for khaidt, found %', n;
  END IF;
END $$;

-- Guard: the Max plan must exist and be enabled (getPlan() enforces enabled=true).
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM subscription_plans
  WHERE id = 11 AND enabled = true AND lower(title) = 'max';
  IF n <> 1 THEN
    RAISE EXCEPTION 'Max plan (id 11) is missing or disabled';
  END IF;
END $$;

UPDATE user_subscriptions s
SET plan_id           = p.id,
    amount_total      = p.total_amount,
    amount_used       = 0,
    daily_extra_quota = 0,
    start_time        = extract(epoch from now())::bigint,
    end_time          = extract(epoch from (now() + interval '1 month'))::bigint,
    last_reset_time   = extract(epoch from now())::bigint,
    next_reset_time   = extract(epoch from (date_trunc('day', now()) + interval '1 day'))::bigint,
    upgrade_group     = COALESCE(p.upgrade_group, ''),
    prev_user_group   = COALESCE(NULLIF(u."group", ''), 'default'),
    source            = 'portal-admin',
    updated_at        = extract(epoch from now())::bigint
FROM subscription_plans p, users u
WHERE s.id = (SELECT id FROM target_sub)
  AND p.id = 11
  AND u.id = s.user_id;

-- users."group" follows plan.upgrade_group, same as provisionUser().
UPDATE users u
SET "group" = p.upgrade_group
FROM subscription_plans p
WHERE u.username = 'khaidt'
  AND p.id = 11
  AND COALESCE(p.upgrade_group, '') <> '';

-- Verification: Max / 80,000,000 total / 0 used / 0 extra / group max.
SELECT s.id AS subscription_id, p.title AS plan, u."group" AS user_group,
       s.amount_total, s.amount_used, s.daily_extra_quota,
       (s.amount_total - s.amount_used) AS amount_left,
       s.status, s.source, s.upgrade_group, s.prev_user_group,
       to_char(to_timestamp(s.start_time),      'YYYY-MM-DD HH24:MI') AS start_t,
       to_char(to_timestamp(s.end_time),        'YYYY-MM-DD HH24:MI') AS end_t,
       to_char(to_timestamp(s.last_reset_time), 'YYYY-MM-DD HH24:MI') AS last_reset,
       to_char(to_timestamp(s.next_reset_time), 'YYYY-MM-DD HH24:MI') AS next_reset
FROM user_subscriptions s
JOIN users u ON u.id = s.user_id
LEFT JOIN subscription_plans p ON p.id = s.plan_id
WHERE u.username = 'khaidt'
ORDER BY s.id DESC;

COMMIT;
