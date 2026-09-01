# Infrastructure

A service-by-service account of what MaroonLedger deploys, why each choice was
made, and what was deliberately left out.

Everything described here exists in `infrastructure/`. Where a component is
optional or disabled by default, that is stated explicitly — this document is
meant to survive someone reading it with the Terraform open next to it.

**Defaults at a glance.** Several components cost real money and are therefore
off by default. The stack applies and runs without any of them:

| Variable | Default | Effect when enabled |
|---|---|---|
| `domain_name` | `""` | Route 53 zone, two ACM certificates, HTTPS on the ALB, custom domain on CloudFront |
| `create_vpc_endpoints` | `false` | Seven interface endpoints + S3 gateway endpoint (~$50/month) |
| `single_nat_gateway` | `true` | `false` gives one NAT Gateway per AZ (+~$32/month, removes an SPOF) |
| `cognito_advanced_security_mode` | `"OFF"` | Compromised-credential detection and adaptive auth (billed per MAU) |
| `ai_provider` | `"bedrock"` | Bedrock IAM policy on the task role; `"stub"` attaches nothing |
| `alert_email` | `""` | Email subscription to the alerts topic |
| `data_pipeline` | `"off"` | `"firehose"` emits analytics events and attaches the Firehose policy to the task role |
| `bedrock_api` | `"mantle"` | Which Bedrock API surface to call; `"runtime"` uses the classic bedrock-runtime endpoint |

Three more default to the production-correct value and are turned *off* only in
the gitignored tfvars, because the sandbox account this was deployed into
forbids them outright rather than merely charging for them:

| Variable | Default | Why it gets overridden |
|---|---|---|
| `enable_waf` | `true` | An SCP denies WAF at CloudFront scope |
| `enable_guardduty` | `true` | An SCP denies GuardDuty entirely |
| `rds_multi_az` | `true` | Not available on the free tier |
| `rds_backup_retention_days` | `7` | Capped on the free tier |
| `alb_ingress_ports` | `[80]` | CloudFront's managed prefix list consumes ~55 of the 60 rules-per-security-group quota, so only one ingress rule fits |

Defaulting these to on and overriding them locally is deliberate. The repository
should describe the architecture I would deploy, not the one a particular
sandbox permitted.

---

## Layer 1: DNS & Edge

The public entry point: resolving the domain, serving content from edge
locations, and filtering malicious traffic before it reaches the VPC.

### Amazon Route 53 & AWS Certificate Manager

**Status.** Implemented in `modules/dns`, inert until `domain_name` is set.

**Role.** Route 53 hosts the zone and resolves the apex to the CloudFront
distribution through an alias record. ACM issues the certificates.

Two certificates are required, because they live in different places:

- The **CloudFront certificate must be in `us-east-1`**, whatever region the
  rest of the stack runs in. This is a CloudFront constraint, not a preference,
  and is why the environment declares a second aliased AWS provider.
- The **ALB certificate must be in the ALB's own region** (`us-east-2`).

Both cover the same name and validate through the same hosted zone.

**Why alias records.** An alias resolves directly to the distribution with no
second lookup, is not billed per query, and can be attached to the zone apex —
which a CNAME cannot.

**Why the whole layer is optional.** Certificates cannot be issued for a domain
you do not control, so hardcoding this would make the stack un-appliable for
anyone without a registered domain. Gating it on one variable keeps the code
present and reviewable while leaving the stack deployable today.

**Implementation note.** The apex alias record is defined in the environment
rather than inside the `dns` module. CloudFront needs the certificate the module
issues, so the module cannot in turn depend on CloudFront's outputs without
creating a dependency cycle.

### Amazon CloudFront

**Status.** Implemented in `modules/cdn`.

**Role.** The single public entry point. It serves the React bundle from a
private S3 origin using Origin Access Control, and routes `/api/*` to the ALB
origin through a path-based cache behaviour.

**Two details that matter more than they look.**

The API behaviour forwards the `Authorization` header. Without it the bearer
token never reaches the API and every request is rejected. Including it in the
cache key also keeps one user's responses out of another's cache.

