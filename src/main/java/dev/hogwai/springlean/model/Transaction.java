package dev.hogwai.springlean.model;

import java.math.BigDecimal;
import java.time.Instant;

public record Transaction(
    Long id,
    String accountNumber,
    BigDecimal amount,
    String description,
    Instant createdAt
) {}
