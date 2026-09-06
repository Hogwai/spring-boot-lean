# syntax=docker/dockerfile:1
FROM maven:3.9-eclipse-temurin-25-alpine AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q
COPY src ./src
RUN mvn -q -DskipTests package

FROM eclipse-temurin:25-jre-alpine AS aot
WORKDIR /app
COPY --from=builder /app/target/micronaut-lean-*.jar ./app.jar
RUN apk add --no-cache coreutils 2>/dev/null || true; \
    timeout 15 java -XX:AOTCacheOutput=app.aot \
    -XX:MaxRAMPercentage=70.0 \
    -XX:+UseCompactObjectHeaders -jar app.jar || true

FROM eclipse-temurin:25-jre-alpine
RUN addgroup -S app && adduser -S app -G app
USER app
WORKDIR /app
COPY --from=aot /app/app.jar ./app.jar
COPY --from=aot /app/app.aot ./app.aot
EXPOSE 8080
ENTRYPOINT ["java", "-XX:AOTCache=app.aot", "-XX:+UseG1GC", "-XX:MaxRAMPercentage=70.0", "-XX:MaxGCPauseMillis=200", "-XX:+UseCompactObjectHeaders", "-jar", "app.jar"]