The API behaviour pins `min_ttl`, `default_ttl` and `max_ttl` to `0`. CloudFront
otherwise applies a 24-hour default TTL, which would serve stale account
balances and — worse — keep serving a user's data from the edge after they
signed out.

**Why one distribution for both origins.** A unified domain, edge caching for
static assets, a single attachment point for WAF, and Shield Standard included
at no cost.

### AWS WAF

**Status.** Implemented, attached to the distribution.

**Rules, in evaluation order.** A rate limit of 2,000 requests per 5 minutes per
IP, then the AWS managed Common, SQLi, Known Bad Inputs, and Amazon IP
Reputation rule groups.

**Why at the edge.** Attacks are rejected closer to the source, and CloudFront's
caching reduces how many requests reach evaluation at all. It layers with Shield
Standard for volumetric protection.

---

## Layer 2: Identity

### Amazon Cognito

**Status.** Implemented in `modules/cognito`.

**Role.** A user pool handles sign-up, sign-in, password reset and MFA
enrolment through the hosted UI, and issues JWTs. The frontend attaches the
access token to API calls; ECS tasks verify it against the pool's JWKS endpoint
on every request.

**Configuration that is load-bearing rather than cosmetic:**

- **`prevent_user_existence_errors = "ENABLED"`.** Without it Cognito returns
  distinguishable errors for registered and unknown email addresses, which
  allows an attacker to enumerate users.
- **`ALLOW_USER_PASSWORD_AUTH` is excluded** from the client's auth flows,
  forcing SRP. Password-based auth transmits the plaintext password to the
  Cognito API; SRP proves knowledge of it without sending it.
- **No client secret.** The client runs in a browser and cannot keep one, so the
  authorization-code flow is secured with PKCE instead.
- **TOTP MFA only.** SMS is deliberately not offered — SIM-swap attacks make it
  the weakest common second factor, and it carries a per-message cost.
- **A 12-character password policy** requiring all four character classes.
- **Token revocation enabled**, so signing out invalidates the refresh token
  rather than leaving it valid until expiry.

**Threat protection is off by default.** Compromised-credential detection and
adaptive authentication are a paid Cognito tier billed per monthly active user.
The variable exists and `ENFORCED` is the correct setting for anything holding
real data; `OFF` is the honest default for a portfolio environment.

**Why Cognito.** It removes password hashing, session storage, MFA enrolment,
token rotation and account recovery from the codebase, and the hosted UI removes
the need to implement the SRP flow in the frontend.

**How this is developed against locally.** The API validates an RS256 token
against a JWKS URL; it has no knowledge of Cognito specifically. Locally that
URL points at `app/cmd/devidp`, a small identity provider that mints tokens for
any username. This is why there is **no authentication bypass flag in the
server** — a bypass that exists in the code is a bypass that can ship. The
authenticated request path is identical in both environments.

---

## Layer 3: Networking

### VPC & Regional Layout

A single VPC in `us-east-2` with a `10.0.0.0/16` CIDR — 65,536 addresses, far
more than needed, leaving room for subnet growth without renumbering.

### Subnet Tiers

Three tiers, each spanning two Availability Zones, all `/24` (251 usable
addresses each):

| Tier | CIDRs | Contents |
|---|---|---|
| Public | `10.0.101.0/24`, `10.0.102.0/24` | ALB, NAT Gateway |
| Private-app | `10.0.1.0/24`, `10.0.2.0/24` | ECS tasks, VPC endpoint ENIs |
| Private-data | `10.0.201.0/24`, `10.0.202.0/24` | RDS primary and standby |

**Why this enforces anything.** The tier separation is real because of the route
tables, not the names. The private-data route table has **no `0.0.0.0/0` entry
at all**, which is what actually makes the database tier unable to reach the
internet in either direction. Subnet labels are documentation; the absence of a
default route is enforcement.

### Internet Gateway & NAT Gateways

The IGW carries public traffic to and from the ALB. A NAT Gateway lets ECS tasks
make outbound connections — pulling packages, reaching AWS APIs not covered by
an endpoint — without being reachable from outside.

