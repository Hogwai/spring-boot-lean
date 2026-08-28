package dev.hogwai.springlean.model;

import java.math.BigDecimal;

public record UpdateTransactionRequest(String accountNumber, BigDecimal amount, String description) {
}
