# MaroonLedger: Designing and Constraining a Cloud Platform

**Ruari Whalen** · September 2026

---

## Executive summary

MaroonLedger is a multi-tenant personal finance application on AWS, built with
Terraform. I built it to learn cloud engineering by operating a system instead of
reading about one.

The application is small on purpose. Users sign in through Cognito, transactions
are scoped to each user's identity, and a language model classifies transactions,
flags unusual ones, and writes a spending summary. What makes it worth writing
about is the infrastructure underneath: a three-tier VPC across two availability
zones, ECS Fargate behind an Application Load Balancer, PostgreSQL in isolated
subnets with no internet route, a CI pipeline that gates on vulnerability
scanning, and an analytics path that can be destroyed independently of the
application.

The project has two halves. I built the infrastructure over five days in April
2026, put a Go API on it, deployed it, and considered it finished. When I returned
in August to improve the interface, my first careful read of my own repository
found that the architecture document described a Cognito identity layer that did
not exist. The API was open CRUD with no authentication. Anyone who found the load
balancer could read and write every account in the database.

Everything since has been closing that gap and hardening what closed it. That work
produced the material here: an authentication design where local development runs
the same verification code as production, a data model where per-user scoping can
only fail in one place, an AI integration that treats model output as untrusted
input, and a deployment pipeline that has caught real vulnerabilities and rolled
back a real bad deployment.

This document also records what does not work. The account I deployed into is a
vended sandbox governed by service control policies that deny several services
outright. I kept the production-correct configuration as the default and overrode
it locally, so the repository describes the architecture I would deploy instead of
the one this account permitted. The difference is documented here and in the repo.

---

## Architecture

A request arrives at CloudFront, which serves two origins. Static assets come from
a private S3 bucket reachable only through Origin Access Control. Anything under
`/api/*` goes to an Application Load Balancer in the public subnets. The load
balancer's security group admits traffic only from CloudFront's AWS-managed prefix
list, so it cannot be reached directly by looking up its DNS name.

Two ECS Fargate tasks run in private subnets across two availability zones, with
no public IPs. Each runs a twelve-megabyte Go binary in an Alpine image as a
non-root user. Their security group accepts traffic only from the load balancer's
security group, referenced by ID instead of CIDR, so the rule survives addressing
changes.

The database sits in a third subnet group with no internet route in either
direction: RDS PostgreSQL 16 on a `db.t4g.micro` with 20 GB of gp3 storage that
autoscales to 100 GB, encrypted with a customer-managed KMS key. RDS manages and
rotates the master password. An earlier version generated it in Terraform, which
wrote it into state in plaintext, and replacing that was one of the first fixes of
the second phase.

Identity is a Cognito user pool with a hosted UI. The browser runs an authorization
code flow with PKCE, the correct choice for a public client that cannot keep a
secret. The API validates the access token against the pool's JWKS endpoint.

That validation was written against an issuer and a JWKS URL, not against Cognito
specifically, and that decision carried more weight than any other in the project.
It let a small local identity provider sit behind the same verification path, so
development runs the same code as production instead of running with the check
disabled. There is no `AUTH_DISABLED` flag in the server, because a bypass in the
code can ship.

The AI layer is an interface with two implementations: Amazon Bedrock and a
deterministic local stub. The application never branches on which is in use, and
every result records which produced it. Three features sit behind it:
categorization into a closed set of twelve categories, anomaly scoring against the
account's own history within the same category, and a spending summary generated
from aggregated totals.

An analytics path runs alongside the transactional database. Committed transactions
go to Kinesis Firehose, land in S3 as gzipped JSON, are folded nightly into
partitioned Parquet by a Glue PySpark job, and are queried through Athena using
partition projection instead of a crawler. The event carries six fields and
excludes the description, account ID, user, and anomaly reason. A test asserts
those six fields and fails if an identifier ever appears, which stops a future
change from turning an aggregate store into a store of personal data.

The analytics path is a separate Terraform root module with its own state, sharing
no `terraform_remote_state` with the compute stack. The compute tier bills by the
hour and is meant to be destroyed between demonstrations; the lake costs nothing
idle. Destroying one cannot affect the other, because neither holds a record that
the other exists.

### What has run, and what has not

