# Spring Boot Lean

An ultra-lean Spring Boot application optimized for fast startup and low memory footprint (kinda).

Three modes:
- JVM+Leyden (AOT compilation)
- Native compilation with GraalVM
- Go (Gin framework + pgx)

## Tech Stack

|           | Java                           | Go            |
|-----------|--------------------------------|---------------|
| Runtime   | Java 25 (GraalVM 25.0.3+9-LTS) | Go 1.23       |
| Framework | Spring Boot 4.1.0              | Gin 1.9.1     |
| DB        | JDBC + HikariCP                | pgxpool       |
| DB        | PostgreSQL 18                  | PostgreSQL 18 |

## Architecture

REST CRUD API on financial transactions:

Java (Spring Boot)
- `TransactionController`: GET list, GET single, POST, PUT
- `JdbcTransactionRepository`: JdbcTemplate + HikariCP
- `GlobalExceptionHandler`: structured JSON error responses
- Actuator health (`/actuator/health`)

Go (Gin)
- `transaction.Handler`: Gin HTTP handlers (same endpoints)
- `transaction.PostgresStore`: pgxpool (same SQL)
- Health (`/health` + `/actuator/health`)

## Build & Run

### Requirements
- Docker
- k6 
- Java: GraalVM CE + sdkman 
- Go 1.23+ 

### Make Commands

```bash
make help              # show all available targets
```

#### Local Run
```bash
make run-jvm           # Spring Boot on JVM (mvn spring-boot:run)
make run-native        # Spring Boot native binary (GraalVM required)
make run-go            # Go server (go run)
```

#### Docker Build
```bash
make build-docker-jvm    # spring-lean:jvm
make build-docker-native # spring-lean:native
make build-docker-go     # spring-lean:go
```

#### Benchmarks
```bash
make bench              # all modes (JVM + Native + Go)
make bench-jvm          # JVM only
make bench-native       # Native only
make bench-go           # Go only
```

Or directly:
```bash
./benchmark/run-benchmarks.sh           # all
./benchmark/run-benchmarks.sh jvm       # JVM only
./benchmark/run-benchmarks.sh go        # Go only
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

| Mode                     | Startup time | Time-to-Health | Memory (idle) | Δ Memory (under k6) | P90     | P95     |
|--------------------------|--------------|----------------|--------------:|--------------------:|---------|---------|
| Spring Boot (JVM+Leyden) | 353 ms       | 1456 ms        |       207 MiB |      618 MiB (+411) | 3.2 ms  | 4.5 ms  |
| Spring Boot (Native)     | 19 ms        | 803 ms         |      38.7 MiB |      89.7 MiB (+51) | 3.11 ms | 4.45 ms |
| Gin (Go)                 | 7 ms         | 288 ms         |     11.41 MiB |     31.55 MiB (+20) | 3.14 ms | 6.25 ms |

Not too bad for a slow and bloated framework, huh ?