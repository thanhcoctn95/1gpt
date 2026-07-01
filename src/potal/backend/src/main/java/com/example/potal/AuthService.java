package com.example.potal;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class AuthService {
    private final JdbcTemplate jdbc;

    public AuthService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public Map<String, Object> requireUser(String authorization) {
        if (authorization == null || !authorization.toLowerCase().startsWith("bearer ")) throw new UnauthorizedException("Missing Authorization: Bearer <api-key>");
        String token = authorization.substring(7).trim();
        if (token.isBlank() || token.length() > 256) throw new UnauthorizedException("Invalid API key");
        String dbToken = SqlUtil.normalizeTokenForDb(token);
        List<Map<String, Object>> rows = jdbc.queryForList("""
            SELECT t.id AS token_id, t.name AS token_name, t.status AS token_status, t.remain_quota AS token_remain_quota,
                   t.unlimited_quota, t.used_quota AS token_used_quota, t.model_limits_enabled, t.model_limits,
                   t."group" AS token_group, t.expired_time, t.accessed_time,
                   u.id AS user_id, u.username, u.display_name, u.role, u.status AS user_status, u.quota AS user_quota,
                   u.used_quota AS user_used_quota, u.request_count, u."group" AS user_group
            FROM tokens t JOIN users u ON u.id = t.user_id
            WHERE t.key = ? AND t.deleted_at IS NULL LIMIT 1
            """, dbToken);
        if (rows.isEmpty()) throw new UnauthorizedException("Invalid API key");
        Map<String, Object> auth = rows.get(0);
        if (((Number) auth.get("token_status")).intValue() != 1 || ((Number) auth.get("user_status")).intValue() != 1) throw new ForbiddenException("API key or user is disabled");
        return auth;
    }

    public Map<String, Object> requireAdmin(String authorization) {
        String bearer = bearerToken(authorization);
        if (bearer.startsWith("pat_")) return requirePortalAdminToken(bearer);
        Map<String, Object> auth = requireUser(authorization);
        int role = auth.get("role") instanceof Number number ? number.intValue() : 0;
        if (role < 100) throw new ForbiddenException("Admin role required");
        return auth;
    }

    private Map<String, Object> requirePortalAdminToken(String token) {
        ensurePortalAdminTokenTable();
        String tokenHash = sha256Hex(token);
        long now = Instant.now().getEpochSecond();
        List<Map<String, Object>> rows = jdbc.queryForList("""
            SELECT s.user_id, s.expires_at, u.username, u.display_name, u.role, u.status AS user_status
            FROM portal_admin_tokens s
            JOIN users u ON u.id = s.user_id
            WHERE s.token_hash = ? AND s.revoked_at IS NULL AND s.expires_at > ? AND u.deleted_at IS NULL
            LIMIT 1
            """, tokenHash, now);
        if (rows.isEmpty()) throw new UnauthorizedException("Invalid admin token");
        Map<String, Object> auth = rows.get(0);
        int role = auth.get("role") instanceof Number number ? number.intValue() : 0;
        int status = auth.get("user_status") instanceof Number number ? number.intValue() : 0;
        if (status != 1 || role < 100) throw new ForbiddenException("Admin role required");
        return auth;
    }

    private String bearerToken(String authorization) {
        if (authorization == null || !authorization.toLowerCase().startsWith("bearer ")) throw new UnauthorizedException("Missing Authorization: Bearer <token>");
        String token = authorization.substring(7).trim();
        if (token.isBlank() || token.length() > 512) throw new UnauthorizedException("Invalid token");
        return token;
    }

    private void ensurePortalAdminTokenTable() {
        jdbc.execute("""
            CREATE TABLE IF NOT EXISTS portal_admin_tokens (
                id BIGSERIAL PRIMARY KEY,
                user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                token_hash CHAR(64) NOT NULL UNIQUE,
                created_at BIGINT NOT NULL,
                expires_at BIGINT NOT NULL,
                revoked_at BIGINT NULL
            )
            """);
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_portal_admin_tokens_user_id ON portal_admin_tokens(user_id)");
    }

    static String sha256Hex(String value) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 is not available", e);
        }
    }
}
