.PHONY: run-jvm run-native run-go build-docker-jvm build-docker-native build-docker-go bench bench-jvm bench-native bench-go bench-all clean help

# Local run
run-jvm:
	mvn spring-boot:run

run-native:
	mvn -Pnative native:compile -DskipTests && ./target/spring-boot-lean

run-go:
	cd go && go run ./cmd/server

# Docker build
build-docker-jvm:
	docker build -f Dockerfile.jvm -t spring-lean:jvm .

build-docker-native:
	docker build -f Dockerfile.native -t spring-lean:native .

build-docker-go:
	docker build -f go/Dockerfile -t spring-lean:go ./go

# Benchmarks
bench:
	./benchmark/run-benchmarks.sh

bench-jvm:
	./benchmark/run-benchmarks.sh jvm

bench-native:
	./benchmark/run-benchmarks.sh native

bench-go:
	./benchmark/run-benchmarks.sh go

bench-all:
	./benchmark/run-benchmarks.sh all

clean:
	mvn clean
	docker rmi spring-lean:jvm spring-lean:native spring-lean:go 2>/dev/null || true
	rm -rf target/
	rm -f /tmp/golean

help:
	@echo "Available targets:"
	@echo "  run-jvm            - Run JVM locally (mvn spring-boot:run)"
	@echo "  run-native         - Build native binary and run (mvn -Pnative ...)"
	@echo "  run-go             - Run Go server locally (go run ./cmd/server)"
	@echo "  build-docker-jvm   - Build JVM Docker image (spring-lean:jvm)"
	@echo "  build-docker-native- Build Native Docker image (spring-lean:native)"
	@echo "  build-docker-go    - Build Go Docker image (spring-lean:go) with context ./go"
	@echo "  bench              - Run all benchmarks (jvm native go) [alias bench-all]"
	@echo "  bench-jvm          - Run JVM benchmark only"
	@echo "  bench-native       - Run Native benchmark only"
	@echo "  bench-go           - Run Go benchmark only"
	@echo "  bench-all          - Run all benchmarks (jvm native go)"
	@echo "  clean              - Clean build artifacts and Docker images"
	@echo "  help               - Show this help"
