package dev.hogwai.micronautlean.controller;

import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Get;
import java.util.Map;

@Controller("/actuator/health")
public class HealthAliasController {

    @Get
    public Map<String, String> health() {
        return Map.of("status", "UP");
    }
}
