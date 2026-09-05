#!/bin/bash
set -e

echo "=== Spring Boot Lean Benchmark ==="
echo ""

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# ============================================================
# Argument parsing - supports individual modes
# ============================================================
# Usage: ./benchmark/run-benchmarks.sh [all|jvm|native|go|jvm,go|jvm native go ...]
# Default (no arg) = all

# Help flag
if [ "$1" = "--help" ] || [ "$1" = "-h" ] || [ "$1" = "help" ]; then
  echo "Usage: $0 [jvm|native|go|rust|all|jvm,go,...]"
  echo "  (no arg) or all : run jvm native go rust"
  echo "  jvm             : JVM+Leyden only"
  echo "  native          : Native only"
  echo "  go              : Go only"
  echo "  rust            : Rust only"
  echo "  Comma or space separated list, e.g. jvm,go or \"jvm native\""
  exit 0
fi

if [ $# -eq 0 ]; then
  MODES="jvm native go rust"
else
  # Join all args, replace commas with spaces to support both "jvm,go" and "jvm go" / "jvm native go"
  RAW_INPUT="$*"
  RAW_INPUT=$(echo "$RAW_INPUT" | tr ',' ' ')
  # If "all" appears anywhere, expand to full set
  if echo "$RAW_INPUT" | grep -qw "all"; then
    MODES="jvm native go rust"
  else
    MODES=""
    for token in $RAW_INPUT; do
      case "$token" in
        jvm|native|go|rust)
          # avoid duplicates
          if ! echo "$MODES" | grep -qw "$token"; then
            MODES="$MODES $token"
          fi
          ;;
        "")
          ;;
        *)
          echo "Usage: $0 [jvm|native|go|rust|all|jvm,go,...]"
          echo "Unknown mode: $token"
          exit 1
          ;;
      esac
    done
    MODES=$(echo "$MODES" | xargs)
    if [ -z "$MODES" ]; then
      echo "Usage: $0 [jvm|native|go|rust|all|jvm,go,...]"
      exit 1
    fi
  fi
fi

echo "Modes: $MODES"
echo ""

BENCH_START=$(date +%s)

# Load sdkman
source ~/.sdkman/bin/sdkman-init.sh 2>/dev/null || true

# Track PIDs for cleanup
PIDS=()
register_pid() { PIDS+=("$1"); }

cleanup() {
  echo "Cleaning up..."
  for p in "${PIDS[@]}"; do
    kill "$p" 2>/dev/null || true
  done
  for p in "${PIDS[@]}"; do
    timeout 3 tail --pid=$p -f /dev/null 2>/dev/null || true
  done
  docker rm -f springlean-app > /dev/null 2>&1 || true
  docker rm -f springlean-pg > /dev/null 2>&1 || true
  docker network rm springlean-net > /dev/null 2>&1 || true
}
trap cleanup EXIT

# Helpers
wait_for_health() {
  local retries=0
  until curl -s http://localhost:8080/actuator/health > /dev/null 2>&1 || curl -s http://localhost:8080/health > /dev/null 2>&1; do
    sleep 0.2
    retries=$((retries + 1))
    if [ $retries -ge 120 ]; then
      echo "TIMEOUT waiting for /actuator/health or /health"
      return 1
    fi
  done
}

parse_spring_startup() {
  local logs
  logs=$(docker logs springlean-app 2>&1 || true)

  local result
  # Extract milliseconds from "Started Application in Xs" or "initialization completed in X ms"
  result=$(echo "$logs" | grep -oE "(Started Application|initialization completed) in [0-9.]+" 2>/dev/null | grep -oE "[0-9.]+" | head -1)

  if [ -z "$result" ]; then
    echo "N/A"
  else
    echo "${result}ms"
  fi
}

parse_go_startup() {
  local logs
  logs=$(docker logs springlean-app 2>&1 || true)
  local result
  # Go now logs "started in Xms"
  result=$(echo "$logs" | grep -oE "started in [0-9]+ms" | grep -oE "[0-9]+ms" | head -1)
  if [ -n "$result" ]; then
    echo "$result"
    return
  fi
  echo "N/A"
}