The compute stack has been deployed and torn down twice, most recently at 85
resources. It served real traffic, authenticated real sign-ins, and stored
transactions through its own API. The Glue job, catalog and Athena workgroup were
deployed and the job ran on schedule.

Three components are implemented and unexercised. Bedrock inference has never run,
because the account's quota is zero for every Claude model in every region; every
demonstration used the stub, which is why the interface labels the provider on
every result. Kinesis Firehose was never created, because policy denies it, so the
lake has only been populated by direct upload. The OIDC federation between GitHub
Actions and AWS has never completed a handshake, because the same policy denies
every operation on OIDC providers, including reading one.

In that last case the deployment logic is not unverified. I ran every step of the
workflow by hand against the live stack: it built, scanned, pushed, registered a
task definition, and rolled the service to full health. Only the credential
exchange is untested.

---

## Well-Architected review

### Operational excellence

Everything is Terraform: sixteen modules across two root stacks, using community
modules for VPC, ALB, RDS and KMS, and hand-written modules elsewhere. Nothing is
click-configured, and rebuilding the environment is one command.

CI runs on every pull request with no AWS credentials, so it is safe on a fork. It
formats, vets and race-tests the Go, builds the frontend with warnings as errors,
builds and scans the container image, and validates all three Terraform roots. One
job exists only to assert that a plain `docker build` produces the API and not the
development identity provider, because stage ordering guarantees that, ordering is
easy to change by accident, and it was wrong once.

Observability is CloudWatch logs with thirty-day retention, five alarms covering
load balancer 5xx and unhealthy hosts alongside database CPU, storage and
connections, an SNS topic, CloudTrail, and AWS Config. The application logs one
line per request with method, path, status and duration, and logs no headers,
bodies or query strings, any of which can carry tokens or personal data into a
system far less protected than the database.

**Tradeoff.** No distributed tracing and no APM. For one service with one
downstream database, metrics and structured logs cover the failure modes that
occur. Tracing earns its cost when there is more than one service to trace between.

### Security

Per-user scoping is enforced in the query, not in application logic. Transactions
carry no owner column; ownership comes from joining through the account that holds
them, so scoping can only fail in one place instead of one per table. A foreign
account returns 404, not 403, because a 403 confirms the identifier is real.

Token verification checks three things beyond signature and expiry, each with a
negative test. Pinning RS256 blocks the `alg=none` and HMAC key-confusion attack
families. Requiring `token_use=access` stops an ID token being replayed as an API
credential. Checking `client_id` matters because a valid signature proves only
that the pool minted the token, not that it minted it for this application.

The network chains rather than sitting flat. CloudFront reaches the load balancer,
the load balancer reaches the tasks, the tasks reach the database, each tier
referencing the one above by security group ID. CloudFront is the one tier that
cannot chain this way, since it has no security group, which is why the managed
prefix list is used instead.

IAM is split. The execution role serves the container agent before the application
starts and can read one secret and use one KMS key. The task role is what
application code runs as and is the only one that can reach Bedrock, scoped to
Anthropic models. Application code cannot borrow the agent's permissions. The CI
role can push to one ECR repository and update one ECS service, and its
`iam:PassRole` grant names only the two task roles and is conditioned on the ECS
service principal. That condition is the real containment on
`RegisterTaskDefinition`, which AWS does not allow to be scoped by task family.

Prompt injection is in the threat model, because transaction descriptions are user
input that reaches a prompt. The control is not the system prompt's wording. A JSON
schema constrains what the model may return, but that schema is enforced across a
network call, so the returned category is re-validated against a closed allowlist
in Go before storage, severities default to none, and nothing the model returns
drives a privileged action. An injection attempt embedded in a description landed
as category `other`.

The build pipeline gates on vulnerability scanning, and this is not decorative. Its
first real run failed on three HIGH findings: arbitrary code execution in musl on
the Alpine base, and a denial of service in an indirect Go dependency. Fixing the
first meant understanding that a base image tag lags its own package repository,
since a newer Alpine release shipped the same vulnerable OpenSSL. The resolution
was to upgrade packages at build time instead of chasing tags.

**Known weakness.** The frontend holds its access token in `sessionStorage`, which
any script on the page can read. A backend-for-frontend holding it in an httpOnly
cookie is the correct fix, and the right investment if this ever holds real money.

