# MaroonLedger: Designing, Building, and Constraining a Cloud Platform

**Ruari Whalen** · September 2026

---

## Executive summary

MaroonLedger is a multi-tenant personal finance application deployed on AWS with
Terraform. It exists because I wanted to learn cloud engineering by operating a
system rather than by reading about one, and because the difference between those
two things turns out to be most of the education.

The application is small on purpose. Users sign in through Cognito, each person's
transactions are scoped to their own identity, and a language model classifies
transactions, flags unusual ones, and writes a spending summary. None of that is
novel. What makes the project worth writing about is everything underneath: a
three-tier VPC across two availability zones, ECS Fargate behind an Application
Load Balancer, RDS PostgreSQL in isolated subnets with no route to the internet, a
CI pipeline that gates on vulnerability scanning, and a streaming analytics path
that is deliberately separable from the transactional one.

The project has two halves, and the second is the interesting one. I built the
infrastructure first over five days in April 2026, put a Go API on top of it,
deployed it, took screenshots, and considered it finished. When I returned to it in
August intending to improve the interface, the first careful read of my own
repository found that the architecture document described a Cognito identity layer
and an ECS-on-EC2 cluster, and that neither existed. The API was open CRUD with no
authentication of any kind. Anyone who found the load balancer could read and write
every account in the database.

Everything since has been about closing that gap and then hardening what closed it.
That work produced the material in this document: an authentication design where
the local development path exercises the same verification code as production, a
data model where per-user scoping can only be got wrong in one place, an AI
integration that treats model output as untrusted input, and a deployment pipeline
that has caught real vulnerabilities and rolled back a real bad deployment.

This document also records what does not work, and why. The account this project
was deployed into is a vended sandbox governed by service control policies that
deny several services outright. Rather than quietly design around those limits, I
kept the production-correct configuration as the default and overrode it locally,
so that the repository describes the architecture I would deploy rather than the
one this particular account permitted. The gap between those two is documented here
and in the repository, because an architecture document that only lists what
succeeded is half a document.

---

## Architecture

A request arrives at CloudFront, which serves two origins. Static assets come from a
private S3 bucket reachable only through Origin Access Control; the bucket has no
public access path at all. Anything under `/api/*` is forwarded to an Application
Load Balancer in the public subnets. The load balancer's security group admits
traffic only from CloudFront's AWS-managed prefix list, so the distribution cannot
be bypassed by finding the load balancer's DNS name and calling it directly.

Behind the load balancer, two ECS Fargate tasks run in private application subnets
spread across two availability zones. They have no public IP addresses. Each task
runs a Go binary of roughly twelve megabytes in a distroless-style Alpine image as a
non-root user. The task's security group accepts traffic only from the load
balancer's security group, referenced by ID rather than by CIDR block, so the rule
remains correct if addressing changes.

The database tier sits in a third subnet group with no route to the internet in
either direction. It runs RDS PostgreSQL 16 on a `db.t4g.micro` instance with 20 GB
of gp3 storage that autoscales to 100 GB. Encryption at rest uses a customer-managed
KMS key. The master password is managed and rotated by RDS itself; an earlier
version generated it in Terraform, which wrote it into state in plaintext, and
replacing that was one of the first corrections of the second phase.

Identity is a Cognito user pool with a hosted UI. The browser performs an
authorization code flow with PKCE, which is the correct choice for a public client
that cannot keep a secret. The API validates the resulting access token against the
pool's JWKS endpoint. That validation was deliberately written against an issuer and
a JWKS URL rather than against Cognito specifically, and that decision turned out to
carry more weight than any other in the project: it allowed a small local identity
provider to sit behind the same verification path, so development runs the same code
as production instead of running with the check disabled. There is no
`AUTH_DISABLED` flag anywhere in the server, because a bypass that exists in the
code is a bypass that can ship.

The AI layer is an interface with two implementations, Amazon Bedrock and a
deterministic local stub. The application never branches on which is in use, and
every result records which provider produced it. Three features sit behind that
interface: transaction categorization into a closed set of twelve categories,
anomaly scoring against the account's own history within the same category, and a
natural-language spending summary generated from aggregated category totals.