parse_rust_startup() {
  local logs
  logs=$(docker logs springlean-app 2>&1 || true)
  local result
  # Rust logs "started in Xms"
  result=$(echo "$logs" | grep -oE "started in [0-9]+ms" | grep -oE "[0-9]+ms" | head -1)
  if [ -n "$result" ]; then
    echo "$result"
    return
  fi
  echo "N/A"
}

measure_memory() {
  # Measure memory via docker stats
  local mem
  mem=$(docker stats --no-stream --format "{{.MemUsage}}" springlean-app 2>/dev/null | cut -d'/' -f1 | xargs 2>/dev/null || true)
  if [ -z "$mem" ] || [ "$mem" = "0" ] || [ "$mem" = "0B" ]; then
    echo "N/A"
  else
    echo "$mem"
  fi
}

measure_memory_mb() {
  local mem
  mem=$(docker stats --no-stream --format "{{.MemUsage}}" springlean-app 2>/dev/null | cut -d'/' -f1 | xargs 2>/dev/null || true)
  if [ -z "$mem" ]; then
    echo "0"
  else
    local num
    num=$(echo "$mem" | grep -oE '[0-9.]+' | head -1)
    if [ -z "$num" ]; then
      echo "0"
    else
      # Convert to MB if needed (docker stats may show MiB or GiB)
      if echo "$mem" | grep -qi "GiB"; then
        # Convert GiB to MB
        echo "$num" | awk '{printf "%.0f", $1 * 1024}'
      else
        echo "$num" | awk '{printf "%.0f", $1}'
      fi
    fi
  fi
}

calc_delta() {
  local before="$1" after="$2"
  local b_num a_num
  b_num=$(echo "$before" | grep -oE '[0-9]+' | head -1)
  a_num=$(echo "$after" | grep -oE '[0-9]+' | head -1)
  if [ -z "$b_num" ] || [ -z "$a_num" ]; then
    echo "N/A"
  else
    echo "$((a_num - b_num)) MB"
  fi
}

run_k6() {
  if command -v k6 &> /dev/null; then
    echo "Running bench 60s 200VUs..."
    k6 run benchmark/load-test.js || echo "k6 failed (continuing)"
  else
    echo "k6 not found, skipping load test"
  fi
}

# ============================================================
# PostgreSQL (once for all modes)
# ============================================================
echo "=== PostgreSQL Setup ==="
docker network create springlean-net 2>/dev/null || true
docker run -d --name springlean-pg --network springlean-net \
  -e POSTGRES_DB=springlean -e POSTGRES_USER=springlean -e POSTGRES_PASSWORD=springlean \
  -p 5432:5432 postgres:18-alpine 2>/dev/null || true
sleep 3
until docker exec springlean-pg pg_isready -U springlean > /dev/null 2>&1; do sleep 1; done
docker exec springlean-pg psql -U springlean -d springlean -c "
CREATE TABLE IF NOT EXISTS transaction (
    id BIGSERIAL PRIMARY KEY, account_number VARCHAR(50) NOT NULL,
    amount DECIMAL(19, 4) NOT NULL, description VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW());
CREATE INDEX IF NOT EXISTS idx_transaction_account ON transaction(account_number, id);
INSERT INTO transaction (account_number, amount, description)
SELECT 'ACC-' || i, (random() * 10000)::decimal(19,4), 'Seed ' || i
FROM generate_series(1, 1000) AS i ON CONFLICT DO NOTHING;
" > /dev/null
echo "PostgreSQL ready (1000 rows)!"
echo ""

# ============================================================
# JVM+Leyden Mode
# ============================================================
if echo "$MODES" | grep -qw "jvm"; then
echo "=== JVM+Leyden Mode ==="
echo "Building Docker image spring-lean:jvm..."
docker build -f Dockerfile.jvm -t spring-lean:jvm .

