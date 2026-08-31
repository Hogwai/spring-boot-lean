# Go Lean — équivalent ultra-lean du Spring Boot

Port Go `net/http` stdlib (Go 1.22+) du projet Spring Boot 4.1 / Java 25.

## Comparatif

| Aspect | Spring Boot (Java) | Go lean |
|---|---|---|
| Runtime | JVM 25, virtual threads | Go 1.23, goroutines |
| HTTP | Spring MVC + Tomcat | `net/http` `ServeMux` avec patterns `GET /path` |
| DB | JdbcTemplate + HikariCP (20/10, timeout 2s) | `pgx/v5` + `pgxpool` (Max 20 Min 10, health 30s) |
| Pool config | `spring.datasource.hikari.*` | `pgxpool.Config` MaxConns/MinConns |
| Config | `application.properties` | Env `PORT`, `DATABASE_URL`, `SPRING_DATASOURCE_URL` (jdbc → postgres) |
| Actuator | `/actuator/health` | `/actuator/health` + `/health` (compat bench) |
| Logging | `logging.pattern.console=%m%n` | `log.Printf` stdout minimal |
| Amount | `BigDecimal(19,4)` | `shopspring/decimal` ↔ `DECIMAL(19,4)` via string |
| JSON | camelCase `accountNumber`, `createdAt` | tags `json:"accountNumber"` identiques |
| Build | Maven `pom.xml` (~65 lignes) | `go.mod` 2 deps (`pgx`, `decimal`) |

## Architecture

```
go/
  go.mod
  cmd/server/main.go     // config, pool, router, graceful shutdown
  internal/config/       // PORT/DATABASE_URL + jdbc conversion
  internal/model/        // Transaction, Requests, ErrorResponse
  internal/repository/   // 3 requêtes SQL identiques au Java
  internal/service/      // business logic miroir
  internal/handler/      // net/http handlers + validation 400/404/500
  Dockerfile             // multi-stage golang:1.23-alpine → alpine
```

## Requêtes SQL (identiques)

```sql
SELECT id, account_number, amount, description, created_at FROM transaction WHERE id = $1
SELECT ... WHERE account_number = $1 ORDER BY id LIMIT $2
INSERT INTO transaction (account_number, amount, description) VALUES ($1,$2,$3) RETURNING id
UPDATE transaction SET account_number=$1, amount=$2, description=$3 WHERE id=$4
```

## API

- `GET /api/transactions?accountNumber=&limit=` → 200 `[]Transaction` (limit default 20 ∈[1,50], accountNumber required blank→400)
- `GET /api/transactions/{id}` → 200 ou 404 `{"error":"Transaction not found: id"}`
- `POST /api/transactions` body `{"accountNumber","amount","description"}` → 201
- `PUT /api/transactions/{id}` → 200 ou 404
- `GET /health` et `GET /actuator/health` → `{"status":"UP"}`

Erreurs toujours `{"error":"..."}` avec 400/404/500 + `Content-Type: application/json`.

## Configuration

```bash
PORT=8080
DATABASE_URL=postgres://springlean:springlean@localhost:5432/springlean?sslmode=disable
# ou
SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/springlean
SPRING_DATASOURCE_USERNAME=springlean
SPRING_DATASOURCE_PASSWORD=springlean
```

`jdbc:postgresql://` est converti automatiquement en `postgres://` + `sslmode=disable`.

## Lancer

```bash
go run ./cmd/server
# ou
go build -o /tmp/golean ./cmd/server && /tmp/golean
```

## Docker

```bash
docker build -f go/Dockerfile -t golean go/
docker run -p 8080:8080 -e DATABASE_URL=postgres://... golean
```

## Bench

Mêmes endpoints que le Java, donc scripts `benchmark/` compatibles (ajoute `/health` en plus).

## Dépendances

- `github.com/jackc/pgx/v5` (pool + driver)
- `github.com/shopspring/decimal` (DECIMAL 19,4 précision)
- Stdlib seul pour HTTP/routing (pas de Gin/Chi)
