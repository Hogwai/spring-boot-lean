.PHONY: run-jvm run-native build-docker-jvm build-docker-native bench clean

# Local run
run-jvm:
	mvn spring-boot:run

run-native:
	mvn -Pnative native:compile -DskipTests
	./target/spring-boot-lean

# Docker build
build-docker-jvm:
	docker build -f Dockerfile.jvm -t spring-lean:jvm .

build-docker-native:
	docker build -f Dockerfile.native -t spring-lean:native .

# Benchmarks
bench:
	./benchmark/run-benchmarks.sh

clean:
	mvn clean
	docker rmi spring-lean:jvm spring-lean:native 2>/dev/null || true
	rm -rf target/
