package com.example.potal;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class PotalApplication {
    public static void main(String[] args) {
        SpringApplication.run(PotalApplication.class, args);
    }
}
