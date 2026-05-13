# Hello World Plugin — Go Example

A minimal nClaw plugin that implements the MCP protocol over HTTP. This plugin exposes a single tool: `echo`.

## Code (`main.go`)

```go
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
)

// Tool definition for tool discovery
type Tool struct {
	ID           string                 `json:"id"`
	Label        string                 `json:"label"`
	Description  string                 `json:"description"`
	InputSchema  map[string]interface{} `json:"input_schema"`
	Streaming    bool                   `json:"streaming"`
}

// Request for /mcp/invoke
type InvokeRequest struct {
	ToolID string                 `json:"tool_id"`
	Args   map[string]interface{} `json:"args"`
}

// Success response
type Result struct {
	Result map[string]interface{} `json:"result"`
}

// Error response
type ErrorResponse struct {
	Error struct {
		Code       string `json:"code"`
		Message    string `json:"message"`
		Retryable  bool   `json:"retryable"`
	} `json:"error"`
}

// GET /mcp/tools
func handleTools(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	tools := []Tool{
		{
			ID:          "echo",
			Label:       "Echo",
			Description: "Echo back the input text",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"text": map[string]interface{}{
						"type":        "string",
						"description": "Text to echo",
					},
				},
				"required": []string{"text"},
			},
			Streaming: false,
		},
	}
	json.NewEncoder(w).Encode(tools)
}

// POST /mcp/invoke
func handleInvoke(w http.ResponseWriter, r *http.Request) {
	var req InvokeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ErrorResponse{
			Error: struct {
				Code      string `json:"code"`
				Message   string `json:"message"`
				Retryable bool   `json:"retryable"`
			}{Code: "invalid_args", Message: err.Error(), Retryable: false},
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")

	// Handle the echo tool
	if req.ToolID == "echo" {
		text, ok := req.Args["text"].(string)
		if !ok {
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(ErrorResponse{
				Error: struct {
					Code      string `json:"code"`
					Message   string `json:"message"`
					Retryable bool   `json:"retryable"`
				}{Code: "invalid_args", Message: "Missing or invalid 'text' parameter", Retryable: false},
			})
			return
		}

		result := Result{
			Result: map[string]interface{}{
				"echo": fmt.Sprintf("echo: %s", text),
			},
		}
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(result)
		return
	}

	// Unknown tool
	w.WriteHeader(http.StatusNotFound)
	json.NewEncoder(w).Encode(ErrorResponse{
		Error: struct {
			Code      string `json:"code"`
			Message   string `json:"message"`
			Retryable bool   `json:"retryable"`
		}{Code: "not_found", Message: "Tool not found", Retryable: false},
	})
}

func main() {
	http.HandleFunc("/mcp/tools", handleTools)
	http.HandleFunc("/mcp/invoke", handleInvoke)

	addr := "127.0.0.1:38099"
	log.Printf("Starting hello-world plugin on %s\n", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}
```

## Run It

```bash
go run main.go
```

Output:
```
2026/05/13 10:30:45 Starting hello-world plugin on 127.0.0.1:38099
```

## Test It

**List tools:**
```bash
curl http://localhost:38099/mcp/tools | jq
```

Output:
```json
[
  {
    "id": "echo",
    "label": "Echo",
    "description": "Echo back the input text",
    "input_schema": {
      "type": "object",
      "properties": {
        "text": {"type": "string", "description": "Text to echo"}
      },
      "required": ["text"]
    },
    "streaming": false
  }
]
```

**Invoke the tool:**
```bash
curl -X POST http://localhost:38099/mcp/invoke \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token" \
  -d '{"tool_id":"echo","args":{"text":"Hello, nClaw!"}}'
```

Output:
```json
{
  "result": {
    "echo": "echo: Hello, nClaw!"
  }
}
```

## Next Steps

- Add authentication: validate the `Authorization` header
- Add rate limiting: track requests per bearer token
- Add more tools: duplicate the echo tool block, customize input/output
- Stream responses: set `streaming: true`, return NDJSON from `/mcp/invoke`
- Integrate with nSelf: build a Docker image, configure in `docker-compose.yml`, enable service discovery
