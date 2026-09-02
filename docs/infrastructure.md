# Infrastructure

What MaroonLedger deploys, and why each choice was made. Everything here exists
in `infrastructure/`. Where a component is optional or off by default, that is
stated.

The diagrams are in [`../README.md`](../README.md) and
[`data-pipeline.md`](data-pipeline.md).
[`architecture-inventory.md`](architecture-inventory.md) maps every box on them to
a resource. [`whitepaper.md`](whitepaper.md) covers the same system as a
Well-Architected review with a cost model.

## Defaults

Several components cost real money and are off by default. The stack applies and
runs without any of them.

| Variable | Default | Effect when enabled |
|---|---|---|
| `domain_name` | `""` | Route 53 zone, two ACM certificates, HTTPS on the ALB, custom domain on CloudFront |
| `create_vpc_endpoints` | `false` | Seven interface endpoints plus an S3 gateway endpoint |
| `single_nat_gateway` | `true` | `false` gives one NAT per AZ, removing a single point of failure |
| `cognito_advanced_security_mode` | `"OFF"` | Compromised-credential detection, billed per MAU |
| `ai_provider` | `"bedrock"` | Attaches the Bedrock policy to the task role; `"stub"` attaches nothing |
| `data_pipeline` | `"off"` | `"firehose"` emits analytics events and attaches the Firehose policy |
| `bedrock_api` | `"mantle"` | `"runtime"` uses the classic bedrock-runtime endpoint |
| `alert_email` | `""` | Email subscription to the alerts topic |

Five more default to the production-correct value and are turned off only in the
gitignored tfvars, because the sandbox account forbids them rather than merely
charging for them.

| Variable | Default | Why it gets overridden |
|---|---|---|
| `enable_waf` | `true` | An SCP denies WAF at CloudFront scope |
| `enable_guardduty` | `true` | An SCP denies GuardDuty |
| `rds_multi_az` | `true` | Not available on the free tier |
| `rds_backup_retention_days` | `7` | Capped on the free tier |
| `alb_ingress_ports` | `[80]` | CloudFront's managed prefix list consumes about 55 of the 60 rules-per-security-group quota, leaving room for one ingress rule |

Defaulting these to on and overriding locally is intentional. The repository should
describe the architecture I would deploy, not the one a sandbox permitted.

---

## Layer 1: Edge

**Route 53 and ACM** are inert until `domain_name` is set, which is what lets the
stack apply without a registered domain. With a domain, two certificates are
issued: one in the stack's region for the ALB, one in `us-east-1` because
CloudFront only accepts certificates from there.

The apex uses an alias record, not a CNAME. An alias resolves directly to the
distribution with no second lookup, is not billed per query, and can be attached
to the zone apex, which a CNAME cannot.

**CloudFront** is the single public entry point. It serves the React bundle from a
private S3 origin using Origin Access Control, and routes `/api/*` to the ALB
through a path-based cache behavior.

Two details matter more than they look. The API behavior forwards the
`Authorization` header; without it the bearer token never reaches the API and every
request is rejected, and including it in the cache key keeps one user's responses
out of another's cache. The API behavior also pins all three TTLs to zero.
CloudFront otherwise applies a 24-hour default, which would serve stale balances
and keep serving a user's data from the edge after they signed out.

One distribution serves both origins: a unified domain, edge caching for static
assets, a single attachment point for WAF, and Shield Standard at no cost.

**WAF** attaches at CloudFront scope with AWS managed rule groups and a per-IP rate
limit. It is gated behind `enable_waf` and denied by SCP in the deployment account.

## Layer 2: Identity

**Cognito** provides a user pool, a hosted UI, and JWT issuance. The frontend runs
an authorization code flow with PKCE, correct for a public client that cannot keep
a secret.

The pool sets `prevent_user_existence_errors` so a wrong username and a wrong
password return the same error, and restricts auth flows to SRP, which keeps
passwords off the wire. MFA is TOTP only: SMS is the weakest common second factor
because of SIM-swap attacks, and it carries a per-message cost.

The API validates tokens against the pool's JWKS endpoint. That verifier was
written against an issuer and a JWKS URL, not against Cognito, which is what allows
`cmd/devidp` to sit behind the same code path in local development. There is no
authentication bypass flag in the server, because a bypass in the code can ship.

