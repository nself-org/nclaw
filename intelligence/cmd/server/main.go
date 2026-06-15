// Command server — nclaw-intelligence gRPC server.
//
// Purpose: Start the nclaw intelligence gRPC server on NCLAW_INTELLIGENCE_PORT (9441 per
//
//	F10-PORT-REGISTRY.md). Registers MemoryService, KnowledgeService, and
//	AgentToolsService handlers backed by the T04/T05/T06 internal packages.
//	Reads all 7 required env vars at startup with explicit failure on missing
//	NCLAW_DB_URL or NCLAW_NSELF_SERVICE_TOKEN. Handles SIGTERM gracefully.
//
// Env vars:
//
//	NCLAW_INTELLIGENCE_PORT     — gRPC listen port; defaults to 9441 (F10).
//	NCLAW_DB_URL                — Postgres DSN (required; fatal if empty).
//	NCLAW_QDRANT_URL            — Qdrant vector store URL.
//	NCLAW_EMBED_URL             — BGE-M3 embedding service URL (port 9431).
//	NCLAW_FALKORDB_URL          — FalkorDB graph URL.
//	NCLAW_NSELF_API_URL         — nSelf backend API base URL.
//	NCLAW_NSELF_SERVICE_TOKEN   — service token for nSelf API calls (required; fatal if empty).
//	NCLAW_DEV_BYPASS_AUTH       — "true" enables dev auth bypass (non-production only).
//
// SPORT: F10-PORT-REGISTRY.md (port 9441) · F08-SERVICE-INVENTORY.md — P2-E5-W4-S8-T08.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5"
)

const (
	// defaultPort is the nclaw intelligence service port per F10-PORT-REGISTRY.md.
	defaultPort = "9441"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo}))

	// ── Env var validation ────────────────────────────────────────────────────
	// All 7 env vars are read at startup. NCLAW_DB_URL and NCLAW_NSELF_SERVICE_TOKEN
	// are required; others may be empty in dev (services start in degraded mode).
	dbURL := os.Getenv("NCLAW_DB_URL")
	if dbURL == "" {
		logger.Error("NCLAW_DB_URL is required but not set")
		os.Exit(1)
	}

	serviceToken := os.Getenv("NCLAW_NSELF_SERVICE_TOKEN")
	if serviceToken == "" {
		logger.Error("NCLAW_NSELF_SERVICE_TOKEN is required but not set")
		os.Exit(1)
	}

	port := os.Getenv("NCLAW_INTELLIGENCE_PORT")
	if port == "" {
		port = defaultPort
	}

	// Log optional env var presence without exposing values.
	logger.Info("nclaw-intelligence starting",
		"port", port,
		"qdrant_url_set", os.Getenv("NCLAW_QDRANT_URL") != "",
		"embed_url_set", os.Getenv("NCLAW_EMBED_URL") != "",
		"falkordb_url_set", os.Getenv("NCLAW_FALKORDB_URL") != "",
		"nself_api_url_set", os.Getenv("NCLAW_NSELF_API_URL") != "",
		"dev_bypass_auth", os.Getenv("NCLAW_DEV_BYPASS_AUTH") == "true",
	)

	// ── Database connection ───────────────────────────────────────────────────
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	db, err := pgx.Connect(ctx, dbURL)
	cancel()
	if err != nil {
		logger.Error("failed to connect to Postgres", "error", err)
		os.Exit(1)
	}
	defer func() {
		if closeErr := db.Close(context.Background()); closeErr != nil {
			logger.Warn("db close error", "error", closeErr)
		}
	}()
	logger.Info("connected to Postgres")

	// ── gRPC service handlers ─────────────────────────────────────────────────
	memHandler := newMemoryHandler(db)
	knowledgeHandler := newKnowledgeHandler(db)
	agtHandler := newAgentToolsHandler()

	// ── TCP listener ──────────────────────────────────────────────────────────
	addr := fmt.Sprintf(":%s", port)
	lis, err := net.Listen("tcp", addr)
	if err != nil {
		logger.Error("failed to listen", "addr", addr, "error", err)
		os.Exit(1)
	}

	// ── gRPC server ───────────────────────────────────────────────────────────
	// Note: google.golang.org/grpc registration wires handlers to the gRPC server.
	// The server is constructed here with the three service handlers. Auth interceptor
	// is stubbed; E2 wires JWT middleware once the auth package is available.
	srv := newGRPCServer(logger, memHandler, knowledgeHandler, agtHandler)

	// ── Start serving ─────────────────────────────────────────────────────────
	serverErr := make(chan error, 1)
	go func() {
		logger.Info("nclaw-intelligence gRPC server ready", "addr", addr)
		serverErr <- srv.Serve(lis)
	}()

	// ── Graceful shutdown ─────────────────────────────────────────────────────
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)

	select {
	case sig := <-quit:
		logger.Info("shutdown signal received", "signal", sig.String())
	case err := <-serverErr:
		if err != nil {
			logger.Error("server error", "error", err)
			os.Exit(1)
		}
	}

	logger.Info("graceful stop in progress...")
	srv.GracefulStop()
	logger.Info("nclaw-intelligence stopped")
}
