// libnclaw_client.go — Go Unix socket JSON-RPC client for libnclaw-server sidecar.
//
// Purpose: Allow the Go intelligence service to call libnclaw E2EE operations
//          (encrypt, decrypt, derive_session) over a Unix domain socket without cgo.
//          Per OD-3: libnclaw-server runs as a sidecar process; Go connects via socket.
//
// Inputs:  LIBNCLAW_SOCKET_PATH env var (default: /tmp/libnclaw.sock).
// Outputs: encrypted/decrypted bytes, derive_session result.
// Constraints: Never log decrypted plaintext or key material.
//              JSON-RPC 2.0 protocol; newline-delimited messages.
// SPORT: REGISTRY-SERVICES.md — libnclaw-server sidecar, socket=/tmp/libnclaw.sock.

package intelligence

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"sync"
)

// LibnclawClient connects to the libnclaw-server Unix socket sidecar.
type LibnclawClient struct {
	socketPath string
	mu         sync.Mutex
	nextID     int
}

// NewLibnclawClient creates a client for the libnclaw-server sidecar.
// Socket path is read from LIBNCLAW_SOCKET_PATH (default /tmp/libnclaw.sock).
func NewLibnclawClient() *LibnclawClient {
	path := os.Getenv("LIBNCLAW_SOCKET_PATH")
	if path == "" {
		path = "/tmp/libnclaw.sock"
	}
	return &LibnclawClient{socketPath: path}
}

type rpcRequest struct {
	JSONRPC string `json:"jsonrpc"`
	Method  string `json:"method"`
	Params  any    `json:"params"`
	ID      int    `json:"id"`
}

type rpcResponse struct {
	JSONRPC string          `json:"jsonrpc"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *rpcError       `json:"error,omitempty"`
	ID      int             `json:"id"`
}

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// call sends one JSON-RPC request and returns the raw result.
func (c *LibnclawClient) call(method string, params any) (json.RawMessage, error) {
	c.mu.Lock()
	c.nextID++
	id := c.nextID
	c.mu.Unlock()

	conn, err := net.Dial("unix", c.socketPath)
	if err != nil {
		return nil, fmt.Errorf("libnclaw: dial %s: %w", c.socketPath, err)
	}
	defer conn.Close()

	req := rpcRequest{JSONRPC: "2.0", Method: method, Params: params, ID: id}
	enc, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("libnclaw: encode request: %w", err)
	}
	enc = append(enc, '\n')

	if _, err := conn.Write(enc); err != nil {
		return nil, fmt.Errorf("libnclaw: write request: %w", err)
	}

	scanner := bufio.NewScanner(conn)
	if !scanner.Scan() {
		return nil, fmt.Errorf("libnclaw: no response from sidecar")
	}

	var resp rpcResponse
	if err := json.Unmarshal(scanner.Bytes(), &resp); err != nil {
		return nil, fmt.Errorf("libnclaw: decode response: %w", err)
	}
	if resp.Error != nil {
		return nil, fmt.Errorf("libnclaw: rpc error %d", resp.Error.Code)
	}
	return resp.Result, nil
}

// Encrypt encrypts plaintext with the given session key via the libnclaw sidecar.
// Returns the EncryptedMessage JSON (nonce+ciphertext+aad).
// Never logs the key or plaintext.
func (c *LibnclawClient) Encrypt(keyB64 string, plaintextB64 string, aadB64 string) (json.RawMessage, error) {
	params := map[string]string{
		"key_b64":       keyB64,
		"plaintext_b64": plaintextB64,
		"aad_b64":       aadB64,
	}
	return c.call("encrypt", params)
}

// Decrypt decrypts an EncryptedMessage via the libnclaw sidecar.
// Returns the base64-encoded plaintext. Never logs key material.
func (c *LibnclawClient) Decrypt(keyB64 string, message json.RawMessage) (string, error) {
	params := map[string]any{
		"key_b64": keyB64,
		"message": message,
	}
	result, err := c.call("decrypt", params)
	if err != nil {
		return "", err
	}
	var out struct {
		PlaintextB64 string `json:"plaintext_b64"`
	}
	if err := json.Unmarshal(result, &out); err != nil {
		return "", fmt.Errorf("libnclaw: decode decrypt result: %w", err)
	}
	return out.PlaintextB64, nil
}

// DeriveSession generates a fresh ephemeral keypair and derives a session key
// with the given remote public key. Returns the local public key and session key
// (both base64-encoded). Never logs the session key.
func (c *LibnclawClient) DeriveSession(remotePubB64 string) (localPubB64 string, sessionKeyB64 string, err error) {
	params := map[string]string{"remote_pub_b64": remotePubB64}
	result, err := c.call("derive_session", params)
	if err != nil {
		return "", "", err
	}
	var out struct {
		LocalPubB64    string `json:"local_pub_b64"`
		SessionKeyB64  string `json:"session_key_b64"`
	}
	if err := json.Unmarshal(result, &out); err != nil {
		return "", "", fmt.Errorf("libnclaw: decode derive_session result: %w", err)
	}
	return out.LocalPubB64, out.SessionKeyB64, nil
}