echo "Running container with memory limit 512m..."
docker rm -f springlean-app 2>/dev/null || true
START=$(date +%s%N)
docker run -d --memory=1g --memory-swap=1g -p 8080:8080 --network springlean-net -e SPRING_DATASOURCE_URL=jdbc:postgresql://springlean-pg:5432/springlean --name springlean-app spring-lean:jvm > /dev/null

if ! wait_for_health; then
  echo "JVM failed to start. Logs:"
  docker logs springlean-app 2>&1 | tail -20 || true
  docker rm -f springlean-app > /dev/null 2>&1 || true
  exit 1
fi

HEALTH_END=$(date +%s%N)
JVM_HEALTH_MS=$(( (HEALTH_END - START) / 1000000 ))
JVM_SPRING=$(parse_spring_startup)
JVM_MEM_BEFORE=$(measure_memory)
echo "Spring startup: ${JVM_SPRING} | Time-to-health: ${JVM_HEALTH_MS}ms | Memory: ${JVM_MEM_BEFORE}"
run_k6 || true
JVM_MEM_AFTER=$(measure_memory)
JVM_MEM_DELTA=$(calc_delta "$JVM_MEM_BEFORE" "$JVM_MEM_AFTER")
echo "Memory before: $JVM_MEM_BEFORE | after: $JVM_MEM_AFTER | delta: $JVM_MEM_DELTA"
JVM_MEM="$JVM_MEM_AFTER"
# Also capture docker stats snapshot
echo "Docker stats: $(docker stats --no-stream --format "{{.MemUsage}} ({{.MemPerc}})" springlean-app 2>/dev/null || echo "N/A")"
docker rm -f springlean-app > /dev/null 2>&1 || true
echo "JVM+Leyden complete."
echo ""
fi

# ============================================================
# Native Mode
# ============================================================
if echo "$MODES" | grep -qw "native"; then
echo "=== Native Mode ==="
NATIVE_BUILD_START=$(date +%s)
echo "Building native binary on host (needs 9GB, ~80s)..."
export JAVA_HOME=$HOME/.sdkman/candidates/java/25.0.3-graal
export PATH=$JAVA_HOME/bin:$PATH
mvn -Pnative native:compile -DskipTests -q
echo "Building Docker image spring-lean:native..."
if ! docker build -f Dockerfile.native -t spring-lean:native . 2>&1; then
  echo "Native build FAILED. Skipping native benchmark."
  echo ""
  NATIVE_BUILD_TIME="FAILED"
else
  NATIVE_BUILD_END=$(date +%s)
  NATIVE_BUILD_TIME="$((NATIVE_BUILD_END - NATIVE_BUILD_START))s"
  echo "Native build time: $NATIVE_BUILD_TIME"
  echo "Running container with memory limit 512m..."
  docker rm -f springlean-app 2>/dev/null || true
  START=$(date +%s%N)
docker run -d --memory=1g --memory-swap=1g -p 8080:8080 --network springlean-net -e SPRING_DATASOURCE_URL=jdbc:postgresql://springlean-pg:5432/springlean --name springlean-app spring-lean:native ./spring-boot-lean -Xmx768m -XX:MaxGCPauseMillis=80 -XX:InitiatingHeapOccupancyPercent=35 > /dev/null
sleep 0.5

if ! wait_for_health; then
    echo "Native failed to start. Logs:"
    docker logs springlean-app 2>&1 | tail -20 || true
    docker rm -f springlean-app > /dev/null 2>&1 || true
  else
    HEALTH_END=$(date +%s%N)
    NATIVE_HEALTH_MS=$(( (HEALTH_END - START) / 1000000 ))
    NATIVE_SPRING=$(parse_spring_startup)
    NATIVE_MEM_BEFORE=$(measure_memory)
    echo "Spring startup: ${NATIVE_SPRING} | Time-to-health: ${NATIVE_HEALTH_MS}ms | Memory: ${NATIVE_MEM_BEFORE}"
    run_k6 || true
    NATIVE_MEM_AFTER=$(measure_memory)
    NATIVE_MEM_DELTA=$(calc_delta "$NATIVE_MEM_BEFORE" "$NATIVE_MEM_AFTER")
    echo "Memory before: $NATIVE_MEM_BEFORE | after: $NATIVE_MEM_AFTER | delta: $NATIVE_MEM_DELTA"
    NATIVE_MEM="$NATIVE_MEM_AFTER"
    echo "Docker stats: $(docker stats --no-stream --format "{{.MemUsage}} ({{.MemPerc}})" springlean-app 2>/dev/null || echo "N/A")"
    docker rm -f springlean-app > /dev/null 2>&1 || true
  fi
  echo "Native complete."
  echo ""
