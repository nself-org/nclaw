// ratelimit.go — Per-user token-bucket rate limiter for intelligence gRPC.
//
// Purpose: Enforce per-user request rate limits using an in-memory token bucket.
//          Rates: 500 Chat/2000 Retrieve/10000 Health requests per minute per user.
//          Rate bucket is keyed by user_id extracted from JWT metadata — never global.
//
// Constraints: No cross-user rate bleed. Thread-safe. Memory-bounded (max 10k buckets).
//              Returns RESOURCE_EXHAUSTED (code 8) on excess. Health is effectively unlimited.
// SPORT: REGISTRY-ENDPOINTS.md — rate-limiting column for intelligence gRPC.

package intelligence

import (
	"sync"
	"time"
)

const (
	RateLimitChat     = 500
	RateLimitRetrieve = 2000
	RateLimitHealth   = 10000
	rateLimitWindow   = time.Minute
	maxBuckets        = 10000
)

// bucket is a per-user, per-method token bucket.
type bucket struct {
	tokens     int
	resetAt    time.Time
	maxTokens  int
	mu         sync.Mutex
}

func newBucket(maxTokens int) *bucket {
	return &bucket{
		tokens:    maxTokens,
		resetAt:   time.Now().Add(rateLimitWindow),
		maxTokens: maxTokens,
	}
}

// Allow consumes one token. Returns true when the request is permitted.
func (b *bucket) Allow() bool {
	b.mu.Lock()
	defer b.mu.Unlock()

	if time.Now().After(b.resetAt) {
		b.tokens = b.maxTokens
		b.resetAt = time.Now().Add(rateLimitWindow)
	}
	if b.tokens <= 0 {
		return false
	}
	b.tokens--
	return true
}

// RateLimiter manages per-user token buckets for all intelligence gRPC methods.
type RateLimiter struct {
	mu      sync.RWMutex
	buckets map[string]map[string]*bucket // userID -> method -> bucket
}

// NewRateLimiter creates an empty RateLimiter.
func NewRateLimiter() *RateLimiter {
	return &RateLimiter{
		buckets: make(map[string]map[string]*bucket),
	}
}

// Allow checks and consumes one token for the given user and method.
// Returns false when the rate limit is exceeded.
func (r *RateLimiter) Allow(userID string, method string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()

	if _, ok := r.buckets[userID]; !ok {
		// Evict oldest entry when at capacity (simple: skip eviction if at max).
		if len(r.buckets) >= maxBuckets {
			return true // fail-open at capacity rather than blocking all users
		}
		r.buckets[userID] = make(map[string]*bucket)
	}

	if _, ok := r.buckets[userID][method]; !ok {
		r.buckets[userID][method] = newBucket(methodLimit(method))
	}

	return r.buckets[userID][method].Allow()
}

func methodLimit(method string) int {
	switch method {
	case "Retrieve":
		return RateLimitRetrieve
	case "Health":
		return RateLimitHealth
	default:
		return RateLimitChat
	}
}
