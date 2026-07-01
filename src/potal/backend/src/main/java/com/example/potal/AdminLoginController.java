package com.example.potal;

import java.security.SecureRandom;
import java.time.Instant;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.bcrypt.BCrypt;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/admin")
public class AdminLoginController {
    private static final SecureRandom RANDOM = new SecureRandom();

    private final JdbcTemplate jdbc;

    public AdminLoginController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @PostMapping("/login")
    @Transactional
    public ResponseEntity<?> login(@RequestBody AdminLoginRequest request) {
        AdminLoginRequest safeRequest = request == null ? new AdminLoginRequest("", "") : request.normalized();
        if (safeRequest.username().isBlank() || safeRequest.password().isBlank()) {
            return ResponseEntity.status(401).body(Map.of("success", false, "message", "Invalid username or password"));
        }

        List<Map<String, Object>> users = jdbc.queryForList("""
            SELECT id, username, display_name, password, role, status
            FROM users
            WHERE (username = ? OR email = ?) AND deleted_at IS NULL
            LIMIT 1
            """, safeRequest.username(), safeRequest.username());
        if (users.isEmpty()) {
            return ResponseEntity.status(401).body(Map.of("success", false, "message", "Invalid username or password"));
        }

        Map<String, Object> user = users.get(0);
        String passwordHash = String.valueOf(user.get("password"));
        if (!BCrypt.checkpw(safeRequest.password(), passwordHash)) {
            return ResponseEntity.status(401).body(Map.of("success", false, "message", "Invalid username or password"));
        }
        int status = ((Number) user.get("status")).intValue();
        int role = ((Number) user.get("role")).intValue();
        if (status != 1 || role < 100) {
            return ResponseEntity.status(403).body(Map.of("success", false, "message", "Admin role required"));
        }

        long userId = ((Number) user.get("id")).longValue();
        String adminToken = createAdminToken(userId);

        return ResponseEntity.ok(Map.of("success", true, "data", Map.of(
            "adminToken", adminToken,
            "tokenMasked", maskKey(adminToken),
            "user", Map.of(
                "id", userId,
                "username", user.get("username"),
                "displayName", user.get("display_name"),
                "role", role
            )
        )));
    }

    private String createAdminToken(long userId) {
        ensurePortalAdminTokenTable();
        long now = Instant.now().getEpochSecond();
        long expiresAt = now + 12L * 60 * 60;
        String adminToken = "pat_" + randomHex(32);
        jdbc.update("""
            INSERT INTO portal_admin_tokens (user_id, token_hash, created_at, expires_at)
            VALUES (?, ?, ?, ?)
            """, userId, AuthService.sha256Hex(adminToken), now, expiresAt);
        return adminToken;
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

    private static String randomHex(int byteCount) {
        byte[] bytes = new byte[byteCount];
        RANDOM.nextBytes(bytes);
        return HexFormat.of().formatHex(bytes);
    }

    private static String maskKey(String key) {
        if (key == null || key.length() <= 12) return "********";
        return key.substring(0, 6) + "********" + key.substring(key.length() - 4);
    }

    public record AdminLoginRequest(String username, String password) {
        AdminLoginRequest normalized() {
            return new AdminLoginRequest(username == null ? "" : username.trim(), password == null ? "" : password);
        }
    }
}
