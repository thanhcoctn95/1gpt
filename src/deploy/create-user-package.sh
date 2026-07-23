#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-oneapi}"
POSTGRES_LABEL="${POSTGRES_LABEL:-app=new-api-postgres}"
BILLING_PREFERENCE="${BILLING_PREFERENCE:-subscription_only}"
USER_GROUP="${USER_GROUP:-default}"
TOKEN_GROUP="${TOKEN_GROUP:-}"
TOKEN_NAME="${TOKEN_NAME:-default}"
RESET_TIMEZONE="${RESET_TIMEZONE:-Asia/Ho_Chi_Minh}"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

trim() {
  local value="$*"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  printf '%s' "$value"
}

sql_quote() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf "%s" "$value"
}

generate_key() {
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48
}

generate_password() {
  LC_ALL=C tr -dc 'A-Za-z0-9@#%+=' </dev/urandom | head -c 16
}

bcrypt_hash() {
  local password="$1"
  # New API uses Go bcrypt.DefaultCost. htpasswd -B generates a compatible bcrypt hash.
  htpasswd -bnBC 10 "" "$password" | tr -d ':\n'
}

choose_plan() {
  local choice=""
  echo "Chọn gói:"
  echo "  1) Plus  - 20M quota/ngày"
  echo "  2) Pro   - 40M quota/ngày"
  echo "  3) Ultra - 60M quota/ngày"
  read -r -p "Nhập lựa chọn [1-3]: " choice
  case "$choice" in
    1|plus|Plus|PLUS) PLAN_CODE="plus"; PLAN_TITLE="Plus"; PLAN_SUBTITLE="20M quota / ngày"; PLAN_PRICE="549000"; PLAN_QUOTA="20000000"; PLAN_SORT="10" ;;
    2|pro|Pro|PRO) PLAN_CODE="pro"; PLAN_TITLE="Pro"; PLAN_SUBTITLE="40M quota / ngày"; PLAN_PRICE="879000"; PLAN_QUOTA="40000000"; PLAN_SORT="20" ;;
    3|ultra|Ultra|ULTRA) PLAN_CODE="ultra"; PLAN_TITLE="Ultra"; PLAN_SUBTITLE="60M quota / ngày"; PLAN_PRICE="1199000"; PLAN_QUOTA="60000000"; PLAN_SORT="30" ;;
    *) echo "Lựa chọn gói không hợp lệ" >&2; exit 1 ;;
  esac
}

need_cmd kubectl
need_cmd htpasswd
need_cmd python3

read -r -p "Username: " USERNAME
USERNAME="$(trim "$USERNAME")"
if [[ ! "$USERNAME" =~ ^[A-Za-z0-9_.-]{3,20}$ ]]; then
  echo "Username không hợp lệ. Dùng 3-20 ký tự: A-Z a-z 0-9 _ . -" >&2
  exit 1
fi

read -r -p "Display name [$USERNAME]: " DISPLAY_NAME
DISPLAY_NAME="$(trim "$DISPLAY_NAME")"
if [ -z "$DISPLAY_NAME" ]; then
  DISPLAY_NAME="$USERNAME"
fi
if [ "${#DISPLAY_NAME}" -gt 20 ]; then
  echo "Display name tối đa 20 ký tự" >&2
  exit 1
fi

choose_plan

POD="$(kubectl -n "$NAMESPACE" get pod -l "$POSTGRES_LABEL" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [ -z "$POD" ]; then
  echo "Không tìm thấy postgres pod trong namespace '$NAMESPACE' với label '$POSTGRES_LABEL'" >&2
  echo "Kiểm tra: kubectl -n $NAMESPACE get pod -l $POSTGRES_LABEL" >&2
  exit 1
fi

PASSWORD="${PASSWORD:-$(generate_password)}"
PASSWORD_HASH="$(bcrypt_hash "$PASSWORD")"
TOKEN_KEY="${TOKEN_KEY:-$(generate_key)}"
NOW="$(date +%s)"
END_TIME="$((NOW + 31 * 24 * 60 * 60))"
# Daily reset at next midnight in Vietnam time, matching the 1API deployment timezone.
NEXT_RESET="$(RESET_TIMEZONE="$RESET_TIMEZONE" python3 - <<'PY'
import os
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

tz = ZoneInfo(os.environ.get("RESET_TIMEZONE", "Asia/Ho_Chi_Minh"))
now = datetime.now(tz)
next_midnight = (now + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
print(int(next_midnight.timestamp()))
PY
)"

