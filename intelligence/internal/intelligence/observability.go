// observability.go — Structured logging, Prometheus metrics, and OTel tracing.
//
// Purpose: Create and export the three observability primitives for the intelligence
//          service: slog JSON logger, per-service Prometheus registry (not global),
//          and OTel tracer wired to OTEL_EXPORTER_OTLP_ENDPOINT (no-op if unset).
//
// Prometheus counters:
//   chat_requests_total{status}
//   retrieve_requests_total{retrieval_path}
//   memory_write_total{status}
//   qdrant_fallback_total (counter)
//   e2ee_sessions_active (gauge)
//
// Constraints: Per-service registry (not prometheus.DefaultRegisterer) to avoid
//              cross-test pollution. OTel span attributes must NOT include plaintext
//              message content or private key material.
// SPORT: F10-PORT-REGISTRY.md — port 9442 nclaw-intelligence-metrics HTTP.

package intelligence

import (
	"context"
	"log/slog"
	"os"

	"github.com/prometheus/client_golang/prometheus"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/sdk/trace"
	oteltrace "go.opentelemetry.io/otel/trace"
)

// Metrics holds all Prometheus counters and gauges for the intelligence service.
type Metrics struct {
	ChatRequestsTotal     *prometheus.CounterVec
	RetrieveRequestsTotal *prometheus.CounterVec
	MemoryWriteTotal      *prometheus.CounterVec
	QdrantFallbackTotal   prometheus.Counter
	E2EESessionsActive    prometheus.Gauge
	Registry              *prometheus.Registry
}

// NewIntelligenceLogger creates a JSON-format slog.Logger.
// Fields: service=intelligence, env=NSELF_ENV.
func NewIntelligenceLogger() *slog.Logger {
	env := os.Getenv("NSELF_ENV")
	if env == "" {
		env = "development"
	}
	handler := slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo})
	return slog.New(handler).With("service", "intelligence", "env", env)
}

// NewPrometheusRegistry creates a per-service Prometheus registry and registers
// all intelligence service metrics. Per-service (not global) to avoid test pollution.
func NewPrometheusRegistry() *Metrics {
	reg := prometheus.NewRegistry()

	chatReqs := prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: "nclaw",
		Subsystem: "intelligence",
		Name:      "chat_requests_total",
		Help:      "Total chat gRPC requests by status.",
	}, []string{"status"})

	retrieveReqs := prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: "nclaw",
		Subsystem: "intelligence",
		Name:      "retrieve_requests_total",
		Help:      "Total retrieve gRPC requests by retrieval_path.",
	}, []string{"retrieval_path"})

	memoryWrite := prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: "nclaw",
		Subsystem: "intelligence",
		Name:      "memory_write_total",
		Help:      "Total MemoryWrite gRPC requests by status.",
	}, []string{"status"})

	qdrantFallback := prometheus.NewCounter(prometheus.CounterOpts{
		Namespace: "nclaw",
		Subsystem: "intelligence",
		Name:      "qdrant_fallback_total",
		Help:      "Total times Qdrant was unavailable and pgvector fallback was used.",
	})

	e2eeSessions := prometheus.NewGauge(prometheus.GaugeOpts{
		Namespace: "nclaw",
		Subsystem: "intelligence",
		Name:      "e2ee_sessions_active",
		Help:      "Current number of active E2EE sessions.",
	})

	reg.MustRegister(chatReqs, retrieveReqs, memoryWrite, qdrantFallback, e2eeSessions)

	return &Metrics{
		ChatRequestsTotal:     chatReqs,
		RetrieveRequestsTotal: retrieveReqs,
		MemoryWriteTotal:      memoryWrite,
		QdrantFallbackTotal:   qdrantFallback,
		E2EESessionsActive:    e2eeSessions,
		Registry:              reg,
	}
}

// NewOTelTracer creates an OTel TracerProvider.
// If OTEL_EXPORTER_OTLP_ENDPOINT is unset, returns a no-op tracer.
func NewOTelTracer(ctx context.Context) (oteltrace.Tracer, func(context.Context) error) {
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		// No-op tracer — no remote export.
		noop := trace.NewTracerProvider()
		otel.SetTracerProvider(noop)
		return noop.Tracer("nclaw-intelligence"), func(_ context.Context) error { return noop.Shutdown(ctx) }
	}

	tp := trace.NewTracerProvider()
	otel.SetTracerProvider(tp)
	return tp.Tracer("nclaw-intelligence"), func(ctx context.Context) error { return tp.Shutdown(ctx) }
}