fi
fi

# ============================================================
# Go Mode
# ============================================================
if echo "$MODES" | grep -qw "go"; then
echo "=== Go Mode ==="
echo "Building Docker image spring-lean:go..."
if ! docker build -f go/Dockerfile -t spring-lean:go ./go 2>&1; then
  echo "Go build FAILED. Skipping Go benchmark."
  echo ""
else
  echo "Running container with memory limit 1g..."
  docker rm -f springlean-app 2>/dev/null || true
  START=$(date +%s%N)
  docker run -d --memory=1g --memory-swap=1g -p 8080:8080 --network springlean-net -e DATABASE_URL=postgres://springlean:springlean@springlean-pg:5432/springlean?sslmode=disable -e SPRING_DATASOURCE_URL=jdbc:postgresql://springlean-pg:5432/springlean --name springlean-app spring-lean:go > /dev/null

  if ! wait_for_health; then
    echo "Go failed to start. Logs:"
    docker logs springlean-app 2>&1 | tail -20 || true
    docker rm -f springlean-app > /dev/null 2>&1 || true
  else
    HEALTH_END=$(date +%s%N)
    GO_HEALTH_MS=$(( (HEALTH_END - START) / 1000000 ))
    GO_STARTUP=$(parse_go_startup)
    GO_MEM_BEFORE=$(measure_memory)
    echo "Go startup: ${GO_STARTUP} | Time-to-health: ${GO_HEALTH_MS}ms | Memory: ${GO_MEM_BEFORE}"
    run_k6 || true
    GO_MEM_AFTER=$(measure_memory)
    GO_MEM_DELTA=$(calc_delta "$GO_MEM_BEFORE" "$GO_MEM_AFTER")
    echo "Memory before: $GO_MEM_BEFORE | after: $GO_MEM_AFTER | delta: $GO_MEM_DELTA"
    GO_MEM="$GO_MEM_AFTER"
    echo "Docker stats: $(docker stats --no-stream --format "{{.MemUsage}} ({{.MemPerc}})" springlean-app 2>/dev/null || echo "N/A")"
    docker rm -f springlean-app > /dev/null 2>&1 || true
  fi
  echo "Go complete."
  echo ""
fi
fi

# ============================================================
# Rust Mode
# ============================================================
if echo "$MODES" | grep -qw "rust"; then
echo "=== Rust Mode ==="
echo "Building Docker image spring-lean:rust..."
if ! docker build -f rust/Dockerfile -t spring-lean:rust ./rust 2>&1; then
  echo "Rust build FAILED. Skipping Rust benchmark."
  echo ""
