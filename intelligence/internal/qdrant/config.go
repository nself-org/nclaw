// config.go — Qdrant connection configuration for nclaw intelligence service.
//
// Purpose: Load Qdrant connection parameters from environment variables and
//          construct a typed Config used by the qdrant client and collection
//          migration. Supports both HTTP and gRPC endpoints.
//
// Inputs:  QDRANT_HOST, QDRANT_PORT, QDRANT_API_KEY environment variables.
//          QDRANT_HOST defaults to "localhost"; QDRANT_PORT defaults to "6333" (gRPC).
//          QDRANT_HTTP_PORT defaults to "6334" (HTTP REST).
//          QDRANT_API_KEY is optional — passed as api-key metadata if non-empty.
//
// Outputs: Config struct with GRPCURL, HTTPURL, APIKey fields.
// Constraints: Pure env-read, no side effects; safe to call multiple times.
//              Never logs the API key value.
//
// SPORT: F10-PORT-REGISTRY.md — port 6333 (qdrant-grpc), 6334 (qdrant-http).
// Env vars: .claude/docs/reference/environment-variables.md — QDRANT_HOST / QDRANT_PORT /
//           QDRANT_API_KEY / NCLAW_QDRANT_URL / NCLAW_QDRANT_GRPC_URL.

package qdrant

import (
	"fmt"
	"os"
)

const (
	// DefaultHost is the Qdrant host used when QDRANT_HOST is unset.
	DefaultHost = "localhost"
	// DefaultGRPCPort is the Qdrant gRPC port (F10: 6333).
	DefaultGRPCPort = "6333"
	// DefaultHTTPPort is the Qdrant HTTP REST port (F10: 6334).
	DefaultHTTPPort = "6334"
)

// Config holds all parameters needed to connect to the Qdrant service.
type Config struct {
	// GRPCURL is the gRPC endpoint, e.g. "localhost:6333".
	// Used by the gRPC client for low-latency vector search.
	GRPCURL string
	// HTTPURL is the HTTP REST endpoint, e.g. "http://localhost:6334".
	// Used for collection management operations.
	HTTPURL string
	// APIKey is an optional Qdrant API key.
	// When non-empty it is sent as the "api-key" gRPC metadata header.
	APIKey string
}

// ConfigFromEnv constructs a Config from environment variables.
//
//   QDRANT_HOST      — hostname or IP of the Qdrant instance (default: "localhost")
//   QDRANT_PORT      — gRPC port (default: "6333")
//   QDRANT_API_KEY   — optional API key for authenticated clusters
//
// The HTTP port is derived from QDRANT_PORT+1 convention but can be overridden
// via QDRANT_HTTP_PORT.
func ConfigFromEnv() Config {
	host := envOrDefault("QDRANT_HOST", DefaultHost)
	grpcPort := envOrDefault("QDRANT_PORT", DefaultGRPCPort)
	httpPort := envOrDefault("QDRANT_HTTP_PORT", DefaultHTTPPort)
	apiKey := os.Getenv("QDRANT_API_KEY")

	return Config{
		GRPCURL: fmt.Sprintf("%s:%s", host, grpcPort),
		HTTPURL: fmt.Sprintf("http://%s:%s", host, httpPort),
		APIKey:  apiKey,
	}
}

// envOrDefault returns the value of the named env var, or fallback if unset or empty.
func envOrDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
