# MaroonLedger

A personal finance application on AWS. Users sign in through Cognito, each
person's data is scoped to their own identity, and Claude on Bedrock categorizes
transactions, flags unusual ones, and writes a spending summary.

![Dashboard](docs/images/dashboard-overview.png)

**Go 1.25 · React 19 · PostgreSQL 16 · Terraform · ECS Fargate · GitHub Actions**

## Overview

I built this in April 2026 to learn cloud engineering by running a real system.
Infrastructure came first: seven layers of Terraform covering network, data,
compute, edge, identity and observability. The first apply created 72 resources.
A Go API went on top.

I came back in August to improve the interface. Instead I found that my own
architecture doc described a Cognito identity layer that did not exist, and that
the API was open CRUD with no authentication. Anyone who found the load balancer
could read and write every account.

The second half of the project closed that gap: token verification, per-user
scoping enforced in SQL, an AI layer with prompt injection in its threat model, a
redesigned frontend, and a streaming analytics pipeline.

More detail in `docs/`: [`whitepaper.md`](docs/whitepaper.md) is a
Well-Architected review with a cost model, [`infrastructure.md`](docs/infrastructure.md)
covers each service, [`devlog.md`](docs/devlog.md) is the build journal.

## Features

Transactions are classified into one of twelve categories on write and scored
against the account's own history. Anything unusual gets a severity and a reason.

![Anomalies](docs/images/dashboard-anomalies.png)

Insights run on demand, not on page load, because inference costs money per call.
The request sends category totals only, never individual transactions.

![Insights](docs/images/insights-analysis.png)

## Architecture

![Architecture](docs/images/architecture-core.png)

| Layer | Components |
|---|---|
| Edge | CloudFront, S3, ACM, Route 53, WAF |
| Identity | Cognito user pool, hosted UI, PKCE, JWT verification in the API |
| Network | VPC, three-tier subnets across two AZs, NAT, VPC endpoints |
| Compute | ALB, ECS Fargate, separate execution and task IAM roles |
| Data | RDS PostgreSQL, Secrets Manager, KMS |
| AI | Claude on Amazon Bedrock |
| Analytics | Kinesis Firehose, S3, Glue PySpark, Athena |
| Observability | CloudWatch alarms, SNS, CloudTrail, GuardDuty, AWS Config |

Sixteen Terraform modules across two independent stacks. The compute stack bills
by the hour and is torn down between demos. The analytics stack costs nothing
idle and stays up. They share no state, so destroying one cannot touch the other.

Every expensive component sits behind a variable that defaults to the production
value: DNS and TLS, VPC endpoints, NAT per AZ, GuardDuty, WAF, RDS Multi-AZ. The
stack still applies with all of them off.

The diagram is generated from [`docs/diagrams/`](docs/diagrams/), so updating it
is a code change. [`architecture-inventory.md`](docs/architecture-inventory.md)
maps every box to a Terraform resource.

## Design decisions

**The JWT verifier was written before Cognito was.** It takes an issuer and a
JWKS URL, nothing Cognito-specific. That let a small local identity provider
(`cmd/devidp`) sit behind the same verification path in development. There is no
`AUTH_DISABLED` flag in the server, because a bypass in the code can ship.

**Three JWT checks beyond signature and expiry**, each with a negative test.
Pinning RS256 stops `alg=none` and HMAC key confusion. Requiring
`token_use=access` stops an ID token being replayed as an API credential.
Checking `client_id` matters because a valid signature only proves the pool
minted the token, not that it minted it for this app.

**Transactions have no owner column.** Ownership comes from joining through the
account, so scoping can only be wrong in one place instead of one per table. A
foreign account ID returns 404, not 403, since a 403 confirms the ID is real.

**Model output is never trusted.** Transaction descriptions are user input that
reaches a prompt. A JSON schema constrains the model, but it is enforced across a
network call, so the category is re-validated against a closed allowlist in Go. A
test injection attempt landed as category `other`.

**Enrichment is best-effort.** Categorization and anomaly detection run under a
deadline and failures are dropped, because neither is worth failing a user's
write. Insights are the one hard dependency, and that endpoint returns 503 rather
than inventing a summary.

**The AI provider is an interface** with two implementations: Bedrock and a
deterministic stub. The stub is a stand-in, not a fallback, so the app runs with
no AWS account and the logic is testable without mocking a network service. Every
result records which provider produced it.

## Security

- Security groups chain by reference, with the ALB restricted to CloudFront's
  managed prefix list so it cannot be reached directly.
- RDS-managed master password, rotated natively. The earlier version wrote a
  Terraform-generated password into state in plaintext.
- Separate ECS execution and task roles, so application code cannot borrow the
  agent's permissions. Bedrock access is scoped to Anthropic models, not `*`.
- Per-identity rate limiting on the endpoints that cost money per call.
- User-supplied categories are rejected, not coerced, with a database CHECK
  constraint behind the allowlist.

Reasoning for each control, and the weaknesses left open, are in
[`infrastructure.md`](docs/infrastructure.md).

## Data pipeline

Committed transactions go to Kinesis Firehose, land in S3 as raw JSON, are folded
nightly into Parquet by a Glue job, and are queried from Athena. Off by default:
with `DATA_PIPELINE=off` the app builds a no-op emitter and makes no AWS calls.

The event carries six fields: id, timestamp, amount, category, AI provider,
anomaly severity. No description, account ID, user, or anomaly reason. A test
asserts those six and fails if an identifier ever appears.

Schema, cost breakdown and query examples: [`data-pipeline.md`](docs/data-pipeline.md).

## CI/CD

Two workflows in `.github/workflows`, authenticating through OIDC. No access key
exists in this repository.

**`ci.yml`** runs on every pull request and needs no credentials, so it is safe
on a fork. It formats, vets and race-tests the Go, builds the frontend with
warnings as errors, builds and Trivy-scans the image, and validates the
Terraform. One job asserts that a plain `docker build` produces the API and not
the development identity provider.

**`deploy.yml`** runs on a push to `main`. It builds with `--target server`,
scans before pushing, pushes tagged by commit SHA, registers a task definition by
editing the current one so Terraform's changes carry forward, and waits for the
rollout. The frontend job is gated on that rollout.

The ECS service has a deployment circuit breaker with rollback. I tested it by
deploying a broken image on purpose: tasks failed health checks, ECS reported
`deployment circuit breaker: rolling back`, and the service returned to the
previous revision by itself. The API kept answering throughout, because
`minimumHealthyPercent` at 100 holds the working tasks until replacements are
healthy.

The IAM role the workflows assume comes from
[MaroonLedger-Pipeline](https://github.com/RuariW12/MaroonLedger-Pipeline), which
owns the trust boundary and nothing else.

## Limitations

- **Bedrock has never run.** The sandbox account's inference quota is zero for
  every Claude model in every region. The integration is complete and exercised
  by `cmd/bedrockcheck`, but the screenshots came from the stub, which is why the
  interface names the provider on every result.
- **The deploy workflow has never run from GitHub.** The same account denies
  every `iam:*OpenIDConnect*` action, so the handshake cannot be established. I
  ran every step of it by hand against the live stack instead: it built, scanned,
  pushed, registered a task definition and rolled the service to 2/2. Only the
  credential exchange is untested.
- **Firehose was never deployed**, also blocked by policy. The lake, Glue job and
  Athena workgroup were, and the job ran nightly.
- The access token sits in `sessionStorage`. A backend-for-frontend holding it in
  an httpOnly cookie is the real fix.
- `GET /api/summary` has no rate limit. The endpoints that cost money do.
