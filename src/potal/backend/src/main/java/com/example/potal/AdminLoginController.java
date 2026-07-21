package com.example.potal;

import jakarta.servlet.http.HttpServletResponse;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.security.crypto.bcrypt.BCrypt;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.CookieValue;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/admin")
public class AdminLoginController {
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final String REFRESH_COOKIE = "potal_admin_refresh";
    private static final long ACCESS_TOKEN_SECONDS = 12L * 60 * 60;
    private static final long REFRESH_TOKEN_SECONDS = 30L * 24 * 60 * 60;
    private final JdbcTemplate jdbc;

    public AdminLoginController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    @PostMapping("/login")
    @Transactional
    public ResponseEntity<?> login(@RequestBody AdminLoginRequest request, HttpServletResponse response) {
        AdminLoginRequest safe = request == null ? new AdminLoginRequest("", "") : request.normalized();
        if (safe.username().isBlank() || safe.password().isBlank()) return unauthorized("Invalid username or password");
        List<Map<String, Object>> users = jdbc.queryForList("""
            SELECT id, username, display_name, password, role, status FROM users
            WHERE (username = ? OR email = ?) AND deleted_at IS NULL LIMIT 1
            """, safe.username(), safe.username());
        if (users.isEmpty() || !BCrypt.checkpw(safe.password(), String.valueOf(users.get(0).get("password")))) return unauthorized("Invalid username or password");
        Map<String, Object> user = users.get(0);
        if (!isActiveAdmin(user)) return ResponseEntity.status(403).body(Map.of("success", false, "message", "Admin role required"));
        return sessionResponse(user, response);
    }

    @PostMapping("/refresh")
    @Transactional
    public ResponseEntity<?> refresh(@CookieValue(value = REFRESH_COOKIE, required = false) String token, HttpServletResponse response) {
        if (token == null || token.isBlank() || token.length() > 512) return unauthorizedAndClear(response, "Invalid refresh token");
        long now = Instant.now().getEpochSecond();
        List<Map<String, Object>> rows = jdbc.queryForList("""
            SELECT r.id AS refresh_id, r.user_id AS id, u.username, u.display_name, u.role, u.status
            FROM portal_admin_refresh_tokens r JOIN users u ON u.id = r.user_id
            WHERE r.token_hash = ? AND r.revoked_at IS NULL AND r.expires_at > ? AND u.deleted_at IS NULL LIMIT 1
            """, AuthService.sha256Hex(token), now);
        if (rows.isEmpty() || !isActiveAdmin(rows.get(0))) return unauthorizedAndClear(response, "Invalid refresh token");
        if (jdbc.update("UPDATE portal_admin_refresh_tokens SET revoked_at=? WHERE id=? AND revoked_at IS NULL", now, rows.get(0).get("refresh_id")) != 1) return unauthorizedAndClear(response, "Invalid refresh token");
        return sessionResponse(rows.get(0), response);
    }

    @PostMapping("/logout")
    @Transactional
    public ResponseEntity<?> logout(@CookieValue(value = REFRESH_COOKIE, required = false) String token, HttpServletResponse response) {
        if (token != null && !token.isBlank()) {
                jdbc.update("UPDATE portal_admin_refresh_tokens SET revoked_at=? WHERE token_hash=? AND revoked_at IS NULL", Instant.now().getEpochSecond(), AuthService.sha256Hex(token));
        }
        clearRefreshCookie(response);
        return ResponseEntity.ok(Map.of("success", true, "data", Map.of("loggedOut", true)));
    }

    @Scheduled(cron = "0 17 * * * *")
    public void cleanupExpiredTokens() {
        long cutoff = Instant.now().getEpochSecond() - 7L * 24 * 60 * 60;
        jdbc.update("DELETE FROM portal_admin_tokens WHERE expires_at < ? OR revoked_at < ?", cutoff, cutoff);
        jdbc.update("DELETE FROM portal_admin_refresh_tokens WHERE expires_at < ? OR revoked_at < ?", cutoff, cutoff);
    }

    private ResponseEntity<?> sessionResponse(Map<String, Object> user, HttpServletResponse response) {
        long userId = ((Number) user.get("id")).longValue();
        long now = Instant.now().getEpochSecond();
        String access = "pat_" + randomHex(32);
        String refresh = "par_" + randomHex(48);
        jdbc.update("INSERT INTO portal_admin_tokens (user_id, token_hash, created_at, expires_at) VALUES (?, ?, ?, ?)", userId, AuthService.sha256Hex(access), now, now + ACCESS_TOKEN_SECONDS);
        jdbc.update("INSERT INTO portal_admin_refresh_tokens (user_id, token_hash, created_at, expires_at) VALUES (?, ?, ?, ?)", userId, AuthService.sha256Hex(refresh), now, now + REFRESH_TOKEN_SECONDS);
        response.addHeader("Set-Cookie", refreshCookie(refresh, REFRESH_TOKEN_SECONDS));
        return ResponseEntity.ok(Map.of("success", true, "data", Map.of("adminToken", access, "tokenMasked", maskKey(access),
            "user", Map.of("id", userId, "username", user.get("username"), "displayName", user.get("display_name") == null ? "" : user.get("display_name"), "role", user.get("role")))));
    }

    private static boolean isActiveAdmin(Map<String, Object> user) { return ((Number) user.get("status")).intValue() == 1 && ((Number) user.get("role")).intValue() >= 100; }
    private static ResponseEntity<?> unauthorized(String message) { return ResponseEntity.status(401).body(Map.of("success", false, "message", message)); }
    private static ResponseEntity<?> unauthorizedAndClear(HttpServletResponse response, String message) { clearRefreshCookie(response); return unauthorized(message); }
    private static String refreshCookie(String token, long maxAge) { return REFRESH_COOKIE + "=" + token + "; Max-Age=" + maxAge + "; Path=/api/admin; HttpOnly; Secure; SameSite=Strict"; }
    private static void clearRefreshCookie(HttpServletResponse response) { response.addHeader("Set-Cookie", refreshCookie("", 0)); }
    private static String randomHex(int byteCount) { byte[] bytes = new byte[byteCount]; RANDOM.nextBytes(bytes); return HexFormat.of().formatHex(bytes); }
  private static String maskKey(String key) { return key.length() <= 12 ? "********" : key.substring(0, 6) + "********" + key.substring(key.length() - 4); }
    public record AdminLoginRequest(String username, String password) { AdminLoginRequest normalized() { return new AdminLoginRequest(username == null ? "" : username.trim(), password == null ? "" : password); } }
}
