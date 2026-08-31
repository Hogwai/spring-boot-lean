.PHONY: run build vet tidy fmt clean

run:
	go run ./cmd/server

build:
	go build -o /tmp/golean ./cmd/server

vet:
	go vet ./...

tidy:
	go mod tidy

fmt:
	go fmt ./...

clean:
	rm -f /tmp/golean
