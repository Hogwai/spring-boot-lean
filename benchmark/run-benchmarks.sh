#!/bin/bash
set -e

echo "=== Spring Boot Lean Benchmark ==="
echo ""

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

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
  until curl -s http://localhost:8080/actuator/health > /dev/null 2>&1; do
    sleep 0.2
    retries=$((retries + 1))
    if [ $retries -ge 120 ]; then
      echo "TIMEOUT waiting for /actuator/health"
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
# PostgreSQL
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

# ============================================================
# Native Mode
# ============================================================
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

# ============================================================
# Summary
# ============================================================
echo ""
echo "=== Summary ==="
printf "%-13s | %-18s | %-14s | %s\n" "Mode" "Spring Startup" "Time-to-Health" "Memory"
printf "%-13s | %-18s | %-14s | %s\n" "---" "---" "---" "---"
printf "%-13s | %-18s | %-14s | %s\n" "JVM+Leyden" "${JVM_SPRING:-N/A}" "${JVM_HEALTH_MS:-N/A}ms" "${JVM_MEM:-N/A}"
printf "%-13s | %-18s | %-14s | %s\n" "Native" "${NATIVE_SPRING:-N/A}" "${NATIVE_HEALTH_MS:-N/A}ms" "${NATIVE_MEM:-N/A}"

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
echo "Note: PGO endurance isn't tested (just G1 GC for native)."

trap - EXIT
docker rm -f springlean-app > /dev/null 2>&1 || true
docker rm -f springlean-pg > /dev/null 2>&1 || true
docker network rm springlean-net > /dev/null 2>&1 || true
echo ""
echo "=== Benchmark Complete ==="