**One NAT Gateway is shared across both AZs by default.** At roughly $32/month
each, a second NAT Gateway is the single largest avoidable cost in this stack.
Sharing one means an AZ failure takes out egress for both private subnets and
adds a cross-AZ data transfer charge. That is the wrong trade for production and
a reasonable one for a portfolio environment, so it is a variable
(`single_nat_gateway`) rather than a hardcoded choice.

### VPC Endpoints

**Status.** Implemented in `modules/vpc-endpoints`, disabled by default.

Interface endpoints for ECR (API and Docker), CloudWatch Logs, Secrets Manager,
SSM, SSM Messages, and Bedrock Runtime, plus a Gateway endpoint for S3.

**Why they are worth having.** Secret retrieval and image pulls never traverse
the public internet; NAT data-processing charges disappear for that traffic; and
the tasks keep working if the NAT Gateway or its AZ fails. The S3 gateway
endpoint is specifically required for image pulls to work without NAT, because
ECR stores layers in S3.

**Why they are off by default.** Interface endpoints bill hourly per endpoint
per AZ. Seven endpoints across two AZs is roughly $50/month — more than the rest
of the stack combined at this scale. The Gateway endpoint is free; only the
interface endpoints carry the cost.

---

## Layer 4: Compute

### Application Load Balancer

Deployed across both public subnets. Health checks on `/health` every 30 seconds
determine which tasks receive traffic.

**With a certificate** (i.e. `domain_name` set) it terminates TLS on 443 using
`ELBSecurityPolicy-TLS13-1-2-2021-06` — TLS 1.2 floor, 1.3 enabled — and port 80
issues a 301 redirect. **Without one** it serves HTTP on port 80 only.

Either way, the ALB security group admits traffic **only from CloudFront's
managed origin-facing prefix list**. This is the control that stops someone
resolving the ALB's public DNS name and bypassing the WAF entirely; without it,
edge protection is decorative.

**Why an ALB rather than an NLB.** Path-based routing, native ECS integration,
and health-check-driven traffic shaping — none of which a Network Load Balancer
provides.

### Elastic Container Service on Fargate

**Status.** Implemented in `modules/ecs`. Fargate launch type, two tasks,
256 CPU units / 512 MB each, `awsvpc` networking in the private-app subnets.

**Why Fargate rather than EC2 with an Auto Scaling Group.** This is a real
trade, and the honest reasoning is:

- There is no host layer to patch, harden or replace. On EC2 the ECS-optimised
  AMI is the team's responsibility to keep current; that is a standing
  operational cost for a two-task workload.
- Billing is per-task, not per-instance. An EC2 cluster sized for two small
  tasks either wastes most of an instance or leaves no headroom to place a
  replacement task during a deployment.
- `awsvpc` gives each task its own ENI and security group membership, so the
  ECS→RDS security group chain describes tasks rather than the hosts they
  happen to land on.

EC2 with an ASG earns its complexity when you need specific instance types, GPU
or local NVMe, Reserved or Spot pricing at scale, or per-host daemon containers.
None apply here. The capacity-management skills that launch type demonstrates
are real, but choosing it for this workload would be justifying infrastructure
by what it teaches rather than what it needs.

**IAM: two roles, deliberately.** The **execution role** is used by the ECS
agent before the container starts — pulling the image, creating log streams,
resolving the database secret. The **task role** is what application code
assumes at runtime, and holds the Bedrock permissions. Keeping them separate
means application code cannot borrow the agent's permissions. Merging them is a
common and rarely-noticed mistake.

**Configuration vs. secrets.** Non-sensitive values (region, AI provider, auth
issuer, JWKS URL, client ID, database host/port/name) are passed as plain
`environment` entries. The database credentials are passed via `secrets`, which
resolves from Secrets Manager at task start and never appears in the task
definition or in `describe-task-definition` output.

The Cognito **client ID is not a secret** and is treated as configuration. It
identifies the application and ships inside the frontend bundle; it is an
audience check, not a credential.

