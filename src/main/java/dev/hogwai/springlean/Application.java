package dev.hogwai.springlean;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.ApplicationListener;
import org.springframework.context.annotation.Bean;

@SpringBootApplication
public class Application {

    static long startNanos;

    static void main(String[] args) {
        startNanos = System.nanoTime();
        SpringApplication.run(Application.class, args);
    }

    @Bean
    ApplicationListener<ApplicationReadyEvent> startupLogger() {
        return _ -> {
            long ms = (System.nanoTime() - startNanos) / 1_000_000;
            System.out.println("Total startup in " + ms + "ms (launch to ready)");
        };
    }
}