TOKEN_UNLIMITED="true"
TOKEN_REMAIN="0"
# Token is only the API credential. Daily package quota is enforced by user_subscriptions.
# Do not bind token.remain_quota to the plan because token quota does not reset daily.

SETTING_JSON="{\"billing_preference\":\"$BILLING_PREFERENCE\"}"

USERNAME_SQL="$(sql_quote "$USERNAME")"
DISPLAY_NAME_SQL="$(sql_quote "$DISPLAY_NAME")"
PASSWORD_HASH_SQL="$(sql_quote "$PASSWORD_HASH")"
TOKEN_KEY_SQL="$(sql_quote "$TOKEN_KEY")"
TOKEN_NAME_SQL="$(sql_quote "$TOKEN_NAME")"
USER_GROUP_SQL="$(sql_quote "$USER_GROUP")"
TOKEN_GROUP_SQL="$(sql_quote "$TOKEN_GROUP")"
SETTING_JSON_SQL="$(sql_quote "$SETTING_JSON")"
PLAN_TITLE_SQL="$(sql_quote "$PLAN_TITLE")"
PLAN_SUBTITLE_SQL="$(sql_quote "$PLAN_SUBTITLE")"

SQL="
BEGIN;
DO \$\$
DECLARE
  v_user_id integer;
  v_plan_id integer;
BEGIN
  IF EXISTS (SELECT 1 FROM users WHERE username = '$USERNAME_SQL' AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'username already exists: $USERNAME_SQL';
  END IF;

  INSERT INTO users
    (username, password, display_name, role, status, quota, used_quota, request_count, \"group\", aff_code, aff_count, aff_quota, aff_history, inviter_id, setting, remark, created_at, last_login_at)
  VALUES
    ('$USERNAME_SQL', '$PASSWORD_HASH_SQL', '$DISPLAY_NAME_SQL', 1, 1, 0, 0, 0, '$USER_GROUP_SQL', substr(md5(random()::text || clock_timestamp()::text), 1, 4), 0, 0, 0, 0, '$SETTING_JSON_SQL', 'created by create-user-package.sh', $NOW, 0)
  RETURNING id INTO v_user_id;

  INSERT INTO tokens
    (user_id, key, status, name, created_time, accessed_time, expired_time, remain_quota, unlimited_quota, model_limits_enabled, model_limits, allow_ips, used_quota, \"group\", cross_group_retry)
  VALUES
    (v_user_id, '$TOKEN_KEY_SQL', 1, '$TOKEN_NAME_SQL', $NOW, $NOW, -1, $TOKEN_REMAIN, $TOKEN_UNLIMITED, false, '', '', 0, '$TOKEN_GROUP_SQL', false);

  -- Use the portal's canonical plan contract; never upsert plan definitions here.
  SELECT id INTO v_plan_id
  FROM subscription_plans
  WHERE title = '$PLAN_TITLE_SQL'
    AND quota_reset_period = 'daily'
    AND total_amount = $PLAN_QUOTA
    AND enabled = true
  ORDER BY id ASC
  LIMIT 1;

  IF v_plan_id IS NULL THEN
    RAISE EXCEPTION 'subscription plan not found after upsert: $PLAN_TITLE_SQL';
  END IF;

  INSERT INTO user_subscriptions
    (user_id, plan_id, amount_total, amount_used, start_time, end_time, status, source, last_reset_time, next_reset_time, upgrade_group, prev_user_group, created_at, updated_at)
  VALUES
    (v_user_id, v_plan_id, $PLAN_QUOTA, 0, $NOW, $END_TIME, 'active', 'script', $NOW, $NEXT_RESET, '', '', $NOW, $NOW);

  RAISE NOTICE 'created user id=% plan=% quota=%', v_user_id, '$PLAN_TITLE_SQL', $PLAN_QUOTA;
END
\$\$;
COMMIT;
"

echo "Creating user '$USERNAME' with plan '$PLAN_TITLE' in namespace '$NAMESPACE'..."
kubectl -n "$NAMESPACE" exec "$POD" -- sh -lc 'PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' <<<"$SQL"

cat <<MSG

Created successfully.

Username: $USERNAME
Password: $PASSWORD
Plan:     $PLAN_TITLE ($PLAN_SUBTITLE)
API key:  sk-$TOKEN_KEY

Billing preference: $BILLING_PREFERENCE
Token quota mode:   unlimited credential; package quota is enforced by subscription
Reset timezone:     $RESET_TIMEZONE

Lưu lại password/API key ngay bây giờ. Script không ghi secret này ra file.
MSG