A streaming analytics path runs alongside the transactional database. Committed
transactions are emitted to Kinesis Firehose, land in S3 as gzipped newline-delimited
JSON, are folded nightly into partitioned Snappy Parquet by a Glue PySpark job, and
are queried through Athena using partition projection rather than a crawler. The
event carries six fields and deliberately excludes the free-text description, the
account identifier, the owning user, and the anomaly reason. A test asserts that the
event has exactly those six fields and fails if a description or account identifier
ever appears, which is a cheap way to stop a future change from quietly turning an
aggregate store into a store of personal data.

The analytics path lives in a separate Terraform root module with its own state, and
the two stacks share no `terraform_remote_state` between them. That separation is
the point rather than an accident of organization: the compute stack carries an
hourly cost floor and is meant to be destroyed between demonstrations, while the
lake costs nothing when idle. Destroying one cannot affect the other, because
neither holds a record that the other exists. Athena keeps answering questions while
the application is switched off entirely.

### What has run, and what has not

Precision here matters more than the impression it creates.

The compute stack has been deployed twice and torn down twice, most recently at 85
resources. The application served real traffic, authenticated real sign-ins through
Cognito, and stored transactions seeded through its own API. The Glue job, catalog,
and Athena workgroup were deployed and the job ran successfully on a nightly
schedule.

Three components are implemented and unexercised. Bedrock inference has never run,
because the account's inference quota is zero for every Claude model in every
region; the integration is complete and there is a dedicated diagnostic command for
it, but every demonstration was produced by the stub, which is why the interface
labels the provider on every result rather than leaving it ambiguous. Kinesis
Firehose was never created, because a service control policy denies it
organization-wide, so the lake has only ever been populated by direct upload. The
OIDC federation between GitHub Actions and AWS has never completed a handshake,
because the same policy denies every operation on OIDC providers, including reading
one. In that last case the deployment logic is not unverified: I ran every step of
the workflow by hand against the live stack, and it built, scanned, pushed,
registered a task definition, and rolled the service to full health. Only the
credential exchange is untested.

---

## Well-Architected review

### Operational excellence

Everything is Terraform. Sixteen modules across two root stacks, with community
modules used for VPC, ALB, RDS, and KMS where they are well maintained, and
hand-written modules where the community options fought the design. Nothing is
click-configured, and rebuilding the entire environment is one command.

Continuous integration runs on every pull request and requires no AWS credentials at
all, which means it is safe to run on a fork. It formats, vets, and race-tests the
Go, builds the frontend with warnings treated as errors, builds and scans the
container image, and validates all three Terraform roots with the backend disabled.
One job exists purely to assert that a plain `docker build` produces the API server
and not the development identity provider, because stage ordering is what guarantees
that, ordering is easy to change by accident, and it was wrong once.

Observability is CloudWatch logs with a thirty-day retention, five alarms covering
load balancer 5xx responses and unhealthy hosts alongside database CPU, storage, and
connection count, an SNS topic for alerts, CloudTrail for API audit, and AWS Config
for resource history. The application logs one line per request containing method,
path, status, and duration, and deliberately logs no headers, bodies, or query
strings, any of which can carry tokens or personal data into a system far less
protected than the database.

The tradeoff accepted here is that there is no distributed tracing and no APM. For a
single service with one downstream database, metrics and structured logs cover the
failure modes that actually occur, and tracing earns its cost when there is more than
one service to trace between.

### Security

Per-user scoping is enforced in the query rather than in application logic.
Transactions carry no owner column at all; ownership is established by joining
through the account that holds them, so there is exactly one place where scoping can
be got wrong instead of one place per table. An account belonging to another user
returns 404 rather than 403, because a 403 confirms that the identifier is real.

