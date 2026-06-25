// validation_interceptor.go — gRPC unary interceptor for request validation.
//
// Purpose: Enforce per-field size caps before auth and business logic.
//          32KB message cap, 1KB AAD cap, 4KB query/triple caps.
//          Sets MaxRecvMsgSize guard at the transport layer (see server.go).
//          Security-Always-Free: validation is default-on, never paywalled.
//
// Constraints: Runs before auth interceptor in chain. Returns INVALID_ARGUMENT (3).
//              NCLAW_E2EE_ENABLED=false in non-dev: logs CRITICAL (never silently skip).
// SPORT: REGISTRY-ENDPOINTS.md — message size caps for intelligence gRPC methods.

package intelligence

import (
	"context"
	"log/slog"
	"os"

	"google.golang.org/grpc"
)

const (
	MaxMsgBytes    = 32 * 1024  // 32KB
	MaxAADBytes    = 1024       // 1KB
	MaxTripleBytes = 4096       // 4KB
	MaxQueryBytes  = 4096       // 4KB
	MaxRecvMsgSize = 64 * 1024  // 64KB — set at gRPC server level
)

// ValidationInterceptor returns a gRPC UnaryServerInterceptor that validates
// common request fields before passing to the handler chain.
func ValidationInterceptor(logger *slog.Logger) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
		if err := validateRequest(req); err != nil {
			return nil, err
		}
		return handler(ctx, req)
	}
}

// validateRequest inspects the request for known oversized fields.
// Uses duck-typing on interface{} to avoid proto import cycle.
func validateRequest(req any) error {
	// We inspect fields via type assertions on common request shapes.
	// The proto-generated types implement these getter patterns.
	type withMessage interface{ GetMessage() string }
	type withAAD interface{ GetAAD() []byte }
	type withQuery interface{ GetQuery() string }
	type withSubject interface{ GetSubject() string }
	type withPredicate interface{ GetPredicate() string }
	type withObject interface{ GetObject() string }
	type withTopK interface{ GetTopK() int32 }

	if r, ok := req.(withMessage); ok {
		if len(r.GetMessage()) > MaxMsgBytes {
			return ErrMessageTooLarge("message", MaxMsgBytes)
		}
	}
	if r, ok := req.(withAAD); ok {
		if len(r.GetAAD()) > MaxAADBytes {
			return ErrMessageTooLarge("aad", MaxAADBytes)
		}
	}
	if r, ok := req.(withQuery); ok {
		if len(r.GetQuery()) > MaxQueryBytes {
			return ErrMessageTooLarge("query", MaxQueryBytes)
		}
	}
	if r, ok := req.(withSubject); ok {
		if len(r.GetSubject()) > MaxTripleBytes {
			return ErrMessageTooLarge("subject", MaxTripleBytes)
		}
	}
	if r, ok := req.(withPredicate); ok {
		if len(r.GetPredicate()) > MaxTripleBytes {
			return ErrMessageTooLarge("predicate", MaxTripleBytes)
		}
	}
	if r, ok := req.(withObject); ok {
		if len(r.GetObject()) > MaxTripleBytes {
			return ErrMessageTooLarge("object", MaxTripleBytes)
		}
	}
	if r, ok := req.(withTopK); ok {
		if r.GetTopK() > 50 {
			return ErrInvalidTopK(int(r.GetTopK()))
		}
	}
	return nil
}

// CheckE2EEFeatureFlag logs CRITICAL when E2EE is disabled in non-dev environments.
// This guard is called at server startup and when the E2EE interceptor is initialised.
func CheckE2EEFeatureFlag(logger *slog.Logger) {
	enabled := os.Getenv("NCLAW_E2EE_ENABLED")
	env := os.Getenv("NSELF_ENV")
	if enabled == "false" && env != "development" {
		logger.Error("NCLAW_E2EE_ENABLED=false in non-dev environment — CRITICAL security bypass; E2EE is disabled",
			"NSELF_ENV", env,
			"NCLAW_E2EE_ENABLED", enabled,
		)
	}
}
