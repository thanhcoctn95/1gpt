package com.example.potal;

import java.time.Instant;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthController {
    private final String newApiBaseUrl;
    private final String newApiPublicBaseUrl;

    public HealthController(@Value("${new-api.base-url}") String newApiBaseUrl, @Value("${new-api.public-base-url}") String newApiPublicBaseUrl) {
        this.newApiBaseUrl = newApiBaseUrl;
        this.newApiPublicBaseUrl = newApiPublicBaseUrl;
    }

    @GetMapping("/api/health")
    public Map<String, Object> health() {
        return Map.of(
            "success", true,
            "service", "new-api-potal-backend",
            "newApiBaseUrl", newApiBaseUrl,
            "newApiPublicBaseUrl", newApiPublicBaseUrl,
            "time", Instant.now().toString()
        );
    }

    @GetMapping("/api/config")
    public Map<String, Object> config() {
        String openAiBaseUrl = newApiPublicBaseUrl.endsWith("/v1") ? newApiPublicBaseUrl : newApiPublicBaseUrl + "/v1";
        return Map.of(
            "success", true,
            "data", Map.of(
                "newApiBaseUrl", newApiBaseUrl,
                "newApiPublicBaseUrl", newApiPublicBaseUrl,
                "openAiBaseUrl", openAiBaseUrl
            )
        );
    }

}