Token verification checks three things beyond signature and expiry, and each has a
negative test. Pinning the algorithm to RS256 blocks the `alg=none` and HMAC
key-confusion attack families. Requiring `token_use=access` prevents an ID token,
issued for the frontend's own consumption, being replayed as an API credential.
Checking `client_id` matters because a valid signature proves only that the pool
minted the token, not that it minted it for this application.

The network is chained rather than flat. CloudFront reaches the load balancer, the
load balancer reaches the tasks, the tasks reach the database, and each tier's
security group references the one above it by identifier. CloudFront is the single
tier that cannot be chained this way, because it does not live in the VPC and has no
security group, which is why the managed prefix list is used instead.

IAM is split deliberately. The ECS execution role exists for the container agent
before the application starts and can read one Secrets Manager secret and use one KMS
key. The task role is what application code runs as, and it is the only one that can
reach Bedrock, scoped to Anthropic models rather than to a wildcard. Application code
therefore cannot borrow the agent's permissions. The CI role can push to one ECR
repository and update one ECS service, and its `iam:PassRole` grant names only the
two task roles and is conditioned on the ECS service principal, which is the real
containment on `RegisterTaskDefinition` given that AWS does not allow that action to
be scoped by task family.

Prompt injection is in the threat model, because transaction descriptions are
user-controlled text that reaches a model prompt. The control is not the wording of
the system prompt. A JSON schema constrains what the model may return, but that
schema is enforced on the far side of a network call, so the returned category is
re-validated against a closed allowlist in Go before it is stored, severities default
to none, and nothing the model returns drives a privileged action. A deliberate
injection attempt embedded in a transaction description landed as category `other`,
which is the containment behaving as designed.

The build pipeline gates on vulnerability scanning, and this is not decorative. Its
first real run failed on three findings rated HIGH, all with fixes available: an
arbitrary code execution issue in musl on the Alpine base, and a denial of service in
an indirect Go dependency. Fixing the first required understanding that the base
image tag lags its own package repository, since moving to a newer Alpine release
shipped the same vulnerable OpenSSL, and the resolution was to upgrade packages at
build time rather than to chase tags.

The most significant known weakness is documented rather than omitted. The frontend
holds its access token in `sessionStorage`, which is readable by any script on the
page. A backend-for-frontend holding it in an httpOnly cookie is the correct fix, and
it is the right investment if this ever holds real money.

### Reliability

The application runs two tasks across two availability zones behind a load balancer
that health-checks them every thirty seconds. The database supports Multi-AZ, and the
Terraform default is Multi-AZ; it was disabled only in the sandbox, where the free
tier does not offer it.

The deployment path is where reliability was actually tested. The ECS service carries
a deployment circuit breaker with rollback enabled and a sixty-second health check
grace period. I added both after a bad image, built without an explicit target and
therefore containing the wrong binary, sat failing health checks for ten minutes at
reduced capacity while nothing intervened. I then verified the fix rather than
trusting the configuration: deploying that same broken image on purpose produced the
intended sequence, with ECS reporting a circuit breaker rollback and returning the
service to the previous revision without human involvement. Throughout the failed
deployment the API answered correctly, because a minimum healthy percentage of one
hundred keeps working tasks in the target group until replacements are healthy. A
deployment failed completely and no request was lost.

That test also produced a useful correction to my expectations. The breaker took
about twelve minutes to trip rather than the two or three I assumed, because each
failed task must drain through the target group's deregistration delay before the
next attempt counts against the failure threshold.

### Performance efficiency

The tasks are sized at 0.25 vCPU and 512 MB, which is the smallest Fargate
configuration available and is generous for a Go binary serving a single-digit
request rate. The correct lever at this scale is not instance sizing but avoiding
work: the dashboard is served by one endpoint that returns balances, a daily balance
series, per-account sparklines, category totals, and flagged anomalies in a single
response, because the alternative of having the browser fetch accounts and then each
account's transactions and then derive the series client-side is one request per
account plus one, all of them round trips.

