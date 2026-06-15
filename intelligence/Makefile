# Makefile — nclaw intelligence service build + proto codegen.
#
# Purpose: Single entry point for protoc codegen (Go + Dart stubs from same protos),
#          server build, and test. Mirrors clawde/intelligence/Makefile pattern.
# Constraints: proto target must run without error when protoc + plugins are installed.
#              NCLAW_INTELLIGENCE_PORT must match F10-PORT-REGISTRY.md (9441).

PROTO_DIR   := ../proto
GEN_GO_DIR  := ./gen/proto
GEN_DART_DIR := ../mobile/lib/gen/proto

# Tools required: protoc, protoc-gen-go, protoc-gen-go-grpc, protoc-gen-dart
# Install: go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
#          go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
#          dart pub global activate protoc_plugin

.PHONY: proto build test clean

## proto — generate Go + Dart gRPC stubs from nclaw/proto/*.proto
proto:
	@echo "Generating Go gRPC stubs..."
	@mkdir -p $(GEN_GO_DIR)
	protoc \
		--proto_path=$(PROTO_DIR) \
		--go_out=$(GEN_GO_DIR) \
		--go_opt=paths=source_relative \
		--go-grpc_out=$(GEN_GO_DIR) \
		--go-grpc_opt=paths=source_relative \
		$(PROTO_DIR)/memory.proto \
		$(PROTO_DIR)/knowledge.proto \
		$(PROTO_DIR)/agenttools.proto
	@echo "Generating Dart gRPC stubs..."
	@mkdir -p $(GEN_DART_DIR)
	protoc \
		--proto_path=$(PROTO_DIR) \
		--dart_out=grpc:$(GEN_DART_DIR) \
		$(PROTO_DIR)/memory.proto \
		$(PROTO_DIR)/knowledge.proto \
		$(PROTO_DIR)/agenttools.proto
	@echo "Proto codegen complete."

## build — compile the intelligence gRPC server binary
build:
	go build -o bin/nclaw-intelligence ./cmd/server/...

## test — run all intelligence package tests
test:
	go test ./... -count=1

## clean — remove generated stubs and binary
clean:
	rm -rf $(GEN_GO_DIR) bin/
	rm -rf $(GEN_DART_DIR)
