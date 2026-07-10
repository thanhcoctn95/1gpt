-- Fix billing_preference for users provisioned without subscription billing mode.
--
-- Root cause: ProvisioningController.ensureUser() created users with
-- users.setting='' (empty string), causing New API to fall back to wallet
-- billing (users.quota=0) instead of subscription billing.
--
-- Also fix users with JSON setting that's empty or missing billing_preference
-- (New API treats empty/invalid setting as wallet billing, which fails since
-- the portal creates all users with users.quota=0).
--
-- Safe to run: only touches users who have at least one active subscription
-- (wallet-only users are intentionally not modified).
--
-- Dry-run first (count only):
--   kubectl -n oneapi exec deployment/new-api-postgres -- psql -U oneapi -d oneapi -c "SELECT count(*) AS to_fix FROM users u WHERE u.deleted_at IS NULL AND EXISTS (SELECT 1 FROM user_subscriptions s WHERE s.user_id = u.id) AND (u.setting IS NULL OR TRIM(u.setting) IN ('', '{}'));"
--
-- Apply:
--   kubectl -n oneapi exec -i deployment/new-api-postgres -- psql -U oneapi -d oneapi -f - < migration-2026-07-08-billing-preference-fix.sql

WITH updated AS (
    UPDATE users
    SET setting = '{"billing_preference":"subscription_only"}'
    WHERE deleted_at IS NULL
      AND EXISTS (SELECT 1 FROM user_subscriptions s WHERE s.user_id = users.id)
      AND (setting IS NULL OR TRIM(setting) IN ('', '{}'))
    RETURNING id, username
)
SELECT count(*) AS users_fixed FROM updated;