The analytics path is serverless throughout and scales to zero between runs. The Glue
job runs for a couple of minutes a night and bills per DPU-second while it runs.
Athena bills per terabyte scanned and nothing at rest. Partition projection removes
the crawler entirely, which means a new day becomes queryable the moment it exists in
S3 with nothing scheduled to discover it.

The ETL job repartitions by its partition keys before writing, which is a small
detail with a large effect: left alone, Spark writes one file per shuffle partition,
which at this volume means hundreds of files of a few kilobytes each. The small-file
problem makes an S3 lake slow and expensive to query regardless of how little data it
holds.

### Cost optimization

Cost is treated as a design constraint rather than an afterthought, and the reasoning
is recorded in the next section.

The structural decision is the two-stack split. The compute tier has an unavoidable
hourly floor because a NAT gateway, a load balancer, and a database instance all bill
by the hour whether or not anyone uses them. The analytics tier has no floor at all.
Separating them into independently destroyable stacks means the expensive half can be
torn down between demonstrations while historical data stays queryable, and that is
only safe because the two stacks genuinely share no state.

Several individually cheap choices follow the same reasoning. Firehose is used
instead of Kinesis Data Streams because Data Streams bills per shard-hour whether or
not anything is written, roughly eleven dollars a month as a floor, while Direct PUT
has none. Timestamp-prefix partitioning is used instead of Firehose's Dynamic
Partitioning feature, because the paid feature would extract a key from record
content that the free timestamp namespace already provides for ingest date. The lake
uses SSE-S3 rather than the customer-managed KMS key that protects the database,
because KMS bills per request and a Glue run issues a decrypt per object, and the
lake holds a lower-sensitivity derivative with no descriptions or identifiers in it.
The Athena workgroup enforces a one-gibibyte per-query scan ceiling that a client
cannot override, so a careless `SELECT *` fails rather than scanning everything.

### Sustainability

The same decisions that control cost control consumed capacity, because on a shared
platform the bill is a reasonable proxy for resources reserved. Fargate allocates
only the CPU and memory a task declares rather than a whole instance. The analytics
tier holds no running compute between nightly executions. Choosing partition
projection over a crawler removes a scheduled job entirely. Storage lifecycle rules
expire the raw landing zone after thirty days and move curated data to infrequent
access after ninety, so nothing accumulates indefinitely by default.

The most sustainable property of the system is that it is designed to be switched
off. Most of a demonstration environment's lifetime is idle, and a stack that can be
destroyed and rebuilt on demand consumes nothing during the weeks nobody is looking
at it.

---

## Cost analysis

All figures below are list prices for `us-east-2` taken from AWS's published price
lists, at 730 hours per month. Observed spend on this project was effectively zero
because free tier credits absorbed it, which makes actual billing data useless for
this purpose; the model is what the same architecture would cost without them.

The configuration as actually deployed, with a single NAT gateway, a Single-AZ
database, and VPC endpoints disabled:

| Component | Basis | Monthly |
|---|---|---|
| ECS Fargate, 2 tasks at 0.25 vCPU / 0.5 GB | $0.04048/vCPU-hr, $0.004445/GB-hr | $18.02 |
| NAT Gateway | $0.045/hr | $32.85 |
| Application Load Balancer | $0.0225/hr, excluding LCU | $16.43 |
| RDS `db.t4g.micro`, Single-AZ | $0.016/hr | $11.68 |
| RDS storage, 20 GB gp3 | $0.115/GB-month | $2.30 |
| Secrets Manager, KMS key, logs, ECR | | $2.42 |
| **Total** | | **$83.70** |

The same architecture at its production defaults, meaning a Multi-AZ database, a NAT
gateway per availability zone, and the seven interface endpoints enabled:

| Component | Monthly |
|---|---|
| Seven interface endpoints across two AZs | $102.20 |
| NAT Gateway, two | $65.70 |
| RDS Multi-AZ, instance and storage | $27.96 |
| Fargate, ALB, and the rest unchanged | $36.87 |
| **Total** | **$232.73** |

Two observations follow, and the second corrected a mistake in my own
documentation.

