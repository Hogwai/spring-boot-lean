# Spring Boot Lean

An ultra-lean Spring Boot application optimized for fast startup and low memory footprint.

Two modes:
- AOT compilation (Project Leyden) 
- Native compilation with GraalVM.

## Tech Stack

- Java 25: GraalVM (25.0.3+9-LTS)
- Spring Boot 4.1.0
- PostgreSQL 18

## Architecture

REST CRUD API on financial transactions:

- `TransactionController`: endpoints: GET list, GET single, POST, PUT
- `JdbcTransactionRepository`: direct JDBC access to PostgreSQL
- `GlobalExceptionHandler`: structured JSON error responses
- Actuator for health monitoring (`/actuator/health`)

## Build & Run

### Requirements
- Docker
- k6
- GraalVM CE
- sdkman

### Local (JVM or Native)

```bash
# Compile
mvn package -DskipTests

# Run JVM
mvn spring-boot:run

# Run Native (GraalVM JDK required)
export JAVA_HOME=$HOME/.sdkman/candidates/java/25.0.3-graal
mvn -Pnative native:compile -DskipTests
./target/spring-boot-lean
```

### Docker

```bash
make bench            # full benchmark suite (JVM + Native)
docker run -p 8080:8080 --network springlean-net \
  -e SPRING_DATASOURCE_URL=jdbc:postgresql://springlean-pg:5432/springlean \
  spring-lean:jvm     # or spring-lean:native
```

## Benchmarks

Full benchmark suite: Docker build, native compilation, time-to-health measurement, and memory endurance under load.

### Summary Results

| Mode       | Spring Startup | Time-to-Health | Memory (idle) | Δ Memory (under k6) | P90    | P95    |
|------------|----------------|----------------|--------------:|--------------------:|--------|--------|
| JVM+Leyden | 353 ms         | 1456 ms        |       207 MiB |      618 MiB (+411) | 3.2ms  | 4.5ms  |
| Native     | 19 ms          | 803 ms         |      38.7 MiB |      89.7 MiB (+51) | 3.11ms | 4.45ms |

## Run Benchmarks

```bash
make bench
./benchmark/run-benchmarks.sh
```