### Reliability

Two tasks run across two availability zones behind a load balancer that health
checks every thirty seconds. The Terraform default for the database is Multi-AZ,
disabled only in the sandbox, where the free tier does not offer it.

The deployment path is where reliability was tested. The ECS service carries a
deployment circuit breaker with rollback and a sixty-second grace period. I added
both after an image built without an explicit target, and therefore containing the
wrong binary, sat failing health checks for ten minutes at reduced capacity while
nothing intervened.

I then verified the fix instead of trusting it. Deploying that same broken image on
purpose produced the intended sequence: ECS reported a circuit breaker rollback and
returned the service to the previous revision with no human involvement. The API
answered correctly throughout, because a minimum healthy percentage of 100 keeps
working tasks in the target group until replacements are healthy. A deployment
failed completely and no request was lost.

The test also corrected my expectations. The breaker took twelve minutes to trip,
not the two or three I assumed, because each failed task must drain through the
target group's deregistration delay before the next attempt counts.

### Performance efficiency

Tasks are sized at 0.25 vCPU and 512 MB, the smallest Fargate configuration, and
generous for a Go binary serving a single-digit request rate. The lever at this
scale is avoiding work, not sizing instances. The dashboard is served by one
endpoint returning balances, a daily balance series, per-account sparklines,
category totals and flagged anomalies in a single response. The alternative has
the browser fetch accounts, then each account's transactions, then derive the
series client-side: one request per account plus one, all round trips.

The analytics path is serverless and scales to zero between runs. The Glue job runs
for a couple of minutes a night. Athena bills per terabyte scanned and nothing at
rest. Partition projection removes the crawler, so a new day becomes queryable the
moment it exists in S3.

The ETL job repartitions by its partition keys before writing. Left alone, Spark
writes one file per shuffle partition, which at this volume means hundreds of files
of a few kilobytes. The small-file problem makes an S3 lake slow and expensive to
query regardless of how little data it holds.

### Cost optimization

The structural decision is the two-stack split. The compute tier has an
unavoidable hourly floor, because a NAT gateway, a load balancer and a database
instance all bill by the hour whether or not anyone uses them. The analytics tier
has no floor. Separating them into independently destroyable stacks lets the
expensive half be torn down between demonstrations while historical data stays
queryable, and that is only safe because they share no state.

Smaller choices follow the same reasoning. Firehose instead of Kinesis Data
Streams, because Data Streams bills per shard-hour whether or not anything is
written, roughly eleven dollars a month as a floor. Timestamp-prefix partitioning
instead of Firehose Dynamic Partitioning, because the paid feature extracts a key
that the free timestamp namespace already provides for ingest date. SSE-S3 on the
lake instead of the customer-managed KMS key protecting the database, because KMS
bills per request and a Glue run issues a decrypt per object, against data that
holds no descriptions or identifiers. And an Athena workgroup that enforces a
one-gibibyte per-query scan ceiling a client cannot override, so a careless
`SELECT *` fails instead of scanning everything.

### Sustainability

The same decisions that control cost control consumed capacity, since on a shared
platform the bill approximates resources reserved. Fargate allocates only the CPU
and memory a task declares. The analytics tier holds no running compute between
nightly executions. Partition projection removes a scheduled job. Lifecycle rules
expire raw data after thirty days and move curated data to infrequent access after
ninety.

The most sustainable property is that the system is designed to be switched off.
Most of a demonstration environment's life is idle, and a stack that can be rebuilt
on demand consumes nothing during the weeks nobody is looking at it.

---

## Cost analysis

All figures are list prices for `us-east-2` from AWS's published price lists, at
730 hours a month. Observed spend was effectively zero because free tier credits
absorbed it, so actual billing is useless here. This is what the same architecture
costs without them.

As deployed, with one NAT gateway, a Single-AZ database, and endpoints disabled:

| Component | Basis | Monthly |
|---|---|---|
| ECS Fargate, 2 tasks at 0.25 vCPU / 0.5 GB | $0.04048/vCPU-hr, $0.004445/GB-hr | $18.02 |
| NAT Gateway | $0.045/hr | $32.85 |
| Application Load Balancer | $0.0225/hr, excluding LCU | $16.43 |
| RDS `db.t4g.micro`, Single-AZ | $0.016/hr | $11.68 |
| RDS storage, 20 GB gp3 | $0.115/GB-month | $2.30 |
| Secrets Manager, KMS, logs, ECR | | $2.42 |
| **Total** | | **$83.70** |

