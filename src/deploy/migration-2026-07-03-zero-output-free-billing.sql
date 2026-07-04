-- Migration: do not charge user quota when upstream returns zero output tokens (2026-07-03)
--
-- Context:
--   New API tiered billing expressions normally charge both input (p) and output (c).
--   Some failed/empty upstream responses can still report prompt_tokens > 0 but
--   completion_tokens/output = 0. For those requests, user quota should not be
--   deducted at all.
--
-- Behavior:
--   Wrap every configured tiered billing expression with:
--     c <= 0 ? tier("zero_output", 0) : (<existing expression>)
--
-- Result:
--   - Pre-consume may still reserve quota before the upstream response.
--   - Final settlement with completion_tokens = 0 computes actual quota = 0,
--     so the pre-consumed quota is refunded and the consume log records quota 0.
--
-- Run:
--   docker exec -i new-api-postgres psql -U newapi -d newapi -f - < migration-2026-07-03-zero-output-free-billing.sql
--   # Kubernetes variant:
--   kubectl -n oneapi exec -i deployment/new-api-postgres -- psql -U oneapi -d oneapi -f - < migration-2026-07-03-zero-output-free-billing.sql
--
-- Rollback pattern (replace with the backup value captured before applying):
--   UPDATE options SET value = '<backup billing_setting.billing_expr JSON>'
--   WHERE key = 'billing_setting.billing_expr';

BEGIN;

DO $$
DECLARE
  current_expr jsonb;
  updated_expr jsonb;
BEGIN
  SELECT value::jsonb
    INTO current_expr
    FROM options
   WHERE key = 'billing_setting.billing_expr'
   FOR UPDATE;

  IF current_expr IS NULL THEN
    RAISE NOTICE 'No billing_setting.billing_expr option found; nothing to update.';
    RETURN;
  END IF;

  SELECT jsonb_object_agg(
           model_name,
           CASE
             WHEN position('c <= 0 ? tier("zero_output", 0)' IN expr) > 0 THEN expr
             ELSE 'c <= 0 ? tier("zero_output", 0) : (' || expr || ')'
           END
         )
    INTO updated_expr
    FROM jsonb_each_text(current_expr) AS e(model_name, expr);

  UPDATE options
     SET value = updated_expr::text
   WHERE key = 'billing_setting.billing_expr';

  RAISE NOTICE 'Updated billing_setting.billing_expr: zero output tokens now bill as quota 0.';
END $$;

COMMIT;
