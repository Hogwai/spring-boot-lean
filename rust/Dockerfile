# syntax=docker/dockerfile:1
FROM rust:1.93-bookworm AS builder
WORKDIR /app
COPY Cargo.toml Cargo.lock* rust-toolchain.toml* ./
RUN mkdir -p src/transaction \
    && echo "fn main(){}" > src/main.rs \
    && echo "" > src/config.rs \
    && echo "" > src/transaction/mod.rs \
    && cargo build --release || true
COPY src ./src
RUN touch src/main.rs src/config.rs src/transaction/mod.rs && cargo build --release

FROM debian:12-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libssl3 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m app
USER app
COPY --from=builder /app/target/release/spring-boot-lean /server
EXPOSE 8080
ENTRYPOINT ["/server"]
