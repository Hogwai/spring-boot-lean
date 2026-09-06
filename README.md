# Spring Boot Lean

An ultra-lean Spring Boot application optimized for fast startup and low memory footprint (kinda).

Five modes:
- JVM+Leyden (AOT compilation)
- Native compilation with GraalVM
- Go (Gin 1.9.1 + pgx)
- Rust (Axum 0.8.8 + sqlx)
- Micronaut (Micronaut 5 + Netty + HikariCP)

## Tech Stack

|           | Java (Spring Boot)             | Micronaut (Netty)       | Go             | Rust             |
|-----------|--------------------------------|-------------------------|----------------|------------------|
| Runtime   | Java 25 (GraalVM 25.0.3+9-LTS) | Java 25                 | Go 1.23        | Rust 1.93.1      |
| Framework | Spring Boot 4.1.0              | Micronaut 5 (5.1.10)    | Gin 1.9.1      | Axum 0.8.8       |
| Server    | Tomcat (virtual threads)       | Netty (port 8080)       | net/http       | Tokio + Axum     |
| DB        | JDBC + HikariCP                | JDBC + HikariCP (20/10) | pgxpool        | sqlx 0.8.6       |
| DB        | PostgreSQL 18                  | PostgreSQL 18           | PostgreSQL 18  | PostgreSQL 18    |
| Image     | spring-lean:jvm / native       | spring-lean:micronaut   | spring-lean:go | spring-lean:rust |

## Architecture

REST CRUD API on financial transactions:

**Java (Spring Boot)**
- `TransactionController`: GET list, GET single, POST, PUT
- `JdbcTransactionRepository`: JdbcTemplate + HikariCP
- `GlobalExceptionHandler`: structured JSON error responses
- Actuator health (`/actuator/health`)

**Micronaut (micronaut/ module)**
- `TransactionController` (Micronaut, Netty on port 8080): GET list, GET single, POST, PUT
- `JdbcTransactionRepository`: JDBC + HikariCP (maximum-pool-size 20, minimum-idle 10)
- `GlobalExceptionHandler` + `HealthAliasController`: structured JSON errors, health (`/health` alias + `/actuator/health`)
- Build: Maven + `micronaut-maven-plugin`, Docker image `spring-lean:micronaut`

**Go (Gin)**
- `transaction.Handler`: Gin HTTP handlers
- `transaction.PostgresStore`: pgxpool
- Health (`/health` + `/actuator/health`)

**Rust (Axum)**
- `transaction::handler`: Axum handlers with extractors
- `transaction::repository::PostgresStore`: sqlx
- Health (`/health` + `/actuator/health`)

## Build & Run

### Requirements
- Docker
- k6
- Java: GraalVM CE + sdkman (JVM/Native/Micronaut modes, Java 25)
- Go 1.23+ (Go mode)
- Rust 1.93.1+ (Rust mode)

### Make Commands

```bash
make help              # show all available targets
```

#### Local Run
```bash
make run-jvm           # Spring Boot on JVM (mvn spring-boot:run)
make run-native        # Spring Boot native binary (GraalVM required)
make run-go            # Go server (go run)
make run-rust          # Rust server (cargo run)
make run-micronaut     # Micronaut server (cd micronaut && mvn mn:run)
```

#### Docker Build
```bash
make build-docker-jvm        # -> spring-lean:jvm
make build-docker-native     # -> spring-lean:native
make build-docker-go         # -> spring-lean:go
make build-docker-rust       # -> spring-lean:rust
make build-docker-micronaut  # -> spring-lean:micronaut
```

#### Benchmarks
```bash
make bench              # all modes (JVM + Native + Go + Rust + Micronaut)
make bench-jvm          # JVM only
make bench-native       # Native only
make bench-go           # Go only
make bench-rust         # Rust only
make bench-micronaut    # Micronaut only
```

Or directly:
```bash
./benchmark/run-benchmarks.sh                 # all (jvm native go rust micronaut)
./benchmark/run-benchmarks.sh jvm             # JVM only
./benchmark/run-benchmarks.sh micronaut       # Micronaut only
./benchmark/run-benchmarks.sh go              # Go only
./benchmark/run-benchmarks.sh rust            # Rust only
./benchmark/run-benchmarks.sh jvm,micronaut   # JVM + Micronaut
./benchmark/run-benchmarks.sh jvm,go          # JVM + Go
./benchmark/run-benchmarks.sh --help          # usage (all = jvm native go rust micronaut)
```

#### Cleanup
```bash
make clean              # remove build artifacts + Docker images
```

## Benchmarks

Full benchmark suite: Docker build, time-to-health measurement, memory endurance under k6 load (200 VUs, 60s). 
All modes are warmed up for 30s before k6.

### Results

All modes are warmed up for 30s.

| Mode                     | Startup time | Time-to-Health | Memory (idle) | Memory (peak) | Memory (retained) | P90    | P95    |
|--------------------------|--------------|----------------|---------------|---------------|-------------------|--------|--------|
| Spring Boot (JVM+Leyden) | 1232ms       | 1539ms         | 185.8MiB      | 208.7MiB      | 177.7MiB (-8)     | 2.69ms | 3.24ms |
| Spring Boot (Native)     | 198ms        | 939ms          | 37.18MiB      | 92.2MiB       | 90.91MiB (+54)    | 2.93ms | 3.50ms |
| Gin (Go)                 | 173ms        | 294ms          | 11.66MiB      | 34.84MiB      | 32.84MiB (+21)    | 2.52ms | 2.92ms |
| Axum (Rust)              | 128ms        | 251ms          | 6.488MiB      | 18.5MiB       | 16.68MiB (+10)    | 2.74ms | 3.22ms |
| Micronaut                | 794ms        | 1220ms         | 188.6MiB      | 248.5MiB      | 227.2MiB (+39)    | 2.42ms | 3.04ms |

Not too bad for a slow and bloated framework, huh ?
