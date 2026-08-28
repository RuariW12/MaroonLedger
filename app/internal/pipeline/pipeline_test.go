package pipeline

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"
)

// The event schema is the contract the Glue job and the Athena table are
// written against, so the field names are asserted rather than assumed.
func TestEventSchema(t *testing.T) {
	when := time.Date(2026, 3, 14, 9, 30, 0, 0, time.UTC)
	data, err := json.Marshal(Event{
		ID:              42,
		Timestamp:       when,
		Amount:          -84.20,
		Category:        "groceries",
		AIProvider:      "bedrock",
		AnomalySeverity: "none",
	})
	if err != nil {
		t.Fatal(err)
	}

	var decoded map[string]any
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatal(err)
	}

	for _, field := range []string{"id", "timestamp", "amount", "category", "ai_provider", "anomaly_severity"} {
		if _, ok := decoded[field]; !ok {
			t.Errorf("event is missing %q -- the curated table expects it", field)
		}
	}

	// Data minimisation is a property of the type, not of the caller. If a
	// description or account field ever appears here, every row already
	// written to the lake carries it.
	for _, forbidden := range []string{"description", "account_id", "account", "user_id", "anomaly_reason"} {
		if _, ok := decoded[forbidden]; ok {
			t.Errorf("event leaks %q into the data lake", forbidden)
		}
	}

	if len(decoded) != 6 {
		t.Errorf("event has %d fields, expected exactly 6: %v", len(decoded), decoded)
	}
}

// Optional fields are omitted rather than serialised as empty strings, so an
// unenriched transaction does not create a bogus "" category in Athena.
func TestEventOmitsUnsetOptionalFields(t *testing.T) {
	data, err := json.Marshal(Event{ID: 1, Amount: -5, Category: "other"})
	if err != nil {
		t.Fatal(err)
	}
	for _, field := range []string{"ai_provider", "anomaly_severity"} {
		if strings.Contains(string(data), field) {
			t.Errorf("unset %q should be omitted, got %s", field, data)
		}
	}
}

func TestDisabledEmitterIsInert(t *testing.T) {
	e := NewDisabled()
	if e.Name() != "disabled" {
		t.Errorf("Name() = %q", e.Name())
	}
	// The whole point: safe to call unconditionally on the write path.
	for i := 0; i < 1000; i++ {
		e.Emit(Event{ID: i})
	}
	if err := e.Close(context.Background()); err != nil {
		t.Errorf("Close() = %v", err)
	}
}

// Emit runs on the HTTP write path, so a full buffer must drop rather than
// block. This is the property that keeps a Firehose outage from becoming
// request latency.
func TestEmitDropsRatherThanBlocking(t *testing.T) {
	// No worker started, so nothing drains the channel -- exactly the state a
	// wedged or throttled delivery stream produces.
	e := &FirehoseEmitter{
		stream: "test",
		events: make(chan Event, 4),
		done:   make(chan struct{}),
	}

	done := make(chan struct{})
	go func() {
		for i := 0; i < 500; i++ {
			e.Emit(Event{ID: i})
		}
		close(done)
	}()

	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("Emit blocked on a full buffer")
	}

	if got := e.dropped.Load(); got != 496 {
		t.Errorf("dropped = %d, want 496 (500 sent, 4 buffered)", got)
	}
}

func TestEncodeProducesNewlineDelimitedJSON(t *testing.T) {
	record, size, err := encode(Event{ID: 7, Amount: -12.5, Category: "dining"})
	if err != nil {
		t.Fatal(err)
	}
	// Firehose concatenates records in the delivered object; without the
	// terminator neither Glue nor Athena can find record boundaries.
	if !strings.HasSuffix(string(record.Data), "\n") {
		t.Errorf("record is not newline-terminated: %q", record.Data)
	}
	if size != len(record.Data) {
		t.Errorf("size = %d, want %d", size, len(record.Data))
	}
	if !json.Valid(record.Data[:len(record.Data)-1]) {
		t.Errorf("record is not valid JSON: %q", record.Data)
	}
}

func TestNewFirehoseRejectsIncompleteConfig(t *testing.T) {
	for _, tc := range []struct {
		name string
		cfg  FirehoseConfig
	}{
		{"no stream", FirehoseConfig{Region: "us-east-2"}},
		{"no region", FirehoseConfig{StreamName: "s"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := NewFirehose(context.Background(), tc.cfg); err == nil {
				t.Error("expected an error, got nil")
			}
		})
	}
}
