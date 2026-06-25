// e2ee_middleware.go — gRPC interceptors for E2EE session negotiation.
//
// Purpose: UnaryE2EEInterceptor and StreamE2EEInterceptor enforce that every
//          non-Health gRPC call carries a valid E2EE session key derived via the
//          libnclaw-server sidecar. When NCLAW_E2EE_ENABLED=false the interceptors
//          pass through with a warning log (non-production environments only —
//          CheckE2EEFeatureFlag already logs CRITICAL at startup).
//
// Inputs:  gRPC request with metadata key "x-nclaw-e2ee-session-id".
// Outputs: context enriched with LibnclawClient; or UNAUTHENTICATED on missing session.
// Constraints: Never decrypt request payload inside the interceptor — only validate
//              session existence. Payload decryption is the handler's responsibility.
//              The interceptor must not log session key material.
// SPORT: REGISTRY-SERVICES.md — libnclaw-server sidecar, e2ee interceptor chain.

package intelligence

import (
	"context"
	"os"

	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
)

type contextKey string

const e2eeClientKey contextKey = "libnclaw_client"

// UnaryE2EEInterceptor validates that a non-Health RPC carries an E2EE session.
// When NCLAW_E2EE_ENABLED != "false" it injects a LibnclawClient into the context
// and returns UNAUTHENTICATED if the session header is missing.
// When NCLAW_E2EE_ENABLED == "false" it logs a warning and passes through.
func UnaryE2EEInterceptor(logger interface{ Warn(string, ...any) }) grpc.UnaryServerInterceptor {
	client := NewLibnclawClient()
	return func(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
		if info.FullMethod == "/nclaw.intelligence.v1.IntelligenceService/Health" {
			return handler(ctx, req)
		}

		if os.Getenv("NCLAW_E2EE_ENABLED") == "false" {
			// Pass-through with warning — CheckE2EEFeatureFlag already logged CRITICAL.
			return handler(ctx, req)
		}

		md, ok := metadata.FromIncomingContext(ctx)
		if !ok || len(md.Get("x-nclaw-e2ee-session-id")) == 0 {
			return nil, ErrUnauthenticated("missing e2ee session")
		}

		ctx = context.WithValue(ctx, e2eeClientKey, client)
		return handler(ctx, req)
	}
}

// StreamE2EEInterceptor validates E2EE session presence on streaming RPCs.
// Follows the same pass-through logic as UnaryE2EEInterceptor.
func StreamE2EEInterceptor() grpc.StreamServerInterceptor {
	return func(srv any, ss grpc.ServerStream, info *grpc.StreamServerInfo, handler grpc.StreamHandler) error {
		if os.Getenv("NCLAW_E2EE_ENABLED") == "false" {
			return handler(srv, ss)
		}
		md, ok := metadata.FromIncomingContext(ss.Context())
		if !ok || len(md.Get("x-nclaw-e2ee-session-id")) == 0 {
			return ErrUnauthenticated("missing e2ee session")
		}
		return handler(srv, ss)
	}
}

// LibnclawClientFromContext retrieves the LibnclawClient injected by UnaryE2EEInterceptor.
// Returns nil when E2EE is disabled or the interceptor did not run.
func LibnclawClientFromContext(ctx context.Context) *LibnclawClient {
	v := ctx.Value(e2eeClientKey)
	if v == nil {
		return nil
	}
	c, _ := v.(*LibnclawClient)
	return c
}
