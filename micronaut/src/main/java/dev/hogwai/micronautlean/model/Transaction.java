package dev.hogwai.micronautlean.model;

import io.micronaut.serde.annotation.Serdeable;

import java.math.BigDecimal;
import java.time.Instant;

@Serdeable
public record Transaction(
    Long id,
    String accountNumber,
    BigDecimal amount,
    String description,
    Instant createdAt
) {}