else
  echo "Running container with memory limit 1g..."
  docker rm -f springlean-app 2>/dev/null || true
  START=$(date +%s%N)
  docker run -d --memory=1g --memory-swap=1g -p 8080:8080 --network springlean-net -e DATABASE_URL=postgres://springlean:springlean@springlean-pg:5432/springlean?sslmode=disable --name springlean-app spring-lean:rust > /dev/null

  if ! wait_for_health; then
    echo "Rust failed to start. Logs:"
    docker logs springlean-app 2>&1 | tail -20 || true
    docker rm -f springlean-app > /dev/null 2>&1 || true
  else
    HEALTH_END=$(date +%s%N)
    RUST_HEALTH_MS=$(( (HEALTH_END - START) / 1000000 ))
    RUST_STARTUP=$(parse_rust_startup)
    RUST_MEM_BEFORE=$(measure_memory)
    echo "Rust startup: ${RUST_STARTUP} | Time-to-health: ${RUST_HEALTH_MS}ms | Memory: ${RUST_MEM_BEFORE}"
    run_k6 || true
    RUST_MEM_AFTER=$(measure_memory)
    RUST_MEM_DELTA=$(calc_delta "$RUST_MEM_BEFORE" "$RUST_MEM_AFTER")
    echo "Memory before: $RUST_MEM_BEFORE | after: $RUST_MEM_AFTER | delta: $RUST_MEM_DELTA"
    RUST_MEM="$RUST_MEM_AFTER"
    echo "Docker stats: $(docker stats --no-stream --format "{{.MemUsage}} ({{.MemPerc}})" springlean-app 2>/dev/null || echo "N/A")"
    docker rm -f springlean-app > /dev/null 2>&1 || true
  fi
  echo "Rust complete."
  echo ""
fi
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "=== Summary ==="
printf "%-13s | %-18s | %-14s | %s\n" "Mode" "Spring Startup" "Time-to-Health" "Memory"
printf "%-13s | %-18s | %-14s | %s\n" "---" "---" "---" "---"
printf "%-13s | %-18s | %-14s | %s\n" "JVM+Leyden" "${JVM_SPRING:-N/A}" "${JVM_HEALTH_MS:-N/A}ms" "${JVM_MEM:-N/A}"
printf "%-13s | %-18s | %-14s | %s\n" "Native" "${NATIVE_SPRING:-N/A}" "${NATIVE_HEALTH_MS:-N/A}ms" "${NATIVE_MEM:-N/A}"
printf "%-13s | %-18s | %-14s | %s\n" "Go" "${GO_STARTUP:-N/A}" "${GO_HEALTH_MS:-N/A}ms" "${GO_MEM:-N/A}"
printf "%-13s | %-18s | %-14s | %s\n" "Rust" "${RUST_STARTUP:-N/A}" "${RUST_HEALTH_MS:-N/A}ms" "${RUST_MEM:-N/A}"

# Endurance summary
BENCH_END=$(date +%s)
BENCH_DURATION=$((BENCH_END - BENCH_START))
BENCH_MIN=$((BENCH_DURATION / 60))
BENCH_SEC=$((BENCH_DURATION % 60))
echo ""
echo "=== Endurance Summary ==="
echo "Total benchmark duration: ${BENCH_MIN}m ${BENCH_SEC}s (${BENCH_DURATION}s)"
if [ -n "${NATIVE_BUILD_TIME:-}" ]; then
  echo "Native build time: ${NATIVE_BUILD_TIME}"
fi
echo "Memory endurance (RSS before -> after k6):"
echo "  JVM+Leyden: ${JVM_MEM_BEFORE:-N/A} -> ${JVM_MEM_AFTER:-N/A} (delta: ${JVM_MEM_DELTA:-N/A})"
echo "  Native    : ${NATIVE_MEM_BEFORE:-N/A} -> ${NATIVE_MEM_AFTER:-N/A} (delta: ${NATIVE_MEM_DELTA:-N/A})"
echo "  Go        : ${GO_MEM_BEFORE:-N/A} -> ${GO_MEM_AFTER:-N/A} (delta: ${GO_MEM_DELTA:-N/A})"
echo "  Rust      : ${RUST_MEM_BEFORE:-N/A} -> ${RUST_MEM_AFTER:-N/A} (delta: ${RUST_MEM_DELTA:-N/A})"
echo "Note: PGO endurance isn't tested (just G1 GC for native)."

trap - EXIT
docker rm -f springlean-app > /dev/null 2>&1 || true
docker rm -f springlean-pg > /dev/null 2>&1 || true
docker network rm springlean-net > /dev/null 2>&1 || true
echo ""
echo "=== Benchmark Complete ==="