## Layer 3: Networking

A single VPC in `us-east-2` with a `10.0.0.0/16` CIDR, giving far more addresses
than needed and room for subnet growth without renumbering.

Three subnet tiers across two availability zones. Public subnets hold the ALB and
NAT gateway. Private application subnets hold the Fargate tasks, which have no
public IPs. Private data subnets hold RDS and have no route to the internet in
either direction.

The Internet Gateway carries public traffic to and from the ALB. A NAT Gateway lets
tasks make outbound connections, such as pulling packages or reaching AWS APIs not
covered by an endpoint, without being reachable from outside. One NAT is the
default; `single_nat_gateway = false` gives one per AZ, which removes a single
point of failure at roughly double the cost.

**VPC endpoints** are off by default and are the most expensive optional component
in the stack. Interface endpoints bill hourly per endpoint per availability zone,
so seven endpoints across two zones is fourteen billable attachments at a cent an
hour, about $102 a month at list price. That is more than the entire rest of the
deployed stack. They are correct to enable where NAT data processing charges exceed
that fixed cost, which is a far higher volume than this application produces. The
S3 gateway endpoint is free and always created with the others.

## Layer 4: Compute

**The Application Load Balancer** is one regional resource with subnets in both
availability zones. With a certificate it terminates TLS on 443 using
`ELBSecurityPolicy-TLS13-1-2-2021-06` (TLS 1.2 floor, 1.3 enabled) and redirects
port 80. Without one it serves HTTP on port 80 only.

An ALB rather than an NLB, for path-based routing, native ECS integration, and
health-check-driven traffic shaping, none of which an NLB provides.

**ECS Fargate** runs two tasks at 0.25 vCPU and 512 MB, the smallest configuration
Fargate offers and generous for a Go binary at this request rate.

IAM is split into two roles on purpose. The **execution role** is used by the ECS
agent before the container starts: pulling the image, creating log streams, and
resolving the database secret. The **task role** is what application code runs as,
and it is the only one that can reach Bedrock. Application code therefore cannot
borrow the agent's permissions.

The service carries a deployment circuit breaker with rollback and a sixty-second
health check grace period. Without it, a revision whose tasks never pass health
checks is retried indefinitely while the service sits at reduced capacity. With it,
ECS reverts to the last revision that reached steady state, and the pipeline's wait
step turns that into a failed build.

## Layer 5: Data

**RDS PostgreSQL 16** on a `db.t4g.micro` with 20 GB of gp3 storage that autoscales
to 100 GB, encrypted at rest with a customer-managed KMS key.

The master password is managed and rotated by RDS. An earlier version generated it
in Terraform, which wrote it into state in plaintext.

`recovery_window_in_days = 0` on the secret so it deletes immediately instead of
sitting in a 30-day recovery window, without which a re-apply fails on a name
collision.

**S3** buckets: the frontend bundle, readable only by CloudFront through Origin
Access Control; CloudTrail log delivery; and AWS Config snapshot delivery. All
block public access and encrypt at rest.

**Secrets Manager** holds the database credentials. Only the ECS execution role can
read them, and only at task start.

## Layer 6: AI

**Bedrock** is reached at runtime by the task role. The IAM policy is scoped to
Anthropic foundation models and to inference profiles in this account, not
`Resource: "*"`, and is created only when `ai_provider = "bedrock"`.

The region wildcard in that policy is intentional. A `us.` inference profile routes
requests across several US regions, and IAM is evaluated against the underlying
foundation model in whichever region serves it, so pinning one region fails
intermittently. The wildcard covers region only and grants nothing beyond Anthropic
models.

**Data minimization.** Insight generation sends aggregated category totals only,
never individual descriptions, account names, or identifiers. Anomaly detection
sends per-category aggregates as the baseline and one transaction description as
the subject.

**Prompt injection** is in the threat model, since descriptions are user input that
reaches a prompt. The control is not the system prompt's wording. A JSON schema
constrains the model, but it is enforced across a network call, so the returned
category is re-validated against a closed allowlist in Go before storage.

## Layer 7: Observability

