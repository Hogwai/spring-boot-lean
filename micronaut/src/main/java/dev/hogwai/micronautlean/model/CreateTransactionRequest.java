package dev.hogwai.micronautlean.model;

import io.micronaut.serde.annotation.Serdeable;

import java.math.BigDecimal;

@Serdeable
public record CreateTransactionRequest(String accountNumber, BigDecimal amount, String description) {}
