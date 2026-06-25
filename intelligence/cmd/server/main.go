// Command server — nclaw-intelligence gRPC server.
//
// Purpose: Start the nclaw intelligence gRPC server on NCLAW_INTELLIGENCE_PORT (9441 per
//
//	F10-PORT-REGISTRY.md). Registers MemoryService, KnowledgeService, AgentToolsService,
//	and IntelligenceService handlers. Reads all required env vars at startup with explicit
//	failure on missing NCLAW_DB_URL or NCLAW_NSELF_SERVICE_TOKEN.
//	TLS: loaded from NCLAW_INTELLIGENCE_TLS_CERT/KEY (optional; plaintext if unset).
//	Metrics: HTTP /metrics on NCLAW_METRICS_PORT (default 9442, F10-PORT-REGISTRY.md).
//	Handles SIGTERM gracefully.
//
// Env vars:
//
//	NCLAW_INTELLIGENCE_PORT     — gRPC listen port; defaults to 9441 (F10).
//	NCLAW_DB_URL                — Postgres DSN (required; fatal if empty).
//	NCLAW_QDRANT_URL            — Qdrant vector store HTTP URL.
//	NCLAW_QDRANT_GRPC_URL       — Qdrant gRPC URL (for QdrantClient).
//	NCLAW_QDRANT_API_KEY        — Qdrant API key.
//	NCLAW_EMBED_URL             — BGE-M3 embedding/rerank service URL (port 9431).
//	NCLAW_FALKORDB_URL          — FalkorDB graph URL.
//	NCLAW_NSELF_API_URL         — nSelf backend API base URL.
//	NCLAW_NSELF_SERVICE_TOKEN   — service token for nSelf API calls (required; fatal if empty).
//	NCLAW_INTELLIGENCE_TLS_CERT — path to TLS certificate file (optional).
//	NCLAW_INTELLIGENCE_TLS_KEY  — path to TLS private key file (optional).
//	NCLAW_E2EE_ENABLED          — "false" disables E2EE (CRITICAL logged in non-dev).
//	NCLAW_SENTRY_DSN            — Sentry DSN for error reporting (optional).
//	NCLAW_METRICS_PORT          — HTTP metrics port; defaults to 9442 (F10).
//	OTEL_EXPORTER_OTLP_ENDPOINT — OTel OTLP endpoint (optional; no-op if unset).
//
// SPORT: F10-PORT-REGISTRY.md (port 9441 + 9442) · F08-SERVICE-INVENTORY.md.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/nself-org/nclaw/intelligence/internal/clients"
	"github.com/nself-org/nclaw/intelligence/internal/intelligence"
)

const (
	// defaultPort is the nclaw intelligence service gRPC port per F10-PORT-REGISTRY.md.
	defaultPort = "9441"
	// defaultMetricsPort is the Prometheus HTTP metrics port per F10-PORT-REGISTRY.md.
	defaultMetricsPort = "9442"
)

func main() {
	logger := intelligence.NewIntelligenceLogger()
	metrics := intelligence.NewPrometheusRegistry()

	// ── Env var validation ────────────────────────────────────────────────────
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

	// T09: NCLAW_DEV_BYPASS_AUTH has been removed. JWT auth is enforced via
	// the E2EE interceptor chain (NCLAW_E2EE_ENABLED controls E2EE path only).
	intelligence.CheckE2EEFeatureFlag(logger)

	port := os.Getenv("NCLAW_INTELLIGENCE_PORT")
	if port == "" {
		port = defaultPort
	}
	metricsPort := os.Getenv("NCLAW_METRICS_PORT")
	if metricsPort == "" {
		metricsPort = defaultMetricsPort
	}

	tlsCert := os.Getenv("NCLAW_INTELLIGENCE_TLS_CERT")
	tlsKey := os.Getenv("NCLAW_INTELLIGENCE_TLS_KEY")
	tlsEnabled := tlsCert != "" && tlsKey != ""

	logger.Info("nclaw-intelligence starting",
		"port", port,
		"metrics_port", metricsPort,
		"tls_enabled", tlsEnabled,
		"qdrant_url_set", os.Getenv("NCLAW_QDRANT_URL") != "",
		"embed_url_set", os.Getenv("NCLAW_EMBED_URL") != "",
		"falkordb_url_set", os.Getenv("NCLAW_FALKORDB_URL") != "",
		"e2ee_enabled", os.Getenv("NCLAW_E2EE_ENABLED") != "false",
		"otel_set", os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT") != "",
	)

	// ── OTel tracer ───────────────────────────────────────────────────────────
	ctx := context.Background()
	_, tracerShutdown := intelligence.NewOTelTracer(ctx)
	defer func() { _ = tracerShutdown(context.Background()) }()

	// ── Database connection ───────────────────────────────────────────────────
	dbCtx, dbCancel := context.WithTimeout(ctx, 10*time.Second)
	db, err := pgx.Connect(dbCtx, dbURL)
	dbCancel()
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

	// ── Service clients ────────────────────────────────────────────────────────
	qdrantCfg := clients.QdrantConfigFromEnv()
	qdrantLogger := slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo}))
	qdrantClient, err := clients.NewQdrantClient(qdrantCfg, qdrantLogger)
	if err != nil {
		logger.Warn("qdrant client init failed — Qdrant will be unavailable", "error", err)
		// Non-fatal: server starts in degraded (pgvector-only) mode.
		qdrantClient = nil
	}
	if qdrantClient != nil {
		defer qdrantClient.Close()
	}
	retrievalClient := clients.NewRetrievalClient(clients.RetrievalClientConfigFromEnv())

	// ── gRPC service handlers ─────────────────────────────────────────────────
	memHandler := newMemoryHandler(db)
	knowledgeHandler := newKnowledgeHandler(db)
	agtHandler := newAgentToolsHandler()
	intelligenceHandler := newIntelligenceHandler(db, qdrantClient, retrievalClient, slog.Default())

	// ── TCP listener ──────────────────────────────────────────────────────────
	addr := fmt.Sprintf(":%s", port)
	lis, err := net.Listen("tcp", addr)
	if err != nil {
		logger.Error("failed to listen", "addr", addr, "error", err)
		os.Exit(1)
	}

	// ── gRPC server with interceptors ─────────────────────────────────────────
	rateLimiter := intelligence.NewRateLimiter()
	srv := newGRPCServer(logger, memHandler, knowledgeHandler, agtHandler, intelligenceHandler, rateLimiter, metrics, tlsCert, tlsKey)

	// ── Prometheus /metrics HTTP server (port 9442) ───────────────────────────
	metricsMux := http.NewServeMux()
	metricsMux.Handle("/metrics", promhttp.HandlerFor(metrics.Registry, promhttp.HandlerOpts{}))
	metricsServer := &http.Server{
		Addr:    fmt.Sprintf(":%s", metricsPort),
		Handler: metricsMux,
	}
	go func() {
		logger.Info("metrics server listening", "addr", metricsServer.Addr)
		if err := metricsServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Warn("metrics server error", "error", err)
		}
	}()
	defer func() {
		shutCtx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		_ = metricsServer.Shutdown(shutCtx)
	}()

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
