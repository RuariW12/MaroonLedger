# Data pipeline

A streaming analytics layer alongside the transactional database. Committed
transactions go to Kinesis Firehose, land in S3 as raw JSON, are folded nightly
into Parquet by a Glue PySpark job, and are queried from Athena.

It is off by default. With `DATA_PIPELINE=off` the application builds a no-op
emitter: no AWS calls, no credentials needed, no cost. Enabling it is explicit,
the same posture as the AI provider.

![Data pipeline](images/architecture-data-pipeline.png)

The database write happens first and the emit is asynchronous behind a bounded
channel. If the buffer is full the event is dropped instead of blocking the
request. Analytics telemetry is not worth slowing a user's transaction, and
certainly not worth failing one.

## Event schema

One event per committed transaction, carrying only these fields:

| Field | Type | Notes |
|---|---|---|
| `id` | `bigint` | Transaction primary key |
| `timestamp` | `string` (RFC 3339) | When the transaction occurred, not when ingested |
| `amount` | `double` | Signed; negative is money leaving |
| `category` | `string` | From the closed set in `internal/ai` |
| `ai_provider` | `string` | `bedrock`, `stub`, or omitted |
| `anomaly_severity` | `string` | `none` / `low` / `medium` / `high`, or omitted |

Not emitted: the free-text description, the account ID, the owning user, and
`anomaly_reason`. The analytics layer needs shape and magnitude, not the merchant
name or who spent it.

A test in `internal/pipeline` asserts the event has exactly six fields and fails if
a description or account identifier appears. That stops a future "just add the
description, it would help with grouping" from quietly turning an aggregate store
into a store of personal data.

In the curated table `event_date` and `category` are partition keys, encoded in the
S3 key instead of stored in the Parquet files.

## Enabling it

Two stacks, applied in order. The data stack is independent and safe to leave
running. The compute stack is the destroyable one.

```bash
# 1. Data stack: serverless, no idle cost
cd infrastructure/environments/data
terraform init && terraform apply

# 2. Wire the outputs into the compute stack
cd ../dev
terraform apply \
  -var 'data_pipeline=firehose' \
  -var "data_pipeline_stream_arn=$(terraform -chdir=../data output -raw firehose_stream_arn)" \
  -var "data_pipeline_stream_name=$(terraform -chdir=../data output -raw firehose_stream_name)"
```

The outputs are wired by hand, not through `terraform_remote_state`. Reading the
other stack's state would couple them, and coupling is what must not exist if
destroying the compute stack is to leave the lake untouched.

| Variable | Default | Effect |
|---|---|---|
| `DATA_PIPELINE` | `off` | `firehose` enables emission |
| `DATA_PIPELINE_STREAM` | none | Delivery stream name; required when enabled |

To turn it off, re-apply with `-var 'data_pipeline=off'`. The task role loses its
Firehose permission and the app reverts to the no-op emitter.

## Destroy and redeploy

```bash
cd infrastructure/environments/dev
terraform destroy          # the lake, catalog and stream are untouched
terraform apply            # later; historical data was queryable throughout
```

The data stack survives because the compute stack has no record of it to destroy.
Athena keeps answering while compute is down.

## Cost

Nothing in the data stack bills while idle.

| Service | Idle | Charged on |
|---|---|---|
| Firehose (Direct PUT) | $0 | GB ingested |
| S3 lake | $0 empty | GB stored |
| Glue job | $0 | DPU-second while running, about 2 min/night |
| Glue Data Catalog | $0 | First million objects free |
| Athena | $0 | $5/TB scanned, capped at 1 GiB per query |
| EventBridge Scheduler | $0 | Per invocation, about 30/month |

The choices behind that:

- **Firehose, not Kinesis Data Streams.** Data Streams bills per shard-hour whether
  or not anything is written, roughly $11/month per shard as a floor. Direct PUT
  has no floor.
- **No Glue crawler.** Partition projection describes the layout deterministically,
  so nothing has to run for a new day to become queryable.
- **Timestamp-prefix partitioning, not Dynamic Partitioning.** The paid feature
  extracts a key from record content that the free timestamp namespace already
  provides for ingest date.
- **SSE-S3, not the RDS customer-managed key.** KMS bills per request and a Glue run
  issues a decrypt per object, against data that holds no descriptions or
  identifiers.
- **Lifecycle rules.** Raw expires at 30 days, curated moves to Standard-IA at 90,
  Athena results expire at 30.
- **A 1 GiB per-query scan cap**, enforced at the workgroup so a client cannot
  override it. One careless `SELECT *` fails instead of scanning the lake.

Excluded on cost grounds: Redshift, MSK, SageMaker endpoints, Glue crawlers,
QuickSight.

## Querying

```sql
-- Partition-pruned: reads only the last 30 days of partitions.
SELECT category, count(*) AS txns, round(sum(amount), 2) AS net
FROM maroon_ledger_analytics.transactions
WHERE event_date >= current_date - interval '30' day
GROUP BY category
ORDER BY abs(sum(amount)) DESC;
```

Always filter on `event_date`. Without it Athena scans every partition, which is
what the scan cap exists to stop.

## The Glue job's one gotcha

`transactions_etl.py` originally called `sys.exit(0)` when the bookmark found no new
records. Glue treats any `SystemExit` as a job failure, so a night with no new
transactions was reported FAILED. The job now branches and reaches a single
`job.commit()` on both paths.
