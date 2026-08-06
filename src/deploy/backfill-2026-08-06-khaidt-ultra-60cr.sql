-- Backfill: reset khaidt's total credit back to the canonical Ultra plan (60 credit).
--
-- Context: khaidt showed 70 credit after a +10 credit grant on 2026-08-05.
-- Units: 1 displayed credit = 1,000,000 raw quota. Ultra = 60,000,000.
--
-- This script is DIAGNOSE-FIRST. Run section 1, read the output, and only then
-- run the matching remediation in section 2. Do NOT run the whole file blindly:
-- the correct fix depends on which root cause the diagnostics reveal.
--
-- Idempotent: re-running any section converges to the same state.

\set ON_ERROR_STOP on

-- =====================================================================
-- SECTION 1 — DIAGNOSTICS (read-only). Run this first.
-- =====================================================================

-- 1a. Every active subscription row for khaidt.
--     subscription_count > 1 with a 'never' row  => stacked token pack (Cause A)
--     single 'daily' row with daily_extra_quota>0 => stale daily extra (Cause B)
SELECT s.id AS subscription_id, p.title, p.quota_reset_period,
       s.amount_total, s.amount_used,
       COALESCE(s.daily_extra_quota, 0) AS daily_extra_quota,
       (s.amount_total - s.amount_used) AS amount_left,
       s.source,
       to_timestamp(s.last_reset_time) AS last_reset,
       to_timestamp(s.next_reset_time) AS next_reset,
       to_timestamp(s.end_time) AS end_time
FROM user_subscriptions s
JOIN users u ON u.id = s.user_id
LEFT JOIN subscription_plans p ON p.id = s.plan_id
WHERE u.username = 'khaidt' AND s.status = 'active'
ORDER BY s.id;

-- 1b. Aggregate exactly as the admin UI computes it (this is the "70" on screen).
SELECT sum(s.amount_total)::bigint AS total_quota,
       (sum(s.amount_total) / 1000000.0) AS total_credit,
       count(*) AS active_subscription_count
FROM user_subscriptions s
JOIN users u ON u.id = s.user_id
WHERE u.username = 'khaidt' AND s.status = 'active'
  AND s.end_time > extract(epoch FROM now())::bigint;

-- 1c. Has the Ultra plan itself been edited away from 60,000,000?
SELECT id, title, total_amount, quota_reset_period, enabled
FROM subscription_plans
WHERE lower(title) = 'ultra';

-- 1d. Actual usage from logs since the current reset window (source of truth
--     for amount_used; keep this value, do not zero it).
SELECT COALESCE(SUM(l.quota), 0)::bigint AS used_from_logs,
       (COALESCE(SUM(l.quota), 0) / 1000000.0) AS used_credit
FROM logs l
JOIN users u ON u.id = l.user_id
JOIN user_subscriptions s ON s.user_id = u.id AND s.status = 'active'
LEFT JOIN subscription_plans p ON p.id = s.plan_id
WHERE u.username = 'khaidt'
  AND COALESCE(p.quota_reset_period, 'daily') <> 'never'
  AND l.created_at >= s.last_reset_time
  AND (s.next_reset_time = 0 OR l.created_at < s.next_reset_time);


-- =====================================================================
-- SECTION 2 — REMEDIATION. Run ONLY the block matching the diagnosis.
-- =====================================================================

-- ---------------------------------------------------------------------
-- CAUSE A: a stacked token pack row (quota_reset_period='never') is adding
-- the extra 10 credit. Cancel that row so only Ultra remains.
-- NOTE: this REMOVES purchased pay-as-you-go tokens. Only run this if the
-- 10 credit was granted by mistake and the user agrees to lose it.
-- ---------------------------------------------------------------------
-- BEGIN;
-- UPDATE user_subscriptions s
-- SET status = 'cancelled', updated_at = extract(epoch FROM now())::bigint
-- FROM users u, subscription_plans p
-- WHERE u.id = s.user_id AND p.id = s.plan_id
--   AND u.username = 'khaidt'
--   AND s.status = 'active'
--   AND p.quota_reset_period = 'never';
-- COMMIT;

-- ---------------------------------------------------------------------
-- CAUSE B: a stale daily_extra_quota is inflating amount_total on the
-- monthly Ultra row. This mirrors the fixed cron: pin amount_total to the
-- plan total, clear the extra, and reconcile amount_used from logs.
-- This is the expected fix for the reported symptom.
-- ---------------------------------------------------------------------
-- BEGIN;
-- UPDATE user_subscriptions s
-- SET amount_total = p.total_amount,
--     daily_extra_quota = 0,
--     amount_used = (
--         SELECT COALESCE(SUM(l.quota), 0)::bigint
--         FROM logs l
--         WHERE l.user_id = s.user_id
--           AND l.created_at >= s.last_reset_time
--           AND (s.next_reset_time = 0 OR l.created_at < s.next_reset_time)
--     ),
--     updated_at = extract(epoch FROM now())::bigint
-- FROM subscription_plans p, users u
-- WHERE p.id = s.plan_id AND u.id = s.user_id
--   AND u.username = 'khaidt'
--   AND s.status = 'active'
--   AND COALESCE(p.quota_reset_period, 'daily') <> 'never';
-- COMMIT;

-- ---------------------------------------------------------------------
-- CAUSE C: the Ultra plan row itself drifted to 70,000,000. Fix the plan;
-- the 00:00 cron then re-pins every Ultra subscriber automatically.
-- Verify with 1c BEFORE running: this affects ALL Ultra users, not just khaidt.
-- ---------------------------------------------------------------------
-- BEGIN;
-- UPDATE subscription_plans
-- SET total_amount = 60000000, updated_at = extract(epoch FROM now())::bigint
-- WHERE lower(title) = 'ultra'
--   AND COALESCE(quota_reset_period, 'daily') <> 'never'
--   AND total_amount IS DISTINCT FROM 60000000;
-- COMMIT;


-- =====================================================================
-- SECTION 3 — VERIFICATION. Must show total_credit = 60.
-- =====================================================================
-- SELECT sum(s.amount_total)::bigint AS total_quota,
--        (sum(s.amount_total) / 1000000.0) AS total_credit,
--        sum(s.amount_used)::bigint AS used_quota,
--        (sum(s.amount_total - s.amount_used) / 1000000.0) AS left_credit,
--        count(*) AS active_subscription_count
-- FROM user_subscriptions s
-- JOIN users u ON u.id = s.user_id
-- WHERE u.username = 'khaidt' AND s.status = 'active'
--   AND s.end_time > extract(epoch FROM now())::bigint;
