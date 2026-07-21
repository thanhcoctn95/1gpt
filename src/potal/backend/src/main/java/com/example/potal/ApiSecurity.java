package com.example.potal;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
public class ApiSecurity extends OncePerRequestFilter {
    private static final long WINDOW_MILLIS = 60_000;
    private static final Map<String, Deque<Long>> REQUESTS = new ConcurrentHashMap<>();
    private final boolean trustForwardedFor;

    public ApiSecurity(@Value("${portal.security.trust-forwarded-for:false}") boolean trustForwardedFor) {
        this.trustForwardedFor = trustForwardedFor;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain) throws ServletException, IOException {
        addSecurityHeaders(response);
        if (request.getRequestURI().startsWith("/api/")) {
            String family = routeFamily(request.getRequestURI());
            if (!allow(clientIp(request) + ":" + family, limitFor(family, request.getMethod()))) {
                response.setStatus(429);
                response.setContentType("application/json");
                response.getWriter().write("{\"success\":false,\"message\":\"Too many requests\"}");
                return;
            }
        }
        filterChain.doFilter(request, response);
    }

    private static void addSecurityHeaders(HttpServletResponse response) {
        response.setHeader("X-Content-Type-Options", "nosniff");
        response.setHeader("X-Frame-Options", "DENY");
        response.setHeader("Referrer-Policy", "no-referrer");
        response.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
        response.setHeader("Cache-Control", "no-store");
        response.setHeader("Content-Security-Policy", "default-src 'self'; frame-ancestors 'none'");
    }

    private static int limitFor(String family, String method) {
        if (family.equals("admin-login")) return 10;
        if (family.equals("admin-refresh")) return 30;
        if (family.equals("dashboard-test")) return 20;
        if (family.equals("admin-write") || "PATCH".equalsIgnoreCase(method)) return 30;
        if (family.equals("dashboard")) return 120;
        return 90;
    }

    private static String routeFamily(String uri) {
        if (uri.equals("/api/admin/login")) return "admin-login";
        if (uri.equals("/api/admin/refresh")) return "admin-refresh";
        if (uri.startsWith("/api/dashboard/test")) return "dashboard-test";
        if (uri.startsWith("/api/dashboard/")) return "dashboard";
        if (uri.startsWith("/api/admin/")) return "admin-write";
        return "api";
    }

    private String clientIp(HttpServletRequest request) {
        if (trustForwardedFor) {
            String forwarded = request.getHeader("X-Forwarded-For");
            if (forwarded != null && !forwarded.isBlank()) return forwarded.split(",")[0].trim();
        }
        return request.getRemoteAddr();
    }

    private static boolean allow(String key, int limit) {
        long now = Instant.now().toEpochMilli();
        Deque<Long> deque = REQUESTS.computeIfAbsent(key, ignored -> new ArrayDeque<>());
        synchronized (deque) {
            while (!deque.isEmpty() && now - deque.peekFirst() > WINDOW_MILLIS) deque.removeFirst();
            if (deque.size() >= limit) return false;
            deque.addLast(now);
            return true;
        }
    }
}
