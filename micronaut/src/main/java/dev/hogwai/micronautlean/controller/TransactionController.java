package dev.hogwai.micronautlean.controller;

import dev.hogwai.micronautlean.model.CreateTransactionRequest;
import dev.hogwai.micronautlean.model.Transaction;
import dev.hogwai.micronautlean.model.UpdateTransactionRequest;
import dev.hogwai.micronautlean.service.TransactionService;
import io.micronaut.http.HttpResponse;
import io.micronaut.http.annotation.Body;
import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Get;
import io.micronaut.http.annotation.PathVariable;
import io.micronaut.http.annotation.Post;
import io.micronaut.http.annotation.Put;
import io.micronaut.http.annotation.QueryValue;

import java.util.List;

@Controller("/api/transactions")
public class TransactionController {

    private final TransactionService service;

    public TransactionController(TransactionService service) {
        this.service = service;
    }

    @Get
    public List<Transaction> findByAccount(
            @QueryValue(value = "accountNumber", defaultValue = "") String accountNumber,
            @QueryValue(value = "limit", defaultValue = "20") int limit) {
        if (accountNumber == null || accountNumber.isBlank()) {
            throw new IllegalArgumentException("accountNumber is required");
        }
        if (limit < 1 || limit > 50) {
            throw new IllegalArgumentException("limit must be between 1 and 50");
        }
        return service.findByAccount(accountNumber, limit);
    }

    @Get("/{id}")
    public Transaction findById(@PathVariable Long id) {
        return service.findById(id);
    }

    @Post
    public HttpResponse<Transaction> create(@Body CreateTransactionRequest request) {
        Transaction created = service.create(request.accountNumber(), request.amount(), request.description());
        return HttpResponse.created(created);
    }

    @Put("/{id}")
    public Transaction update(@PathVariable Long id, @Body UpdateTransactionRequest request) {
        return service.update(id, request.accountNumber(), request.amount(), request.description());
    }
}
