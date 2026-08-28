package dev.hogwai.springlean.config;

import dev.hogwai.springlean.repository.JdbcTransactionRepository;
import dev.hogwai.springlean.repository.TransactionRepository;
import dev.hogwai.springlean.service.TransactionService;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;

@Configuration(proxyBeanMethods = false)
public class AppConfig {

    @Bean
    TransactionService transactionService(TransactionRepository repository) {
        return new TransactionService(repository);
    }

    @Bean
    TransactionRepository transactionRepository(JdbcTemplate jdbc) {
        return new JdbcTransactionRepository(jdbc);
    }
}
