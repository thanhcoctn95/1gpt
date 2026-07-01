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
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
public class ApiSecurity extends OncePerRequestFilter {
    private static final long WINDOW_MILLIS = 60_000;
    private static final Map<String, Deque<Long>> REQUESTS = new ConcurrentHashMap<>();

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain) throws ServletException, IOException {
        addSecurityHeaders(response);
        if (request.getRequestURI().startsWith("/api/")) {
            int limit = limitFor(request.getRequestURI(), request.getMethod());
            String key = clientIp(request) + ":" + routeFamily(request.getRequestURI());
            if (!allow(key, limit)) {
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

    private static int limitFor(String uri, String method) {
        if (uri.equals("/api/dashboard/test")) return 20;
        if (uri.contains("/model-limits") || "PATCH".equalsIgnoreCase(method)) return 30;
        if (uri.startsWith("/api/dashboard/")) return 120;
        return 90;
    }

    private static String routeFamily(String uri) {
        if (uri.startsWith("/api/dashboard/test")) return "dashboard-test";
        if (uri.startsWith("/api/dashboard/")) return "dashboard";
        if (uri.startsWith("/api/tokens/") || uri.startsWith("/api/users/") || uri.startsWith("/api/models/available")) return "admin";
        return "api";
    }

    private static String clientIp(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) return forwarded.split(",")[0].trim();
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
