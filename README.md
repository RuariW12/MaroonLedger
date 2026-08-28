# MaroonLedger 🍁

*A production-grade personal finance platform on AWS — built to develop hands-on expertise across cloud engineering, DevOps, security, and networking.*

**MaroonLedger** is an end-to-end cloud engineering project: a multi-tenant personal finance application deployed on AWS with Terraform. Users authenticate through Cognito, each user's data is scoped to their own identity, and Claude on Amazon Bedrock categorises transactions, flags anomalies, and generates spending insights.

- Screenshots of the working app are in [`docs/images/`](docs/images/)
- [`docs/infrastructure.md`](docs/infrastructure.md) is a service-by-service account of the architecture, the reasoning behind each choice, and what was deliberately left out
- [`docs/devlog.md`](docs/devlog.md) is the development journal — debugging, dead ends, and decisions

---

## Running it locally

The full stack runs locally with no AWS account and no credentials. Authentication is **fully enabled** — there is no local bypass. Tokens come from a small development identity provider instead of Cognito, and the API validates them through exactly the same code path it uses in production.

```bash
cd app
docker compose up --build          # Postgres, dev identity provider, API
```

```bash
cd app/frontend
npm install
npm start                          # http://localhost:3001
```

Sign in with any username. The AI features run against a deterministic local provider, so every surface works offline and costs nothing.

### Using real Bedrock inference

```bash
export AWS_PROFILE=your-profile    # or AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
AI_PROVIDER=bedrock docker compose up --build
```

Requires Bedrock model access enabled in your account for the target region. Everything else is unchanged — the only difference is which `ai.Provider` implementation is constructed at startup.

### Tests

```bash
cd app && go test ./...
```

Covers JWT verification (including `alg=none`, foreign signing keys, ID-token replay, and wrong-audience rejection), the category allowlist that contains prompt injection, and the stub AI provider.

---

## Architecture

![MaroonLedger Architecture Diagram](docs/images/cloud-project-diagram-v1.png)

*The diagram predates the Cognito and Bedrock work; `docs/infrastructure.md` is the current reference.*

| Layer | Components |
|---|---|
| **Edge** | Route 53, CloudFront, ACM, WAF, S3 static hosting |
| **Identity** | Cognito user pool, hosted UI, PKCE, JWT verification |
| **Network** | VPC, 3-tier subnets across 2 AZs, NAT, VPC endpoints |
| **Compute** | ALB, ECS Fargate, separate execution and task IAM roles |
| **Data** | RDS PostgreSQL Multi-AZ, Secrets Manager, KMS CMK |
| **AI** | Claude on Amazon Bedrock |
| **Observability** | CloudWatch alarms, SNS, CloudTrail, GuardDuty, AWS Config |

Several components are gated behind variables because they cost real money — DNS/TLS, VPC endpoints, NAT-per-AZ, and Cognito threat protection. The stack applies and runs with all of them off. See the defaults table at the top of [`docs/infrastructure.md`](docs/infrastructure.md).

---

## What the AI layer does

Three features, all behind a single `ai.Provider` interface with two implementations — Bedrock, and a deterministic local stub. The application never branches on which is in use.

- **Transaction categorisation.** Leave the category blank and the description is classified into one of twelve categories on write.
- **Anomaly detection.** Each transaction is scored against the account's historical behaviour, with a severity and a plain-language reason.
- **Spending insights.** A natural-language summary with observations and recommendations, generated from aggregated category totals.

Two things shaped the design more than the features themselves:

**Prompt injection is in the threat model.** Transaction descriptions are user-controlled text that reaches a prompt. The defence is not prompt wording — it is that model output is never trusted. Categories are constrained by a JSON schema and then re-validated against a closed allowlist in Go; severities default to `none`; nothing the model returns drives a privileged action.

**Enrichment is best-effort.** Categorisation and anomaly detection run concurrently under a deadline, and any failure is logged and dropped rather than failing the user's write. The insights endpoint is the one place the model is a hard dependency, and it reports a 503 honestly rather than inventing a summary.

---

## Tech Stack

**Infrastructure** — Terraform (module-based), AWS
**Backend** — Go 1.25, PostgreSQL 16, Docker (multi-stage, non-root)
**Frontend** — React 19
**AI** — Claude on Amazon Bedrock via the Anthropic Go SDK
**Tooling** — AWS CLI, Git, tmux, nvim

---

## Security

The reasoning behind each control is in [`docs/infrastructure.md`](docs/infrastructure.md#security-model). In brief:

- **Per-user data scoping enforced in the query.** Transactions carry no owner of their own; ownership is always established by joining through the account, so guessing an ID cannot reach another user's data. Foreign resources return 404, not 403.
- **JWT verification** pins RS256 (blocking `alg=none`), requires `token_use=access` so an ID token cannot be replayed as an API credential, and checks `client_id` so a token minted for another app client in the same pool is rejected.
- **No auth bypass flag exists in the server.** Local development uses a real identity provider rather than a disabled check.
- **Security group chaining** — each tier admits only the tier above it, with the ALB restricted to CloudFront's managed prefix list so the WAF cannot be bypassed.
- **RDS-managed master password**, rotated natively. The previous approach wrote a Terraform-generated password into state in plaintext.
- **Separate ECS execution and task roles**, so application code cannot borrow the agent's permissions. Bedrock access is scoped to Anthropic models in-region, not `*`.
- **Per-identity rate limiting** on the endpoints that cost money per call.

Known weaknesses are documented rather than omitted — see [Deliberately Not Implemented](docs/infrastructure.md#deliberately-not-implemented).

---

## CI/CD

Built as a separate repository: a GitHub Actions pipeline automating build, push, deploy, and CloudFront invalidation.
