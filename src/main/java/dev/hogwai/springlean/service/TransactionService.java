package dev.hogwai.springlean.service;

import dev.hogwai.springlean.error.TransactionNotFoundException;
import dev.hogwai.springlean.model.Transaction;
import dev.hogwai.springlean.repository.TransactionRepository;

import java.math.BigDecimal;
import java.util.List;

public class TransactionService {

    private final TransactionRepository repository;

    public TransactionService(TransactionRepository repository) {
        this.repository = repository;
    }

    public List<Transaction> findByAccount(String accountNumber, int limit) {
        return repository.findByAccountNumber(accountNumber, limit);
    }

    public Transaction findById(Long id) {
        return repository.findById(id)
            .orElseThrow(() -> new TransactionNotFoundException(id));
    }

    public Transaction create(String accountNumber, BigDecimal amount, String description) {
        Transaction transaction = new Transaction(null, accountNumber, amount, description, null);
        return repository.save(transaction);
    }

    public Transaction update(Long id, String accountNumber, BigDecimal amount, String description) {
        Transaction existing = findById(id);
        Transaction updated = new Transaction(id, accountNumber, amount, description, existing.createdAt());
        return repository.save(updated);
    }
}
