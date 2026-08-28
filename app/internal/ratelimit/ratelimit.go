// Package ratelimit provides a per-identity token bucket for HTTP handlers.
//
// It exists mainly to protect the model-backed endpoints: those cost real money
// per call, so an authenticated user looping on them is a billing incident as
// much as a load problem. WAF rate rules sit in front of the ALB and cap
// requests per IP; this caps them per identity, which is the dimension that
// actually maps to spend.
//
// Buckets live in process memory, so with more than one task each replica
// enforces the limit independently. That is a deliberate trade: it needs no
// shared state, and the effective ceiling stays within a small multiple of the
// configured rate. A hard global limit would need Redis or DynamoDB.
package ratelimit

import (
	"net/http"
	"sync"
	"time"

	"golang.org/x/time/rate"

	"github.com/RuariW12/MaroonLedger/internal/auth"
)

type bucket struct {
	limiter  *rate.Limiter
	lastSeen time.Time
}

// Limiter hands out one token bucket per key.
type Limiter struct {
	mu      sync.Mutex
	buckets map[string]*bucket

	rate  rate.Limit
	burst int
	ttl   time.Duration
}

// New creates a limiter allowing perMinute requests per key, tolerating short
// bursts of burst requests.
func New(perMinute float64, burst int) *Limiter {
	l := &Limiter{
		buckets: make(map[string]*bucket),
		rate:    rate.Limit(perMinute / 60.0),
		burst:   burst,
		// Idle buckets are evicted after this long. Without eviction the map
		// grows with every distinct key ever seen, which turns the limiter
		// itself into a memory-exhaustion vector.
		ttl: 10 * time.Minute,
	}
	go l.evictLoop()
	return l
}

// Allow reports whether the key may proceed, consuming a token if so.
func (l *Limiter) Allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	b, ok := l.buckets[key]
	if !ok {
		b = &bucket{limiter: rate.NewLimiter(l.rate, l.burst)}
		l.buckets[key] = b
	}
	b.lastSeen = time.Now()

	return b.limiter.Allow()
}

func (l *Limiter) evictLoop() {
	for range time.Tick(l.ttl) {
		cutoff := time.Now().Add(-l.ttl)

		l.mu.Lock()
		for key, b := range l.buckets {
			// Only evict a bucket that is idle *and* back to full, so eviction
			// can never be used to reset a partially-drained bucket early.
			if b.lastSeen.Before(cutoff) && b.limiter.Tokens() >= float64(l.burst) {
				delete(l.buckets, key)
			}
		}
		l.mu.Unlock()
	}
}

// Middleware rejects requests from an identity that has exceeded its rate.
//
// It keys on the authenticated subject, so it must be mounted inside the auth
// middleware. If no claims are present it fails closed.
func (l *Limiter) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		claims, ok := auth.ClaimsFrom(r.Context())
		if !ok {
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		if !l.Allow(claims.Subject) {
			w.Header().Set("Retry-After", "60")
			http.Error(w, "Rate limit exceeded", http.StatusTooManyRequests)
			return
		}

		next.ServeHTTP(w, r)
	})
}