At production defaults, meaning Multi-AZ, a NAT gateway per zone, and the seven
interface endpoints enabled:

| Component | Monthly |
|---|---|
| Seven interface endpoints across two AZs | $102.20 |
| NAT Gateway, two | $65.70 |
| RDS Multi-AZ, instance and storage | $27.96 |
| Fargate, ALB, and the rest unchanged | $36.87 |
| **Total** | **$232.73** |

Two findings follow, and the second corrected my own documentation.

**Compute is not the cost.** Two Fargate tasks are $18 a month. The network
plumbing around them, one NAT gateway and one load balancer, is $49. Right-sizing
containers is the obvious optimization and nearly the least effective one.
Eliminating the NAT gateway by routing outbound traffic through VPC endpoints is
the meaningful change, and only above a certain scale.

**VPC endpoints cost more than everything else combined.** Interface endpoints bill
per endpoint per availability zone, so seven across two zones is fourteen billable
attachments at a cent an hour: $102.20 a month against a baseline of $83.70. My
infrastructure document had estimated fifty dollars, having neglected to multiply
by zone, and building this model is what caught it. Endpoints stay off by default
and are correct to enable where NAT data processing charges exceed their fixed
cost, which is a far higher volume than this application produces.

The analytics stack has no idle cost worth tabulating. Firehose bills per gigabyte
ingested, an empty S3 bucket costs nothing, Glue bills per DPU-second during a
two-minute nightly run, Athena bills per terabyte scanned under a one-gibibyte cap,
and the Glue Data Catalog is free below a million objects. The whole tier is a few
dollars a month, and its budget alarm is set at twenty dollars because anything
near that indicates a runaway job, not growth.

---

## Lessons learned

**The most expensive bug was a correct comment.** A category aggregation summed
signed amounts, so any category with movement in both directions reported the
difference instead of its spending. Three transfers into savings cancelled most of
an outbound wire, and the interface claimed $600 of spending while the anomaly
panel a few inches away flagged the $2,400 transfer it had just erased. The fix
already existed: a neighboring function had been corrected weeks earlier and
carried a comment explaining why per-category nets cannot be reused. It had never
been applied to the query above it, or to a third copy elsewhere. A correct comment
beside the bug it describes is worse than no comment, because it reads as though
someone already checked.

**Defaults are a security control.** The Dockerfile built two binaries: the API and
a local identity provider that issues tokens to anyone. A build with no explicit
target produces whichever stage comes last, and the identity provider was last, and
a comment at the top of the file claimed otherwise. That image reached the
registry. It was caught only because it listened on the wrong port and failed every
health check. Had the ports agreed, a public endpoint would have been handing out
tokens. Stage order is now the mechanism and a CI job asserts it, because the
property was previously guaranteed by a comment.

**Verification and configuration are different things.** I configured a circuit
breaker and could have written that this system rolls back failed deployments.
Testing it turned that claim into a measurement, and the measurement included a
fact I had wrong: how long it takes. I have kept that distinction visible
throughout this document.

**Constraints produce better documentation than freedom.** Being unable to deploy
WAF, GuardDuty, Firehose or OIDC federation forced a decision about what the
repository should describe. Keeping the production-correct value as the default and
overriding locally means the code represents the architecture I would deploy, with
the divergence written down. It also meant confronting service control policies
properly, including working out that an OIDC provider already existed in an account
where listing providers was denied, by observing that AWS validates a provider ARN
when parsing a trust policy, so acceptance proves existence.

**What I would do differently.** Write the authentication layer first instead of
fourth; adding identity later meant revisiting every query. Add integration tests
against a real PostgreSQL container early, because the aggregation bug was a SQL
defect no unit test could catch, and it was found by two numbers disagreeing on a
screen. Build the cost model before choosing the architecture, since learning that
VPC endpoints cost more than the workload would have changed when I reached for
them. And treat the first draft of an architecture document as a claim requiring
verification, since the gap between what mine described and what existed is the
reason this project has a second half.
