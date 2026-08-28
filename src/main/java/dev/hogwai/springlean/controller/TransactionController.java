package dev.hogwai.springlean.controller;

import dev.hogwai.springlean.model.CreateTransactionRequest;
import dev.hogwai.springlean.model.Transaction;
import dev.hogwai.springlean.model.UpdateTransactionRequest;
import dev.hogwai.springlean.service.TransactionService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;

@RestController
@RequestMapping("/api/transactions")
public class TransactionController {

    private final TransactionService service;

    public TransactionController(TransactionService service) {
        this.service = service;
    }

    @GetMapping
    List<Transaction> findByAccount(@RequestParam String accountNumber, @RequestParam(defaultValue = "20") int limit) {
        if (accountNumber == null || accountNumber.isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "accountNumber is required");
        }
        if (limit < 1 || limit > 50) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "limit must be between 1 and 50");
        }
        return service.findByAccount(accountNumber, limit);
    }

    @GetMapping("/{id}")
    Transaction findById(@PathVariable Long id) {
        return service.findById(id);
    }

    @PostMapping
    ResponseEntity<Transaction> create(@RequestBody CreateTransactionRequest request) {
        Transaction created = service.create(request.accountNumber(), request.amount(), request.description());
        return ResponseEntity.status(HttpStatus.CREATED).body(created);
    }

    @PutMapping("/{id}")
    Transaction update(@PathVariable Long id, @RequestBody UpdateTransactionRequest request) {
        return service.update(id, request.accountNumber(), request.amount(), request.description());
    }
}

