// Package pipeline emits transaction events to the analytics data lake.
//
// It follows the same shape as internal/ai: one interface with a real
// implementation and a no-op stand-in, selected by an environment variable that
// defaults to off, with credentials resolved through the default AWS chain. The
// application never branches on which implementation is active.
//
// # What is emitted
//
// Deliberately not the whole transaction. The event carries the identifier, the
// timestamp, the amount, the category, and the two AI-derived fields -- and
// nothing else. The free-text description and the account it belongs to stay in
// the database. That is the same data-minimisation posture the Bedrock
// integration takes: the analytics layer needs shape and magnitude, not the
// merchant name, so sending it would widen exposure for no analytical gain.
//
// # Failure posture
//
// Emission is best-effort and must never affect the write it describes. Every
// failure path -- a full buffer, a rejected batch, an unreachable endpoint --
// logs and drops. A transaction that was committed successfully is a success
// regardless of whether its analytics event survived.
package pipeline

import (
	"context"
	"errors"
	"time"
)

// Event is one transaction as the data lake sees it.
//
// Field names are the contract for the Glue schema and the Athena table, so
// changing a JSON tag is a breaking change to the curated dataset, not a
// refactor.
type Event struct {
	ID        int       `json:"id"`
	Timestamp time.Time `json:"timestamp"`
	Amount    float64   `json:"amount"`
	Category  string    `json:"category"`
	// AIProvider records which provider enriched the row ("bedrock" or
	// "stub"), so analysis can separate real inference from local stand-in
	// output rather than treating them as one population.
	AIProvider string `json:"ai_provider,omitempty"`
	// AnomalySeverity is "none", "low", "medium" or "high"; empty when the
	// transaction was never assessed.
	AnomalySeverity string `json:"anomaly_severity,omitempty"`
}

// Emitter accepts events for delivery to the lake.
//
// Implementations must be safe for concurrent use and Emit must not block:
// it is called from an HTTP handler on the write path.
type Emitter interface {
	// Name identifies the backing implementation for logging, e.g. "firehose"
	// or "disabled".
	Name() string

	// Emit hands over an event. It never blocks and never returns an error --
	// there is no useful action a caller could take, and the write it
	// describes has already succeeded.
	Emit(Event)

	// Close flushes what is buffered, bounded by the context.
	Close(ctx context.Context) error
}

// ErrUnavailable indicates the delivery stream could not be reached or rejected
// the batch. Mirrors ai.ErrUnavailable: callers log and continue.
var ErrUnavailable = errors.New("data pipeline unavailable")

// Disabled is the no-op emitter used when DATA_PIPELINE is off.
//
// It is the default deliberately. A misconfigured or forgotten flag then costs
// nothing, rather than quietly starting to bill for Firehose ingestion.
type Disabled struct{}

func NewDisabled() *Disabled { return &Disabled{} }

func (*Disabled) Name() string { return "disabled" }

func (*Disabled) Emit(Event) {}

func (*Disabled) Close(context.Context) error { return nil }
