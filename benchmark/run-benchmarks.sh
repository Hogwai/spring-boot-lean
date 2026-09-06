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
  echo "Usage: $0 [jvm|native|go|rust|micronaut|all|jvm,go,...]"
  echo "  (no arg) or all : run jvm native go rust micronaut"
  echo "  jvm             : JVM+Leyden only"
  echo "  native          : Native only"
  echo "  go              : Go only"
  echo "  rust            : Rust only"
  echo "  micronaut       : Micronaut only"
  echo "  Comma or space separated list, e.g. jvm,go or \"jvm native\""
  exit 0
fi

if [ $# -eq 0 ]; then
  MODES="jvm native go rust micronaut"
else
  # Join all args, replace commas with spaces to support both "jvm,go" and "jvm go" / "jvm native go"
  RAW_INPUT="$*"
  RAW_INPUT=$(echo "$RAW_INPUT" | tr ',' ' ')
  # If "all" appears anywhere, expand to full set
  if echo "$RAW_INPUT" | grep -qw "all"; then
    MODES="jvm native go rust micronaut"
  else
    MODES=""
    for token in $RAW_INPUT; do
      case "$token" in
        jvm|native|go|rust|micronaut)
          # avoid duplicates
          if ! echo "$MODES" | grep -qw "$token"; then
            MODES="$MODES $token"
          fi
          ;;
        "")
          ;;
        *)
          echo "Usage: $0 [jvm|native|go|rust|micronaut|all|jvm,go,...]"
          echo "Unknown mode: $token"
          exit 1
          ;;
      esac
    done
    MODES=$(echo "$MODES" | xargs)
    if [ -z "$MODES" ]; then
      echo "Usage: $0 [jvm|native|go|rust|micronaut|all|jvm,go,...]"
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

warmup() {
  echo "=== Warmup (30s) ==="
  local end=$(( $(date +%s) + 30 ))
  local i=0
  while [ "$(date +%s)" -lt "$end" ]; do
    case $((i % 2)) in
      0) curl -s -o /dev/null "http://localhost:8080/api/transactions?accountNumber=ACC-1&limit=20" || true ;;
      1) curl -s -o /dev/null "http://localhost:8080/api/transactions/1" || true ;;
    esac
    i=$((i + 1))
    sleep 0.1 || true
  done || true
}