**CloudWatch** holds application logs at thirty-day retention and five alarms: ALB
5xx and unhealthy hosts, and database CPU, storage and connection count. The ALB
alarms set `treat_missing_data = "notBreaching"`, because "no errors" reports as no
data rather than zero, and without it the alarm sits permanently in
`INSUFFICIENT_DATA` while the service is healthy.

**CloudTrail** records management events to a dedicated bucket with log file
validation enabled.

**GuardDuty** findings route to SNS through an EventBridge rule that extracts
severity, type, region and description. Low-severity informational findings are
filtered out, because an alert channel that is mostly noise stops being read.

**AWS Config** records resource configuration history.

**KMS** provides a customer-managed key for RDS encryption at rest. Customer-managed
rather than the AWS-managed default, for control over key policy, rotation cadence
and cross-account access.

## Layer 8: Analytics

Kinesis Firehose to an S3 lake, a nightly Glue PySpark job producing partitioned
Parquet, and Athena over the result using partition projection instead of a
crawler.

It lives in its own root module with its own state key, sharing no
`terraform_remote_state` with the compute stack. That separation is the point: the
compute stack carries the hourly cost floor and is destroyed between demos, while
the lake costs nothing idle. Neither holds a record that the other exists.

The event carries six fields and excludes the description, account ID, owning user,
and anomaly reason, the same data-minimization posture as the Bedrock integration.

Full detail is in [`data-pipeline.md`](data-pipeline.md).

---

## Security model

No single control is trusted on its own.

**Network isolation.** Each tier admits only the tier above it, referencing
security groups by ID instead of CIDR so rules survive addressing changes.
CloudFront is the one tier that cannot be chained this way, since it does not live
in the VPC and has no security group, so the ALB is restricted to CloudFront's
AWS-managed prefix list instead.

**Identity.** Token verification checks three things beyond signature and expiry,
each with a negative test:

1. **RS256 pinned**, blocking the `alg=none` and HMAC key-confusion families.
2. **`token_use = "access"` required**, so an ID token issued for the frontend's
   own use cannot be replayed as an API credential.
3. **`client_id` checked**, because a valid signature only proves the pool minted
   the token, not that it minted it for this application.

**Per-user scoping** is enforced in the query. Accounts carry the owner's Cognito
`sub` and every read filters on it. Transactions have no owner of their own;
ownership is established by joining through the account, so guessing an account ID
cannot reach another user's data. A foreign account returns 404, not 403, because a
403 confirms the identifier is real.

**Data protection.** Encryption at rest everywhere: RDS under a customer-managed
key, S3 and the analytics lake under SSE-S3. TLS in transit, with `DB_SSLMODE`
required on the database connection.

**Application hardening.** Security headers on every API response: nosniff, frame
denial, `no-referrer`, `no-store` and HSTS. A per-identity rate limiter caps the
model-backed endpoints, which is the dimension that maps to spend; WAF's per-IP
limit does not. User-supplied categories are rejected, not coerced, with a database
CHECK constraint behind the allowlist.

The frontend holds its access token in `sessionStorage`, which any script on the
page can read. This is the most significant known weakness in the stack. It is
documented in `app/frontend/src/auth.js` and closes the moment a
backend-for-frontend holds the token in an httpOnly cookie.

---

## Deliberately not implemented

An architecture document that only lists what exists is half a document.

- **A backend-for-frontend for token storage.** The right upgrade if this ever
  holds real money.
- **Integration tests against a real Postgres.** The netting bug in the category
  aggregation was a SQL defect no unit test could catch. A handful of handler tests
  against a real database is the highest-value testing work outstanding.
- **A rate limit on `GET /api/summary`.** The endpoints that cost money per call
  are limited. This one is a plain database aggregate and is not, which is a gap
  rather than a decision.
- **Container Insights and APM tracing.** Metrics and logs cover the failure modes
  one service with one database actually has. Tracing earns its cost with more than
  one service.
- **Organization-wide CloudTrail.** Single-account project; extending the trail is
  configuration, not redesign.
- **WAF logging to Firehose, and ALB access logs.** Sampled requests and CloudWatch
  metrics cover behavior at this traffic level.
- **Terratest or equivalent.** Nothing tests the Terraform beyond `validate`.