---

## Layer 5: Data

### Amazon RDS (PostgreSQL 16)

Multi-AZ `db.t4g.micro`, 20 GB scaling to 100 GB, in the private-data subnets,
reachable only from the ECS security group.

Storage and automated backups are encrypted with the customer-managed KMS key.
Backups are retained for 7 days. PostgreSQL and upgrade logs are exported to
CloudWatch so they survive instance replacement.

**Master credentials are managed by RDS**, not by Terraform. This replaced an
earlier approach that generated the password with `random_password` and wrote it
into a Secrets Manager secret. That had two problems: **the password was stored
in Terraform state in plaintext**, and rotating it would have required deploying
a rotation Lambda inside the VPC. RDS-managed passwords rotate natively on a
30-day cycle with no additional infrastructure, and nothing in the Terraform ever
sees the value.

The consequence is that the managed secret contains only `username` and
`password`. Host, port and database name are not secret and reach the
application as ordinary environment variables; the application merges whichever
fields the secret actually provides.

**Why Multi-AZ.** Synchronous replication to a standby in the second AZ, with
AWS handling DNS cutover on failover. **Why PostgreSQL.** JSONB, strong
constraint support, and exact `DECIMAL` arithmetic, which matters for money.

### Amazon S3

Three buckets, all with public access blocked:

- **Frontend** — the React bundle, readable only by CloudFront through Origin
  Access Control.
- **CloudTrail** — audit log delivery.
- **AWS Config** — configuration snapshot delivery.

**Why S3 behind CloudFront for static assets.** It separates static delivery
from the application tier, offloads traffic to the edge, and costs a fraction of
serving the same files from ECS.

### AWS Secrets Manager

Holds the RDS master credentials, encrypted with the customer-managed KMS key
and retrieved by the ECS execution role at task start. The task role's policy
scopes access to that specific secret ARN.

**Why this rather than environment variables or a baked-in config file.**
Credentials stay out of source control, out of container images, and out of
`describe-task-definition`, and every access is recorded in CloudTrail.

---

## Layer 6: AI

### Amazon Bedrock

**Status.** Implemented in `app/internal/ai`, with IAM in `modules/ecs`.

**Role.** Claude on Bedrock powers three features: transaction categorisation,
anomaly assessment, and spending insight generation.

**How credentials work.** The application uses the Anthropic SDK's Bedrock
client, which resolves credentials through the default AWS chain. That means the
**ECS task role in AWS and the developer's shared credentials file locally, with
no difference in code**.

**IAM scope.** `bedrock:InvokeModel` and `InvokeModelWithResponseStream`,
restricted to Anthropic foundation models in-region and to inference profiles in
this account — not `Resource: "*"`. The policy is only created when the service
is actually configured for Bedrock.

**Why there is a second implementation.** `ai.Provider` has two
implementations: `Bedrock`, and a deterministic local `Stub` that uses keyword
matching and arithmetic. The application never branches on which is in use. This
means the AI surfaces are fully functional with no AWS account and no inference
spend, and it makes the behaviour testable without mocking a network service.
The provider that produced each result is recorded on the row, so stub output is
never mistaken for real inference.

`AI_PROVIDER` defaults to `stub`, so a misconfiguration cannot silently start
billing.

**Data minimisation.** Insight generation sends **only aggregated category
totals** — never individual transaction descriptions, account names, or
identifiers. Anomaly detection sends per-category aggregates as the baseline
rather than the rows themselves. The categorisation path is the only one that
sends a raw description, and it sends exactly one, truncated to 200 characters.

---

## Layer 7: Observability & Operations

Nothing in this layer sits in the traffic path; it observes, records and alerts.

### Amazon CloudWatch

Container logs ship via the `awslogs` driver to a log group with 30-day
retention. Five alarms publish to the alerts topic:

