// errors.go — shared error helpers for generated gRPC stubs.
//
// Purpose: Provide errUnimplemented used by all Unimplemented* server structs,
//
//	and GRPCServer registration helpers that work without importing
//	google.golang.org/grpc directly in this package.
//
// SPORT: P2-E5-W4-S8-T08.
package nclaw_proto

import "fmt"

// errUnimplemented returns a standard "not implemented" error for gRPC stubs.
func errUnimplemented(service, method string) error {
	return fmt.Errorf("nclaw intelligence: %s.%s: not implemented — run make proto to regenerate stubs", service, method)
}
