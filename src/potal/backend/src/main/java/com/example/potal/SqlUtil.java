package com.example.potal;

import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.stream.Collectors;

final class SqlUtil {
    private SqlUtil() {}

    static String normalizeTokenForDb(String token) {
        if (token == null) return "";
        String trimmed = token.trim();
        return trimmed.startsWith("sk-") ? trimmed.substring(3) : trimmed;
    }

    static String uniqueCsv(String csv) {
        if (csv == null || csv.isBlank()) return "";
        Set<String> values = Arrays.stream(csv.split(","))
            .map(String::trim)
            .filter(s -> !s.isBlank())
            .collect(Collectors.toCollection(LinkedHashSet::new));
        return String.join(",", values);
    }
}
