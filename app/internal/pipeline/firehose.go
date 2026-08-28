package pipeline

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"sync/atomic"
	"time"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/firehose"
	"github.com/aws/aws-sdk-go-v2/service/firehose/types"
)

// Firehose service limits. Exceeding any of them fails the whole batch, so the
// worker flushes before it reaches them rather than discovering them at the API.
const (
	maxRecordsPerBatch = 500
	maxBatchBytes      = 4 << 20 // 4 MiB
	maxRecordBytes     = 1 << 20 // 1 MiB
)

// Tuning. The buffer is bounded on purpose: an unbounded queue in front of a
// remote service converts a delivery outage into memory exhaustion, which takes
// the API down with it. Dropping is the correct failure mode for telemetry.
const (
	defaultBufferSize = 2048
	defaultFlushEvery = 5 * time.Second
)

// FirehoseEmitter batches events onto a Kinesis Data Firehose delivery stream.
type FirehoseEmitter struct {
	client *firehose.Client
	stream string

	events chan Event
	done   chan struct{}
	wg     sync.WaitGroup

	// Counters are read only for logging, so relaxed atomics are sufficient.
	dropped   atomic.Uint64
	delivered atomic.Uint64
	failed    atomic.Uint64
}

// FirehoseConfig configures the emitter.
type FirehoseConfig struct {
	// StreamName is the Firehose delivery stream to publish to.
	StreamName string
	// Region hosting the stream.
	Region string
	// BufferSize overrides the in-process queue depth.
	BufferSize int
	// FlushInterval bounds how long a partial batch waits before delivery.
	FlushInterval time.Duration
}

// NewFirehose builds a Firehose-backed emitter and starts its delivery worker.
//
// As with the Bedrock client, no credentials are passed: the SDK resolves them
// through the default AWS chain, which is the ECS task role in AWS and the
// developer's shared credentials file locally, with no difference in code.
func NewFirehose(ctx context.Context, cfg FirehoseConfig) (*FirehoseEmitter, error) {
	if cfg.StreamName == "" {
		return nil, fmt.Errorf("pipeline: firehose stream name is required")
	}
	if cfg.Region == "" {
		return nil, fmt.Errorf("pipeline: region is required")
	}
	if cfg.BufferSize <= 0 {
		cfg.BufferSize = defaultBufferSize
	}
	if cfg.FlushInterval <= 0 {
		cfg.FlushInterval = defaultFlushEvery
	}

	awsCfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(cfg.Region))
	if err != nil {
		return nil, fmt.Errorf("pipeline: load AWS config: %w", err)
	}

	e := &FirehoseEmitter{
		client: firehose.NewFromConfig(awsCfg),
		stream: cfg.StreamName,
		events: make(chan Event, cfg.BufferSize),
		done:   make(chan struct{}),
	}

	e.wg.Add(1)
	go e.run(cfg.FlushInterval)

	return e, nil
}

func (e *FirehoseEmitter) Name() string { return "firehose" }

// Emit queues an event, or drops it if the buffer is full.
//
// The non-blocking send is the whole point. This runs on the HTTP write path,
// and a delivery stream that is throttling must not become latency on a user's
// request -- let alone a deadlock if the worker is wedged.
func (e *FirehoseEmitter) Emit(event Event) {
	select {
	case e.events <- event:
	default:
		// Counted rather than logged per-event: under sustained backpressure
		// per-event logging is itself a load problem. The worker reports the
		// running total.
		e.dropped.Add(1)
	}
}

// Close stops accepting events and flushes what is queued, bounded by ctx.
func (e *FirehoseEmitter) Close(ctx context.Context) error {
	close(e.done)

	finished := make(chan struct{})
	go func() {
		e.wg.Wait()
		close(finished)
	}()

	select {
	case <-finished:
	case <-ctx.Done():
		return ctx.Err()
	}

	log.Printf("pipeline: delivered=%d failed=%d dropped=%d",
		e.delivered.Load(), e.failed.Load(), e.dropped.Load())
	return nil
}

// run owns the batch. Everything that touches the pending slice happens here,
// on one goroutine, so no locking is needed around it.
func (e *FirehoseEmitter) run(flushEvery time.Duration) {
	defer e.wg.Done()

	ticker := time.NewTicker(flushEvery)
	defer ticker.Stop()

	pending := make([]types.Record, 0, maxRecordsPerBatch)
	pendingBytes := 0

	flush := func() {
		if len(pending) == 0 {
			return
		}
		// A fresh context per flush: the worker outlives any single request,
		// and a flush must not inherit a cancelled request's deadline.
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		e.deliver(ctx, pending)
		cancel()

		pending = pending[:0]
		pendingBytes = 0
	}

	for {
		select {
		case event := <-e.events:
			record, size, err := encode(event)
			if err != nil {
				log.Printf("pipeline: encode event %d: %v", event.ID, err)
				e.dropped.Add(1)
				continue
			}
			// Flush before appending when this record would breach a limit,
			// so the batch that goes out is always inside them.
			if len(pending) >= maxRecordsPerBatch || pendingBytes+size > maxBatchBytes {
				flush()
			}
			pending = append(pending, record)
			pendingBytes += size

		case <-ticker.C:
			flush()

		case <-e.done:
			// Drain whatever is still queued before exiting, so a graceful
			// shutdown does not discard events that were already accepted.
			for {
				select {
				case event := <-e.events:
					record, size, err := encode(event)
					if err != nil {
						e.dropped.Add(1)
						continue
					}
					if len(pending) >= maxRecordsPerBatch || pendingBytes+size > maxBatchBytes {
						flush()
					}
					pending = append(pending, record)
					pendingBytes += size
				default:
					flush()
					return
				}
			}
		}
	}
}

// deliver sends one batch and accounts for partial failure.
//
// PutRecordBatch returns 200 with a per-record failure count, so checking only
// the error misses rejected records entirely.
func (e *FirehoseEmitter) deliver(ctx context.Context, records []types.Record) {
	out, err := e.client.PutRecordBatch(ctx, &firehose.PutRecordBatchInput{
		DeliveryStreamName: &e.stream,
		Records:            records,
	})
	if err != nil {
		e.failed.Add(uint64(len(records)))
		log.Printf("pipeline: %v: put %d records: %v", ErrUnavailable, len(records), err)
		return
	}

	failed := 0
	if out.FailedPutCount != nil {
		failed = int(*out.FailedPutCount)
	}
	if failed > 0 {
		// Not retried on purpose. A retry queue in front of best-effort
		// telemetry is a source of unbounded growth and duplicate rows in the
		// lake; Firehose already retries internally toward S3.
		e.failed.Add(uint64(failed))
		log.Printf("pipeline: %d of %d records rejected by firehose", failed, len(records))
	}
	e.delivered.Add(uint64(len(records) - failed))
}

// encode renders one event as a newline-terminated JSON record.
//
// The trailing newline is what makes the delivered S3 objects newline-delimited
// JSON; without it Firehose concatenates records and neither Glue nor Athena
// can find the record boundaries.
func encode(event Event) (types.Record, int, error) {
	data, err := json.Marshal(event)
	if err != nil {
		return types.Record{}, 0, err
	}
	data = append(data, '\n')

	if len(data) > maxRecordBytes {
		return types.Record{}, 0, fmt.Errorf("record is %d bytes, over the %d limit", len(data), maxRecordBytes)
	}
	return types.Record{Data: data}, len(data), nil
}
