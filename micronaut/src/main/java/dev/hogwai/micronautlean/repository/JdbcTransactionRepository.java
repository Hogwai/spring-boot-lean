package dev.hogwai.micronautlean.repository;

import dev.hogwai.micronautlean.model.Transaction;
import jakarta.inject.Singleton;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

@Singleton
public class JdbcTransactionRepository implements TransactionRepository {

    private final DataSource dataSource;

    public JdbcTransactionRepository(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    private Transaction mapRow(ResultSet rs) throws SQLException {
        return new Transaction(
            rs.getLong("id"),
            rs.getString("account_number"),
            rs.getBigDecimal("amount"),
            rs.getString("description"),
            rs.getObject("created_at", OffsetDateTime.class).toInstant()
        );
    }

    @Override
    public Optional<Transaction> findById(Long id) {
        try (Connection c = dataSource.getConnection();
             PreparedStatement ps = c.prepareStatement(
                 "SELECT id, account_number, amount, description, created_at FROM transaction WHERE id = ?")) {
            ps.setLong(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return Optional.of(mapRow(rs));
                }
                return Optional.empty();
            }
        } catch (SQLException e) {
            throw new RuntimeException(e);
        }
    }

    @Override
    public List<Transaction> findByAccountNumber(String accountNumber, int limit) {
        try (Connection c = dataSource.getConnection();
             PreparedStatement ps = c.prepareStatement(
                 "SELECT id, account_number, amount, description, created_at FROM transaction WHERE account_number = ? ORDER BY id LIMIT ?")) {
            ps.setString(1, accountNumber);
            ps.setInt(2, limit);
            try (ResultSet rs = ps.executeQuery()) {
                List<Transaction> list = new ArrayList<>();
                while (rs.next()) {
                    list.add(mapRow(rs));
                }
                return list;
            }
        } catch (SQLException e) {
            throw new RuntimeException(e);
        }
    }

    @Override
    public Transaction save(Transaction transaction) {
        if (transaction.id() == null) {
            try (Connection c = dataSource.getConnection();
                 PreparedStatement ps = c.prepareStatement(
                     "INSERT INTO transaction (account_number, amount, description) VALUES (?, ?, ?) RETURNING id")) {
                ps.setString(1, transaction.accountNumber());
                ps.setBigDecimal(2, transaction.amount());
                ps.setString(3, transaction.description());
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        Long id = rs.getLong(1);
                        return new Transaction(id, transaction.accountNumber(), transaction.amount(), transaction.description(), transaction.createdAt());
                    }
                    throw new RuntimeException("Insert failed, no id returned");
                }
            } catch (SQLException e) {
                throw new RuntimeException(e);
            }
        }
        try (Connection c = dataSource.getConnection();
             PreparedStatement ps = c.prepareStatement(
                 "UPDATE transaction SET account_number = ?, amount = ?, description = ? WHERE id = ?")) {
            ps.setString(1, transaction.accountNumber());
            ps.setBigDecimal(2, transaction.amount());
            ps.setString(3, transaction.description());
            ps.setLong(4, transaction.id());
            ps.executeUpdate();
            return transaction;
        } catch (SQLException e) {
            throw new RuntimeException(e);
        }
    }
}
