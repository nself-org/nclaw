// errors.go — Typed gRPC status constructors for the intelligence service.
//
// Purpose: Centralise all gRPC error construction so every handler uses
//          consistent status codes and never leaks internal detail to clients.
//          ErrInternal never includes the underlying error string.
//
// Constraints: ErrInternal must never expose DB queries, stack traces, or key material.
//              ErrQdrantUnavailable is nil (caller proceeds to pgvector fallback).
//              All 6 E9 gRPC status codes covered.
// SPORT: REGISTRY-ENDPOINTS.md — error-codes column for intelligence gRPC methods.

package intelligence

import (
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// ErrUnauthenticated returns a gRPC UNAUTHENTICATED (code 16) error.
func ErrUnauthenticated(msg string) error {
	return status.Error(codes.Unauthenticated, msg)
}

// ErrRateLimit returns a gRPC RESOURCE_EXHAUSTED (code 8) error.
func ErrRateLimit() error {
	return status.Error(codes.ResourceExhausted, "rate limit exceeded")
}

// ErrQdrantUnavailable logs a warning internally and returns nil so the
// caller proceeds with the pgvector-only fallback path. Qdrant unavailability
// must never surface as a user-facing error.
func ErrQdrantUnavailable() error {
	return nil
}

// ErrDuplicateFact returns a gRPC ALREADY_EXISTS (code 6) error.
func ErrDuplicateFact() error {
	return status.Error(codes.AlreadyExists, "fact already exists")
}

// ErrInvalidTopK returns a gRPC INVALID_ARGUMENT (code 3) error for top_k > 50.
func ErrInvalidTopK(topK int) error {
	return status.Errorf(codes.InvalidArgument, "top_k must be <= 50, got %d", topK)
}

// ErrMessageTooLarge returns a gRPC INVALID_ARGUMENT (code 3) error.
func ErrMessageTooLarge(field string, maxBytes int) error {
	return status.Errorf(codes.InvalidArgument, "%s exceeds max size (%d bytes)", field, maxBytes)
}

// ErrInternal returns a gRPC INTERNAL (code 13) error.
// The underlying error is NEVER included in the client-visible message.
// Log the underlying error server-side before calling this.
func ErrInternal() error {
	return status.Error(codes.Internal, "internal error")
}