The first is that at this scale, compute is not the cost. The two Fargate tasks are
$18 a month, while the network plumbing around them, a NAT gateway and a load
balancer, is $49. Right-sizing containers is the obvious optimization and very nearly
the least effective one. Removing the NAT gateway by routing all outbound traffic
through VPC endpoints would be the meaningful change, and it is only worth it above a
certain scale.

The second is that the VPC endpoints cost more than the entire rest of the deployed
stack combined. Interface endpoints bill hourly per endpoint per availability zone,
so seven endpoints across two zones is fourteen billable attachments at a cent an
hour, or $102.20 a month, against a baseline of $83.70. My own infrastructure document
had estimated roughly fifty dollars, having neglected to multiply by availability
zone, and building this cost model is what surfaced the error. Endpoints remain off by
default and are correct to enable at a scale where NAT data processing charges exceed
their fixed cost, which is a much higher volume than this application produces.

The analytics stack is a separate case, because it has no idle cost worth tabulating.
Firehose Direct PUT bills per gigabyte ingested, S3 bills per byte stored with an
empty bucket costing nothing, Glue bills per DPU-second during a run of roughly two
minutes a night, Athena bills per terabyte scanned under a one-gibibyte per-query cap,
and the Glue Data Catalog is free below a million objects. At this application's
volume the entire analytics tier is a few dollars a month, and the budget alarm
attached to it is set at twenty dollars precisely because anything approaching that
figure indicates a runaway job rather than growth.

---

## Lessons learned

**The most expensive bug was a comment that was correct.** A category aggregation
query summed signed amounts, so any category holding movement in both directions
reported the difference rather than its spending. Three transfers into savings
cancelled most of an outbound wire, and the interface claimed six hundred dollars of
spending while the anomaly panel a few inches away flagged the twenty-four hundred
dollar transfer it had just erased. The fix already existed: a neighboring function
had been corrected weeks earlier and carried a comment explaining precisely why
per-category nets cannot be reused for this purpose. It had never been applied to the
query directly above it, or to a third copy of the same query elsewhere. A correct
comment sitting beside the bug it describes is worse than no comment, because it
reads as though somebody already checked.

**Defaults are a security control.** The Dockerfile built two binaries, the API and a
local identity provider that issues tokens to anyone. A build with no explicit target
produces whichever stage comes last, and the development provider was last, and a
comment at the top of the file asserted the opposite. That image reached the
registry. It was caught only because it listened on the wrong port and failed every
health check; had the ports agreed, a public endpoint would have been handing out
tokens. Reordering the stages so the safe target is the default is now the mechanism,
and a CI job asserts it, because the property was previously guaranteed by a comment.

**Verification and configuration are different things.** I configured a deployment
circuit breaker and could have written that this system rolls back failed
deployments. Testing it turned that claim into a measurement, and the measurement
included a fact I had wrong, which was how long it takes. I have tried to keep that
distinction visible throughout this document: what ran, and what is merely correct.

**Constraints produce better documentation than freedom does.** Being unable to
deploy WAF, GuardDuty, Firehose, or OIDC federation forced a decision about what the
repository should describe. Keeping the production-correct value as the default and
overriding it locally means the code represents the architecture I would deploy, with
the divergence written down rather than silently absorbed. It also meant confronting
service control policies properly, including working out that an OIDC provider
already existed in an account where listing providers was denied, by observing that
AWS validates a provider ARN when it parses a trust policy and therefore that
acceptance proves existence.

**What I would do differently.** I would write the authentication layer first rather
than fourth; building an application without identity and adding it later meant
revisiting every query. I would add integration tests against a real PostgreSQL
container early, because the aggregation bug above was a SQL defect that no unit test
could have caught, and it was ultimately found by two numbers disagreeing on a screen.
I would build the cost model before choosing the architecture rather than after,
since discovering that VPC endpoints cost more than the workload would have changed
when I reached for them. And I would treat the first draft of an architecture
document as a claim requiring verification, since the gap between what mine described
and what existed is the reason this project has a second half at all.
