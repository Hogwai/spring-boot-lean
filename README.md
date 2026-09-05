# Spring Boot Lean

An ultra-lean Spring Boot application optimized for fast startup and low memory footprint (kinda).

Four modes:
- JVM+Leyden (AOT compilation)
- Native compilation with GraalVM
- Go (Gin 1.9.1 + pgx)
- Rust (Axum 0.8.8 + sqlx)

## Tech Stack

|           | Java                           | Go            | Rust          |
|-----------|--------------------------------|---------------|---------------|
| Runtime   | Java 25 (GraalVM 25.0.3+9-LTS) | Go 1.23       | Rust 1.93.1   |
| Framework | Spring Boot 4.1.0              | Gin 1.9.1     | Axum 0.8.8    |
| DB        | JDBC + HikariCP                | pgxpool       | sqlx 0.8.6    |
| DB        | PostgreSQL 18                  | PostgreSQL 18 | PostgreSQL 18 |

## Architecture

REST CRUD API on financial transactions:

**Java (Spring Boot)**
- `TransactionController`: GET list, GET single, POST, PUT
- `JdbcTransactionRepository`: JdbcTemplate + HikariCP
- `GlobalExceptionHandler`: structured JSON error responses
- Actuator health (`/actuator/health`)

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
- Java: GraalVM CE + sdkman (JVM/Native modes)
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
```

#### Docker Build
```bash
make build-docker-jvm    # -> spring-lean:jvm
make build-docker-native # -> spring-lean:native
make build-docker-go     # -> spring-lean:go
make build-docker-rust   # -> spring-lean:rust
```

#### Benchmarks
```bash
make bench              # all modes (JVM + Native + Go + Rust)
make bench-jvm          # JVM only
make bench-native       # Native only
make bench-go           # Go only
make bench-rust         # Rust only
```

Or directly:
```bash
./benchmark/run-benchmarks.sh           # all
./benchmark/run-benchmarks.sh jvm       # JVM only
./benchmark/run-benchmarks.sh go        # Go only
./benchmark/run-benchmarks.sh rust      # Rust only
./benchmark/run-benchmarks.sh jvm,go    # JVM + Go
./benchmark/run-benchmarks.sh --help    # usage
```

#### Cleanup
```bash
make clean              # remove build artifacts + Docker images
```

## Benchmarks

Full benchmark suite: Docker build, time-to-health measurement, memory endurance under k6 load (200 VUs, 60s).

### Results

All modes are warmed up for 30s.

| Mode                     | Startup time | Time-to-Health | Memory (idle) | Δ Memory (under k6) | P90    | P95    |
|--------------------------|--------------|----------------|---------------|---------------------|--------|--------|
| Spring Boot (JVM+Leyden) | 368ms        | 1468ms         | 236.4MiB      | 627.2MiB (+391)     | 2.70ms | 3.13ms |
| Spring Boot (Native)     | 19ms         | 837ms          | 37.33MiB      | 91.62MiB (+54)      | 2.78ms | 3.27ms |
| Gin (Go)                 | 8ms          | 262ms          | 23.09MiB      | 41.3MiB (+18)       | 2.59ms | 3.03ms |
| Axum (Rust)              | 0ms          | 242ms          | 6.254MiB      | 15.6MiB (+9)        | 2.80ms | 3.23ms |

Not too bad for a slow and bloated framework, huh ?