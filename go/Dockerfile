# syntax=docker/dockerfile:1
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /server ./cmd/server

FROM alpine:3.20
RUN addgroup -S app && adduser -S app -G app
USER app
COPY --from=builder /server /server
EXPOSE 8080
ENTRYPOINT ["/server"]