| Alarm | Condition | Why |
|---|---|---|
| ALB 5xx | >10 in 5 min | Closest signal to "the site is broken" |
| Healthy target count | <1 for 2 min | Service is down even though the ALB is fine |
| RDS CPU | >80% for 10 min | Saturation before it becomes timeouts |
| RDS connections | >150 for 10 min | Pool exhaustion before writes fail |
| RDS free storage | <2 GB | Storage exhaustion is unrecoverable in place |

The ALB alarms set `treat_missing_data = "notBreaching"`, because "no errors"
reports as no data rather than zero — without it the alarm sits permanently in
`INSUFFICIENT_DATA` while the service is healthy.

### AWS CloudTrail

A trail with log file validation enabled, delivering to a dedicated S3 bucket.
CloudTrail is what makes incident response possible at all: without it there is
no way to reconstruct who did what. It is also GuardDuty's primary input.

### Amazon GuardDuty

Analyses CloudTrail events, VPC Flow Logs and DNS query logs for credential
exfiltration, cryptomining, and communication with known-malicious hosts.

**Findings are routed, not just recorded.** An EventBridge rule matches findings
at **severity 4.0 and above** and forwards them to SNS through an input
transformer that extracts severity, type, region and description. Low-severity
informational findings are filtered out deliberately — an alert channel that is
mostly noise stops being read.

### AWS Config

Records resource configuration changes for drift and compliance history.

### AWS KMS

A customer-managed key with automatic annual rotation encrypts RDS storage and
backups, and the Secrets Manager values. Every use is logged to CloudTrail.

**Why customer-managed rather than the AWS-managed default.** Control over the
key policy, rotation cadence and cross-account access — all of which matter in a
compliance context even though the underlying cryptography is identical.

The SNS alerts topic uses the **AWS-managed** SNS key rather than this one.
Sharing a single key across unrelated purposes couples their key policies
together for no benefit.

---

## Layer 8: Analytics

A streaming pipeline running alongside the transactional database: Kinesis
Firehose to an S3 lake, a nightly Glue PySpark job producing partitioned
Parquet, and Athena over the result with partition projection rather than a
crawler.

It lives in its own root module (`infrastructure/environments/data`) with its
own state key, and the two stacks share no `terraform_remote_state`. That
separation is the point: the compute stack carries the hourly cost floor and is
meant to be destroyed between demos, while the lake costs nothing idle and stays
up. Destroying one cannot touch the other because neither has a record of it.

The event carries six fields and deliberately excludes the transaction
description, the account ID, and the owning user, which is the same
data-minimisation posture as the Bedrock integration.

Full detail — schema, cost table, lifecycle rules, query examples, and the Glue
job's `SystemExit` gotcha — is in `data-pipeline.md`.

---

## Security Model

Defence in depth: no single control is trusted on its own.

### Network Isolation

Each tier's security group references the security group of the tier permitted
to call it, rather than an IP range, so the rules stay correct as resources
scale:

| Security group | Inbound source | Port | Purpose |
|---|---|---|---|
| `alb-sg` | CloudFront managed prefix list | 80, 443 | Only CloudFront edges reach the ALB |
| `ecs-sg` | `alb-sg` | 3000 | App traffic only from the ALB |
| `rds-sg` | `ecs-sg` | 5432 | Database traffic only from ECS tasks |
| `vpce-sg` | `ecs-sg` | 443 | Endpoint traffic only from ECS tasks |

CloudFront is the one tier that cannot be chained — it does not live in the VPC
and has no security group to reference. The AWS-published managed prefix list is
the closest equivalent.

The database security group has **no blanket egress rule**; it may only return
traffic to the ECS security group. This is what stops a compromised database
being used to reach back out.

### Identity and Access

User identity is Cognito-issued JWTs, verified on every request. The verifier
does four things beyond checking the signature and expiry:

1. **Pins the accepted algorithm to RS256.** This is what blocks the `alg: none`
   and HMAC key-confusion attack families.
2. **Requires `token_use = "access"`**, so an ID token — issued for the
   frontend's own use — cannot be replayed as an API credential.
3. **Checks `client_id`.** A valid signature only proves the pool minted the
   token, not that it minted it *for us*. Without this, a token issued to any
   other app client in the same user pool would be accepted.