parse_spring_startup() {
  local logs
  logs=$(docker logs springlean-app 2>&1 || true)

  local result
  result=$(echo "$logs" | grep -oE "Total startup in [0-9]+ms" | grep -oE "[0-9]+ms" | head -1)
  if [ -n "$result" ]; then
    echo "$result"
    return
  fi
  # Fallback for old format
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

parse_micronaut_startup() {
  local logs
  logs=$(docker logs springlean-app 2>&1 || true)
  local result
  # Micronaut logs "Startup completed in Xms"
  result=$(echo "$logs" | grep -oE "Startup completed in [0-9]+ms" | grep -oE "[0-9]+ms" | head -1)
  if [ -n "$result" ]; then
    echo "$result"
    return
  fi
  echo "N/A"
}

container_startup_ms() {
  local container="$1" || true
  local pattern="$2" || true
  local started=""
  local ready_line=""
  local ready_ts=""
  local started_ms=""
  local ready_ms=""
  local diff=""
  local logs=""
  local fallback=""
  started=$(docker inspect -f '{{.State.StartedAt}}' "$container" 2>&1 || true)
  if [ -z "$started" ] || echo "$started" | grep -q "No such" 2>/dev/null; then
    logs=$(docker logs "$container" 2>&1 || true)
    fallback=$(echo "$logs" | grep -oE "$pattern" | grep -oE "[0-9]+ms" | head -1 || true)
    if [ -n "$fallback" ]; then
      echo "$fallback" || true
      return 0
    fi
    echo "n/a" || true
    return 0
  fi
  ready_line=$(docker logs --timestamps "$container" 2>&1 | grep -E "$pattern" | head -1 || true)
  if [ -z "$ready_line" ]; then
    logs=$(docker logs "$container" 2>&1 || true)
    fallback=$(echo "$logs" | grep -oE "$pattern" | grep -oE "[0-9]+ms" | head -1 || true)
    if [ -n "$fallback" ]; then
      echo "$fallback" || true
      return 0
    fi
    echo "n/a" || true
    return 0
  fi
  ready_ts=$(echo "$ready_line" | awk '{print $1}' || true)
  if [ -z "$ready_ts" ]; then
    logs=$(docker logs "$container" 2>&1 || true)
    fallback=$(echo "$logs" | grep -oE "$pattern" | grep -oE "[0-9]+ms" | head -1 || true)
    if [ -n "$fallback" ]; then echo "$fallback" || true; return 0; fi
    echo "n/a" || true; return 0
  fi
  started_ms=$(date -u -d "$started" +%s%3N 2>&1 || true)
  ready_ms=$(date -u -d "$ready_ts" +%s%3N 2>&1 || true)
  if [ -z "$started_ms" ] || [ -z "$ready_ms" ] || ! echo "$started_ms" | grep -qE '^[0-9]+$' 2>/dev/null || ! echo "$ready_ms" | grep -qE '^[0-9]+$' 2>/dev/null; then
    logs=$(docker logs "$container" 2>&1 || true)
    fallback=$(echo "$logs" | grep -oE "$pattern" | grep -oE "[0-9]+ms" | head -1 || true)
    if [ -n "$fallback" ]; then echo "$fallback" || true; return 0; fi
    echo "n/a" || true; return 0
  fi
  diff=$((ready_ms - started_ms)) || true
  if [ "$diff" -lt 0 ]; then diff=0; fi || true
  echo "${diff}ms" || true
  return 0
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

to_mib() {
  local input="$1" || true
  if [ -z "$input" ] || echo "$input" | grep -qiE "^n/a$" 2>/dev/null; then
    echo "n/a" || true
    return 0
  fi
  local num
  num=$(echo "$input" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1 || true)
  if [ -z "$num" ]; then
    echo "n/a" || true
    return 0
  fi
  if echo "$input" | grep -qi "GiB" 2>/dev/null; then
    awk -v n="$num" 'BEGIN{printf "%.1f", n*1024}' 2>&1 || echo "n/a" || true
  elif echo "$input" | grep -qi "KiB" 2>/dev/null; then
    awk -v n="$num" 'BEGIN{printf "%.1f", n/1024}' 2>&1 || echo "n/a" || true
  elif echo "$input" | grep -qi "MiB" 2>/dev/null; then
    awk -v n="$num" 'BEGIN{printf "%.1f", n}' 2>&1 || echo "n/a" || true
  elif echo "$input" | grep -qiE "[0-9]B" 2>/dev/null; then
    if echo "$input" | grep -qiE "MiB|GiB|KiB" 2>/dev/null; then
      awk -v n="$num" 'BEGIN{printf "%.1f", n}' 2>&1 || echo "n/a" || true
    else
      awk -v n="$num" 'BEGIN{printf "%.1f", n/1024/1024}' 2>&1 || echo "n/a" || true
    fi
  else
    awk -v n="$num" 'BEGIN{printf "%.1f", n}' 2>&1 || echo "n/a" || true
  fi
  return 0
}

measure_memory_mb() {
  local mem
  mem=$(docker stats --no-stream --format "{{.MemUsage}}" springlean-app 2>/dev/null | cut -d'/' -f1 | xargs 2>/dev/null || true)
  if [ -z "$mem" ]; then
    echo "0" || true
    return 0
  fi
  local mib
  mib=$(to_mib "$mem" 2>&1 || true)
  if [ "$mib" = "n/a" ] || [ -z "$mib" ]; then
    echo "0" || true
    return 0
  fi
  printf "%.0f" "$mib" 2>&1 || echo "0" || true
}

sample_peak_mem() {
  local outfile="$1" || true
  local peak="0" || true
  local mem=""
  local mib=""
  local is_greater=""
  # peak covers k6 only (not warmup)
  echo "0.0MiB" > "$outfile" 2>/dev/null || true
  while true; do
    mem=$(docker stats --no-stream --format "{{.MemUsage}}" springlean-app 2>/dev/null | cut -d'/' -f1 | xargs 2>/dev/null || true)
    if [ -n "$mem" ] && [ "$mem" != "0" ] && [ "$mem" != "0B" ] && [ "$mem" != "n/a" ] && [ "$mem" != "N/A" ]; then
      mib=$(to_mib "$mem" 2>&1 || true)
      if [ -n "$mib" ] && [ "$mib" != "n/a" ] && echo "$mib" | grep -qE '^[0-9]+(\.[0-9]+)?$' 2>/dev/null; then
        is_greater=$(awk -v a="$mib" -v b="$peak" 'BEGIN{print (a>b)?1:0}' 2>&1 || true)
        if [ "$is_greater" = "1" ]; then
          peak="$mib" || true
          printf "%.1fMiB" "$peak" > "$outfile" 2>/dev/null || true
        fi
      fi
    fi
    sleep 2 2>&1 || true
  done || true
}

calc_delta() {
  local before="$1" after="$2"
  local b_num a_num
  b_num=$(echo "$before" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
  a_num=$(echo "$after" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
  if [ -z "$b_num" ] || [ -z "$a_num" ]; then
    echo "n/a"
  else
    awk "BEGIN {printf \"%.1fMiB\", $a_num - $b_num}" 2>/dev/null || echo "n/a"
  fi
}

parse_k6_p() {
  local file="$1"
  local pct="$2"
  if [ ! -f "$file" ]; then
    echo "n/a"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$file" "$pct" <<'PY' 2>/dev/null || echo "n/a"
import json, sys
f = sys.argv[1]
pct = sys.argv[2]
key = f"p({pct})"
try:
    data = json.load(open(f))
    m = data.get("metrics", {}).get("http_req_duration", {})
    v = m.get(key)
    if v is None:
        v = m.get("percentiles", {}).get(key)
    if v is None:
        v = m.get("values", {}).get(key)
    if v is None:
        # fallback scan any dict level
        for k in (m, data.get("metrics", {})):
            if isinstance(k, dict) and key in k:
                v = k[key]
                break
    if v is None or v == "":
        print("n/a")
    else:
        try:
            print(f"{float(v):.2f}ms")
        except:
            print(f"{v}")
except Exception:
    print("n/a")
PY
    return 0
  fi
  if command -v jq >/dev/null 2>&1; then
    local val
    val=$(jq -r ".metrics.http_req_duration[\"p($pct)\"] // .metrics.http_req_duration.percentiles[\"p($pct)\"] // .metrics.http_req_duration.values[\"p($pct)\"] // empty" "$file" 2>/dev/null || true)
    if [ -n "$val" ] && [ "$val" != "null" ]; then
      printf "%.2fms" "$val" 2>/dev/null || echo "${val}ms"
    else
      echo "n/a"
    fi
    return 0
  fi
  echo "n/a"
}

run_k6() {
  local mode="${1:-default}"
  local summary="/tmp/k6-${mode}.json"
  if command -v k6 &> /dev/null; then
    echo "Running bench 60s 200VUs..."
    k6 run --summary-export="$summary" benchmark/load-test.js || echo "k6 failed (continuing)"
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
  JVM_SPRING=$(container_startup_ms springlean-app "Total startup in [0-9]+ms" || true)
  if [ "$JVM_SPRING" = "n/a" ] || [ -z "$JVM_SPRING" ]; then JVM_SPRING=$(parse_spring_startup || true); fi || true
  JVM_MEM_BEFORE=$(measure_memory)
echo "Spring startup: ${JVM_SPRING} | Time-to-health: ${JVM_HEALTH_MS}ms | Memory: ${JVM_MEM_BEFORE}"
warmup
  # peak covers k6 only (not warmup)
  sample_peak_mem /tmp/peak-jvm.txt & PEAK_PID=$! || true
run_k6 jvm || true
  kill $PEAK_PID 2>/dev/null || true; wait $PEAK_PID 2>/dev/null || true
  JVM_PEAK=$(cat /tmp/peak-jvm.txt 2>/dev/null || echo "n/a"); if [ -z "$JVM_PEAK" ] || [ "$JVM_PEAK" = "0.0MiB" ]; then JVM_PEAK="n/a"; fi || true
  JVM_P90=$(parse_k6_p "/tmp/k6-jvm.json" "90" 2>/dev/null || echo "n/a") || true
JVM_P95=$(parse_k6_p "/tmp/k6-jvm.json" "95" 2>/dev/null || echo "n/a") || true
[ -z "$JVM_P90" ] && JVM_P90="n/a" || true
[ -z "$JVM_P95" ] && JVM_P95="n/a" || true
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
    NATIVE_SPRING=$(container_startup_ms springlean-app "Total startup in [0-9]+ms" || true)
    if [ "$NATIVE_SPRING" = "n/a" ] || [ -z "$NATIVE_SPRING" ]; then NATIVE_SPRING=$(parse_spring_startup || true); fi || true
    NATIVE_MEM_BEFORE=$(measure_memory)
    echo "Spring startup: ${NATIVE_SPRING} | Time-to-health: ${NATIVE_HEALTH_MS}ms | Memory: ${NATIVE_MEM_BEFORE}"
    warmup
  # peak covers k6 only (not warmup)
  sample_peak_mem /tmp/peak-native.txt & PEAK_PID=$! || true
    run_k6 native || true
  kill $PEAK_PID 2>/dev/null || true; wait $PEAK_PID 2>/dev/null || true
  NATIVE_PEAK=$(cat /tmp/peak-native.txt 2>/dev/null || echo "n/a"); if [ -z "$NATIVE_PEAK" ] || [ "$NATIVE_PEAK" = "0.0MiB" ]; then NATIVE_PEAK="n/a"; fi || true
    NATIVE_P90=$(parse_k6_p "/tmp/k6-native.json" "90" 2>/dev/null || echo "n/a") || true
    NATIVE_P95=$(parse_k6_p "/tmp/k6-native.json" "95" 2>/dev/null || echo "n/a") || true
    [ -z "$NATIVE_P90" ] && NATIVE_P90="n/a" || true
    [ -z "$NATIVE_P95" ] && NATIVE_P95="n/a" || true
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
    GO_STARTUP=$(container_startup_ms springlean-app "started in [0-9]+ms" || true)
    if [ "$GO_STARTUP" = "n/a" ] || [ -z "$GO_STARTUP" ]; then GO_STARTUP=$(parse_go_startup || true); fi || true
    GO_MEM_BEFORE=$(measure_memory)
    echo "Go startup: ${GO_STARTUP} | Time-to-health: ${GO_HEALTH_MS}ms | Memory: ${GO_MEM_BEFORE}"
    warmup
  # peak covers k6 only (not warmup)
  sample_peak_mem /tmp/peak-go.txt & PEAK_PID=$! || true
    run_k6 go || true
  kill $PEAK_PID 2>/dev/null || true; wait $PEAK_PID 2>/dev/null || true
  GO_PEAK=$(cat /tmp/peak-go.txt 2>/dev/null || echo "n/a"); if [ -z "$GO_PEAK" ] || [ "$GO_PEAK" = "0.0MiB" ]; then GO_PEAK="n/a"; fi || true
    GO_P90=$(parse_k6_p "/tmp/k6-go.json" "90" 2>/dev/null || echo "n/a") || true
    GO_P95=$(parse_k6_p "/tmp/k6-go.json" "95" 2>/dev/null || echo "n/a") || true
    [ -z "$GO_P90" ] && GO_P90="n/a" || true
    [ -z "$GO_P95" ] && GO_P95="n/a" || true
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
    RUST_STARTUP=$(container_startup_ms springlean-app "started in [0-9]+ms" || true)
    if [ "$RUST_STARTUP" = "n/a" ] || [ -z "$RUST_STARTUP" ]; then RUST_STARTUP=$(parse_rust_startup || true); fi || true
    RUST_MEM_BEFORE=$(measure_memory)
    echo "Rust startup: ${RUST_STARTUP} | Time-to-health: ${RUST_HEALTH_MS}ms | Memory: ${RUST_MEM_BEFORE}"
    warmup
  # peak covers k6 only (not warmup)
  sample_peak_mem /tmp/peak-rust.txt & PEAK_PID=$! || true
    run_k6 rust || true
  kill $PEAK_PID 2>/dev/null || true; wait $PEAK_PID 2>/dev/null || true
  RUST_PEAK=$(cat /tmp/peak-rust.txt 2>/dev/null || echo "n/a"); if [ -z "$RUST_PEAK" ] || [ "$RUST_PEAK" = "0.0MiB" ]; then RUST_PEAK="n/a"; fi || true
    RUST_P90=$(parse_k6_p "/tmp/k6-rust.json" "90" 2>/dev/null || echo "n/a") || true
    RUST_P95=$(parse_k6_p "/tmp/k6-rust.json" "95" 2>/dev/null || echo "n/a") || true
    [ -z "$RUST_P90" ] && RUST_P90="n/a" || true
    [ -z "$RUST_P95" ] && RUST_P95="n/a" || true
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
# Micronaut Mode
# ============================================================
if echo "$MODES" | grep -qw "micronaut"; then
echo "=== Micronaut Mode ==="
echo "Building Docker image spring-lean:micronaut..."
if ! docker build -f micronaut/Dockerfile -t spring-lean:micronaut ./micronaut 2>&1; then
  echo "Micronaut build FAILED. Skipping Micronaut benchmark."
  echo ""
else
  echo "Running container with memory limit 1g..."
  docker rm -f springlean-app 2>/dev/null || true
  START=$(date +%s%N)
  docker run -d --memory=1g --memory-swap=1g -p 8080:8080 --network springlean-net -e DATABASE_URL=postgres://springlean:springlean@springlean-pg:5432/springlean?sslmode=disable -e SPRING_DATASOURCE_URL=jdbc:postgresql://springlean-pg:5432/springlean -e DATASOURCES_DEFAULT_URL=jdbc:postgresql://springlean-pg:5432/springlean -e DATASOURCES_DEFAULT_USERNAME=springlean -e DATASOURCES_DEFAULT_PASSWORD=springlean --name springlean-app spring-lean:micronaut > /dev/null

  if ! wait_for_health; then
    echo "Micronaut failed to start. Logs:"
    docker logs springlean-app 2>&1 | tail -20 || true
    docker rm -f springlean-app > /dev/null 2>&1 || true
  else
    HEALTH_END=$(date +%s%N)
    MICRONAUT_HEALTH_MS=$(( (HEALTH_END - START) / 1000000 ))
    MICRONAUT_STARTUP=$(container_startup_ms springlean-app "Startup completed in [0-9]+ms" || true)
    if [ "$MICRONAUT_STARTUP" = "n/a" ] || [ -z "$MICRONAUT_STARTUP" ]; then MICRONAUT_STARTUP=$(parse_micronaut_startup || true); fi || true
    MICRONAUT_MEM_BEFORE=$(measure_memory)
    echo "Micronaut startup: ${MICRONAUT_STARTUP} | Time-to-health: ${MICRONAUT_HEALTH_MS}ms | Memory: ${MICRONAUT_MEM_BEFORE}"
    warmup
  # peak covers k6 only (not warmup)
  sample_peak_mem /tmp/peak-micronaut.txt & PEAK_PID=$! || true
    run_k6 micronaut || true
  kill $PEAK_PID 2>/dev/null || true; wait $PEAK_PID 2>/dev/null || true
  MICRONAUT_PEAK=$(cat /tmp/peak-micronaut.txt 2>/dev/null || echo "n/a"); if [ -z "$MICRONAUT_PEAK" ] || [ "$MICRONAUT_PEAK" = "0.0MiB" ]; then MICRONAUT_PEAK="n/a"; fi || true
    MICRONAUT_P90=$(parse_k6_p "/tmp/k6-micronaut.json" "90" 2>/dev/null || echo "n/a") || true
    MICRONAUT_P95=$(parse_k6_p "/tmp/k6-micronaut.json" "95" 2>/dev/null || echo "n/a") || true
    [ -z "$MICRONAUT_P90" ] && MICRONAUT_P90="n/a" || true
    [ -z "$MICRONAUT_P95" ] && MICRONAUT_P95="n/a" || true
    MICRONAUT_MEM_AFTER=$(measure_memory)
    MICRONAUT_MEM_DELTA=$(calc_delta "$MICRONAUT_MEM_BEFORE" "$MICRONAUT_MEM_AFTER")
    echo "Memory before: $MICRONAUT_MEM_BEFORE | after: $MICRONAUT_MEM_AFTER | delta: $MICRONAUT_MEM_DELTA"
    MICRONAUT_MEM="$MICRONAUT_MEM_AFTER"
    echo "Docker stats: $(docker stats --no-stream --format "{{.MemUsage}} ({{.MemPerc}})" springlean-app 2>/dev/null || echo "N/A")"
    docker rm -f springlean-app > /dev/null 2>&1 || true
  fi
  echo "Micronaut complete."
  echo ""
fi
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "=== Summary ==="
fmt_ms() {
  if [ -n "${1:-}" ]; then echo "${1}ms"; else echo "n/a"; fi
}
fmt_mem_k6() {
  if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then echo "n/a"; return 0; fi
  local a b d
  a=$(echo "$1" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
  b=$(echo "$2" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
  if [ -z "$a" ] || [ -z "$b" ]; then echo "n/a"; return 0; fi
  d=$(awk "BEGIN {printf \"%.0f\", $a - $b}" 2>/dev/null || echo "?")
  echo "$1 (+${d})"
}
printf "| %-22s | %-12s | %-14s | %-13s | %-13s | %-19s | %-7s | %-7s |\n" "Mode" "Startup time" "Time-to-Health" "Memory (idle)" "Memory (peak)" "Memory (retained)" "P90" "P95"
printf "|%-24s|%-14s|%-16s|%-15s|%-15s|%-21s|%-9s|%-9s|\n" "------------------------" "--------------" "----------------" "---------------" "---------------" "---------------------" "---------" "---------"
printf "| %-22s | %-12s | %-14s | %-13s | %-13s | %-19s | %-7s | %-7s |\n" "Spring Boot (JVM+Leyden)" "${JVM_SPRING:-n/a}" "$(fmt_ms "${JVM_HEALTH_MS:-}")" "${JVM_MEM_BEFORE:-n/a}" "${JVM_PEAK:-n/a}" "$(fmt_mem_k6 "${JVM_MEM_AFTER:-}" "${JVM_MEM_BEFORE:-}")" "${JVM_P90:-n/a}" "${JVM_P95:-n/a}"
printf "| %-22s | %-12s | %-14s | %-13s | %-13s | %-19s | %-7s | %-7s |\n" "Spring Boot (Native)" "${NATIVE_SPRING:-n/a}" "$(fmt_ms "${NATIVE_HEALTH_MS:-}")" "${NATIVE_MEM_BEFORE:-n/a}" "${NATIVE_PEAK:-n/a}" "$(fmt_mem_k6 "${NATIVE_MEM_AFTER:-}" "${NATIVE_MEM_BEFORE:-}")" "${NATIVE_P90:-n/a}" "${NATIVE_P95:-n/a}"
printf "| %-22s | %-12s | %-14s | %-13s | %-13s | %-19s | %-7s | %-7s |\n" "Gin (Go)" "${GO_STARTUP:-n/a}" "$(fmt_ms "${GO_HEALTH_MS:-}")" "${GO_MEM_BEFORE:-n/a}" "${GO_PEAK:-n/a}" "$(fmt_mem_k6 "${GO_MEM_AFTER:-}" "${GO_MEM_BEFORE:-}")" "${GO_P90:-n/a}" "${GO_P95:-n/a}"
printf "| %-22s | %-12s | %-14s | %-13s | %-13s | %-19s | %-7s | %-7s |\n" "Axum (Rust)" "${RUST_STARTUP:-n/a}" "$(fmt_ms "${RUST_HEALTH_MS:-}")" "${RUST_MEM_BEFORE:-n/a}" "${RUST_PEAK:-n/a}" "$(fmt_mem_k6 "${RUST_MEM_AFTER:-}" "${RUST_MEM_BEFORE:-}")" "${RUST_P90:-n/a}" "${RUST_P95:-n/a}"
printf "| %-22s | %-12s | %-14s | %-13s | %-13s | %-19s | %-7s | %-7s |\n" "Micronaut" "${MICRONAUT_STARTUP:-n/a}" "$(fmt_ms "${MICRONAUT_HEALTH_MS:-}")" "${MICRONAUT_MEM_BEFORE:-n/a}" "${MICRONAUT_PEAK:-n/a}" "$(fmt_mem_k6 "${MICRONAUT_MEM_AFTER:-}" "${MICRONAUT_MEM_BEFORE:-}")" "${MICRONAUT_P90:-n/a}" "${MICRONAUT_P95:-n/a}"

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
echo "  JVM+Leyden: ${JVM_MEM_BEFORE:-N/A} -> ${JVM_PEAK:-N/A} (peak) -> ${JVM_MEM_AFTER:-N/A} (delta: ${JVM_MEM_DELTA:-N/A})"
echo "  Native    : ${NATIVE_MEM_BEFORE:-N/A} -> ${NATIVE_PEAK:-N/A} (peak) -> ${NATIVE_MEM_AFTER:-N/A} (delta: ${NATIVE_MEM_DELTA:-N/A})"
echo "  Go        : ${GO_MEM_BEFORE:-N/A} -> ${GO_PEAK:-N/A} (peak) -> ${GO_MEM_AFTER:-N/A} (delta: ${GO_MEM_DELTA:-N/A})"
echo "  Rust      : ${RUST_MEM_BEFORE:-N/A} -> ${RUST_PEAK:-N/A} (peak) -> ${RUST_MEM_AFTER:-N/A} (delta: ${RUST_MEM_DELTA:-N/A})"
echo "  Micronaut : ${MICRONAUT_MEM_BEFORE:-N/A} -> ${MICRONAUT_PEAK:-N/A} (peak) -> ${MICRONAUT_MEM_AFTER:-N/A} (delta: ${MICRONAUT_MEM_DELTA:-N/A})"
echo "Note: PGO endurance isn't tested (just G1 GC for native)."

trap - EXIT
docker rm -f springlean-app > /dev/null 2>&1 || true
docker rm -f springlean-pg > /dev/null 2>&1 || true
docker network rm springlean-net > /dev/null 2>&1 || true
echo ""
echo "=== Benchmark Complete ==="
