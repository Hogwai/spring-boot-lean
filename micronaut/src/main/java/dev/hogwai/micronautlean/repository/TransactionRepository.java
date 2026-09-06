package dev.hogwai.micronautlean.repository;

import dev.hogwai.micronautlean.model.Transaction;

import java.util.List;
import java.util.Optional;

public interface TransactionRepository {
    Optional<Transaction> findById(Long id);
    List<Transaction> findByAccountNumber(String accountNumber, int limit);
    Transaction save(Transaction transaction);
}
