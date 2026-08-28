package dev.hogwai.springlean.model;

import java.math.BigDecimal;

public record CreateTransactionRequest(String accountNumber, BigDecimal amount, String description) {
}