4. **Returns a single opaque error** for every rejection. Distinguishing
   "expired" from "wrong audience" only helps an attacker probe.

Service identity is IAM roles, scoped as described in Layer 4.

**Data is scoped per user in the query, not in the handler.** Accounts carry the
owner's Cognito `sub`, and every read filters on it. Transactions have no owner
of their own — ownership is always established by joining through the account —
so guessing an account ID cannot reach another user's data. An account belonging
to someone else returns **404, not 403**, because a 403 confirms the ID exists.

### Prompt Injection

Transaction descriptions are user-controlled text that ends up inside a model
prompt, which puts prompt injection in scope.

The defence is **not** the wording of the system prompt. It is that model output
is never trusted:

- Categories are constrained by a JSON schema whose `category` field is an enum,
  and then **re-validated against a closed allowlist in Go**. The schema is
  enforced on the other side of a network call; the allowlist runs in our own
  process.
- Severities are validated against a fixed set and default to `none`, so an
  unparseable answer can never manufacture an alert.
- Descriptions are truncated before they reach the prompt.
- Model output drives no privileged action. The worst outcome of a successful
  injection is a wrong category on the attacker's own row.

### Data Protection

At rest: RDS storage and backups, and Secrets Manager values, under the
customer-managed KMS key.

In transit: viewer to CloudFront over TLS 1.2+; CloudFront to ALB over HTTPS
once a certificate exists; ECS to RDS with `sslmode=require`; ECS to AWS APIs
over native TLS.

Without a domain configured, the CloudFront-to-ALB hop is HTTP. It stays inside
AWS's network and the ALB is reachable only from CloudFront, but it is genuinely
the weakest link in the current default configuration — and it closes the moment
`domain_name` is set.

### Application Hardening

Request bodies are capped at 1 MiB and reject unknown fields, so a client
sending `user_id` gets an error rather than the impression the server honoured
it. Amounts are rejected if not finite. Responses carry `nosniff`, `DENY`
framing, `no-referrer`, `no-store` and HSTS. A per-identity rate limiter caps
the model-backed endpoints, which is the dimension that maps to spend — WAF's
per-IP limit does not.

---

## Deliberately Not Implemented

Stated plainly, because an architecture document that only lists what exists is
half a document.

- **A second S3 bucket for user uploads.** The application has no upload
  feature. The S3 Gateway endpoint that would serve it is already in place.
- **Container Insights / APM tracing.** CloudWatch metrics and logs cover the
  failure modes this workload actually has. Distributed tracing earns its cost
  once there is more than one service.
- **Organization-wide CloudTrail.** This is a single-account project. The trail
  is account-scoped; extending it is a configuration change, not a redesign.
- **WAF logging to Kinesis Firehose.** Sampled requests and CloudWatch metrics
  are enabled; full request logging is additional cost for little added value
  at this traffic level.
- **ALB access logs.** Same reasoning; CloudWatch metrics cover the ALB's
  behaviour.
- **A backend-for-frontend holding tokens in httpOnly cookies.** The frontend
  stores its access token in `sessionStorage`, which is readable by any script
  on the page. This is the most significant known weakness in the stack and is
  documented in `app/frontend/src/auth.js` rather than left implicit. It is the
  right upgrade if this ever holds real money.
- **Automated tests against live AWS.** The Go test suite covers token
  verification, the category allowlist, the anomaly baseline logic, and the
  analytics event schema. Nothing tests the Terraform beyond `validate`; there
  is no Terratest suite.
- **A rate limit on `GET /api/summary`.** The endpoints that cost money per call
  are limited per identity. The summary endpoint is a plain database aggregate
  and is not, which is a gap rather than a decision.
- **Integration tests against a real Postgres.** The netting bug in the category
  aggregation was a SQL defect, and no unit test could have caught it — it was
  found by reading two numbers on screen that disagreed, and confirmed by
  running both queries against a throwaway container. A handful of handler tests
  against a real database would have caught it earlier and is the highest-value
  testing work outstanding.
