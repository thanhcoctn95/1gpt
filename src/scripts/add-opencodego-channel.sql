-- ============================================================
-- Thêm channel opencode-go vào New API (chạy trên cùng DB)
-- Model: deepseek-v4-flash
-- Type: 1 = OpenAI compatible
-- ============================================================

-- THAY API_KEY bên dưới bằng key từ pi config
-- (mở ~/.pi/agent/auth.json → mục "opencode-go" → "key")

INSERT INTO channels (
    type, key, status, name, models, "group", base_url, created_time,
    test_time, response_time, other, balance, balance_updated_time,
    used_quota, auto_ban, priority, weight, channel_info
) VALUES (
    1,
    'API_KEY',
    1,
    'opencode-go',
    'deepseek-v4-flash',
    'default',
    'https://opencode.ai/zen/go/v1',
    EXTRACT(EPOCH FROM NOW())::bigint,
    0, 0, '', 0, 0, 0, 1, 0, 0,
    '{}'::jsonb
)
ON CONFLICT DO NOTHING;
