package dev.hogwai.springlean.repository;

import dev.hogwai.springlean.model.Transaction;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;

public class JdbcTransactionRepository implements TransactionRepository {

    private final JdbcTemplate jdbc;

    private final RowMapper<Transaction> rowMapper = (rs, _) -> new Transaction(
        rs.getLong("id"),
        rs.getString("account_number"),
        rs.getBigDecimal("amount"),
        rs.getString("description"),
        rs.getObject("created_at", OffsetDateTime.class).toInstant()
    );

    public JdbcTransactionRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public Optional<Transaction> findById(Long id) {
        List<Transaction> results = jdbc.query(
            "SELECT id, account_number, amount, description, created_at FROM transaction WHERE id = ?",
            rowMapper, id
        );
        return results.stream().findFirst();
    }

    @Override
    public List<Transaction> findByAccountNumber(String accountNumber, int limit) {
        return jdbc.query(
            "SELECT id, account_number, amount, description, created_at FROM transaction WHERE account_number = ? ORDER BY id LIMIT ?",
            rowMapper, accountNumber, limit
        );
    }

    @Override
    public Transaction save(Transaction transaction) {
        if (transaction.id() == null) {
            Long id = jdbc.queryForObject(
                "INSERT INTO transaction (account_number, amount, description) VALUES (?, ?, ?) RETURNING id",
                Long.class,
                transaction.accountNumber(), transaction.amount(), transaction.description()
            );
            return new Transaction(id, transaction.accountNumber(), transaction.amount(), transaction.description(), transaction.createdAt());
        }
        jdbc.update(
            "UPDATE transaction SET account_number = ?, amount = ?, description = ? WHERE id = ?",
            transaction.accountNumber(), transaction.amount(), transaction.description(), transaction.id()
        );
        return transaction;
    }
}
