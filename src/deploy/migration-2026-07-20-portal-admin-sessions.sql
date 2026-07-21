-- Portal admin access/refresh token storage.
-- Raw tokens are returned only to the client; the database stores SHA-256 hashes.
CREATE TABLE IF NOT EXISTS portal_admin_tokens (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash CHAR(64) NOT NULL UNIQUE,
    created_at BIGINT NOT NULL,
    expires_at BIGINT NOT NULL,
    revoked_at BIGINT NULL
);
CREATE INDEX IF NOT EXISTS idx_portal_admin_tokens_user_id ON portal_admin_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_portal_admin_tokens_expiry ON portal_admin_tokens(expires_at);

CREATE TABLE IF NOT EXISTS portal_admin_refresh_tokens (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash CHAR(64) NOT NULL UNIQUE,
    created_at BIGINT NOT NULL,
    expires_at BIGINT NOT NULL,
    revoked_at BIGINT NULL
);
CREATE INDEX IF NOT EXISTS idx_portal_admin_refresh_tokens_user_id ON portal_admin_refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_portal_admin_refresh_tokens_expiry ON portal_admin_refresh_tokens(expires_at);
