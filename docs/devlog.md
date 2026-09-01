# Development Log
MaroonLedger journal containing decision making, debugging, lessons learned, and sidenotes.

## Day 1 - Architecture and Planning
- Designed the full architecture diagram with Lucidchart
- Mapped out a three layer architecture, considered cost implications, resource usage, and efficiency in architecture
- Wrote the first draft of the README. Focused on establishing the project requirements, deliverables, and purpose early to set clear goals.

## Day 2 - Bootstrap and Remote State
- Decided to utilize an S3 remote state backend with DynamoDB locking for production realism. 
- Declared the bootstrap module in infrastructure. Encrypted S3 bucket, DynamoDB table with a LockID
- Learned .terraform.lock.hcl should be committed and not ignored. Version locks providers

## Day 3 - Beginning Layer Modules
- Built layer 1 and 2. (VPC, SG's, KMS)
- Defined VPC architecture as a three tier subnet layout spread across two AZs. Public, private, and database. Enabled DNS hostnames and DNS support for RDS 
- Security Groups: wrote these resources with ingress/egress rules. Learned about SG chaining, so that services only accept traffic from the previous sg in line.
- Learned SG's and their rules are separate TF resources.
- ip_protocol = "-1" allows all egress traffic.
- KMS: wrote the module for RDS encryption at rest. RDS asks KMS for a key, KMS generates one under the master key. 

## Day 4 - Data, Compute, Edge, and Observability Modules
- Built the remaining four layers in one sitting
- Build every module, then apply once
- RDS module uses PostgreSQL with minimum efficient resources for cost implications. 
- ALB module uses the community module. Performs health checks every 30 seconds.
- ECS module Hit a provider compatibility issue with community module, developed custom module that defines the clster, tasks, IAM roles, and service.
- CDN Module serves React frontend from S3, attached WAF.
- Observability module uses CloudTrail for API audit logging, GuardDuty, and AWS Config for resource config tracking

## Day 5 - First Apply and debugging
- Ran first terraform init and plan in /environments/dev
- Fixed provider version conflict in ALB module
- ECS module incompatibility Fixed
- After debugging, plan came back clean with 72 resouces.
- Learned RDS takes a while to apply which is normal
- Some issues destroying. ALB deletion protection, had to reconfigure module. S3 buckets not being empty, added force_destroy = true. IGW couldnt detach, resolved itself after fixing deletion protection
- added recovery_window_in_days = 0 to Secrets Manager so the secret deletes immediatelty instead of sitting in a 30 day recovery window. Without this, the apply fails with name collsions.

- Started the Go backend. Wrote cmd/server/main.go with a health check endpoint on port 3000. Tested locally with curl and got a status ok
- wrote db connection pooling, data models, SQL migrations, and REST handlers for accounts and transactions. Wired everything into main.go

- Setup docker compose for local Postgres. Ran into connection issues, realized VPN was conflicting with local testing
- Succesfully curled full API locally. 

## Day 6 - Containerization and Deployment
- Created a multi stage dockerfile. First stage compiled the Go binary, second copies binary into alpine for HTTPS. Compressed down to 22MB.
- New ECR Terraform module wired in. used -target flag in apply to create just the repo without bringing every other resource
- A lot of debugging. Containers kept crashing in a loop.
- Secrets manager access error solved with a new Deployment
- containers connecting to localhost as default, had to update main.go to check for JSON blob
- RDS hostname included the port. changed ...db_instance_endpoint to db_instance_address which returns just the hostname
- RDS required SSL. Added sslmode=require in ECS path
- Tables didn't exist in RDS. Migrations kept running against local postgres. Created internal/database/migrate.go using Go to read the SQL file and execute on startup. Ran into issues with nonexisting SQL, so rewrote sql file to include "IF NOT EXISTS" for idempotentency.
- After all the fixes, the db connected, migrations ran, server started. All healthy.

## Day 7 - Frontend and Docs
- Built a simple React frontend. Main dashboard, account detail, forms
- Built the frontend, synced to s3, invalidated CloudFront cache. Cloudfront serves the react app and routes api calls to the alb.
- Seeded the database with semi-realistic data through API calls. Took screenshots
- Destroyed infra, committed everything

## Day 8 - Revisiting the project: authentication

Picked this back up before recruiting season. First pass over the code turned up
two gaps between what the docs claimed and what existed: the infrastructure doc
described a Cognito identity layer and an ECS-on-EC2 cluster, and neither was
real. The API was open CRUD with no auth at all.

- Started with token verification rather than Cognito itself. Wrote the verifier
  against an issuer + JWKS URL rather than against Cognito specifically, which
  turned out to be the decision everything else hung off.
- That let me build `cmd/devidp`, a tiny local identity provider. It means local
  development runs the *same* verification code as production instead of a
  disabled check. Deliberately did not add an `AUTH_DISABLED` flag - a bypass
  that exists in the code is a bypass that can ship.
- Learned/confirmed the JWT checks that actually matter beyond signature+expiry:
  pinning the algorithm to RS256 (stops `alg=none` and HMAC key confusion),
  requiring `token_use=access` (stops an ID token being replayed as an API
  credential), and checking `client_id` (a valid signature only proves the pool
  minted the token, not that it minted it for *us*).
- Wrote tests for all of those as negative cases. 18 assertions, all passing.
- Replaced the hardcoded single-migration read with a versioned runner - each
  file applies once inside a transaction alongside its `schema_migrations`
  insert, so a failed migration leaves no partial state.

## Day 9 - Per-user data and the AI layer

- Added `user_id` to accounts and scoped every query to it. Transactions
  deliberately have no `user_id` of their own: ownership is established by
  joining through the account, so there is exactly one place scoping can be got
  wrong. Foreign accounts return 404 rather than 403 - a 403 confirms the ID is
  real.
- Built `internal/ai` around a `Provider` interface with two implementations:
  Bedrock, and a deterministic stub. The stub is not a fallback, it is a
  stand-in - it means the whole app works with no AWS account, and it made the
  logic testable without mocking a network service. Recorded which provider
  produced each result so stub output can never be mistaken for inference.
- Thought about prompt injection properly for the first time. Transaction
  descriptions are user-controlled text going into a prompt. The realization
  that mattered: the system prompt wording is not the control. The control is
  that model output is re-validated against a closed allowlist in Go after it
  comes back. The JSON schema constrains the model, but it is enforced on the
  other side of a network call.
- Verified with an actual injection attempt in a description. It landed as
  category `other`, which is exactly the intended containment.
- Enrichment runs categorization and anomaly detection concurrently under a
  15s deadline, and drops failures. Neither is worth failing a user's write.

## Day 10 - Frontend auth, and two bugs only a browser could find

- Wired PKCE for the Cognito hosted UI and a username form for the dev IdP
  behind one interface. Checked the OAuth `state` parameter on return - without
  it an attacker can feed you a code that logs you into *their* account.
- Everything worked from curl. Then I opened it in a browser and sign-in failed
  immediately: the dev IdP sent no CORS headers, so the cross-origin fetch from
  the dev server was blocked. Cognito's token endpoint sets them, so this only
  ever affected local development - and only in a real browser.
- Fixed that, and hit a second one. The dev IdP generated a fresh RSA key on
  every restart but advertised a *fixed* `kid`. The API had cached the old key
  under that same `kid` and had no way to know it had changed, so every token
  failed verification. Real IdPs derive the key ID from the key; changed it to a
  hash of the modulus so rotation invalidates the cache the way it should.
  Genuinely the most useful thing I learned this week.
- Screenshotted the three views through headless Chrome to confirm no runtime
  errors.

## Day 11 - Closing the infrastructure/documentation gap

Audited `docs/infrastructure.md` line by line against the Terraform. It was
worse than the two gaps I already knew about - roughly a dozen claims described
infrastructure that did not exist: VPC endpoints, NAT per AZ, Route 53, ACM, the
HTTPS listener, the ALB prefix-list restriction, Secrets Manager rotation,
CloudWatch alarms, SNS, and the GuardDuty event routing. Decided to build them
rather than delete the claims.

- **ALB was reachable from `0.0.0.0/0`.** The WAF sits on CloudFront, so anyone
  resolving the ALB's DNS name skipped it entirely. Restricted the SG to
  CloudFront's managed origin-facing prefix list. This was the most serious
  finding of the whole pass.
- **CloudFront was caching API responses for 24 hours.** The `/api/*` behavior
  set no TTLs, so the default applied. Stale balances, and responses still
  served from the edge after sign-out. Pinned all three TTLs to 0.
- Replaced the `random_password` + manual secret with an RDS-managed master
  password. The old approach wrote the password into Terraform state in
  plaintext, and rotating it would have needed a Lambda in the VPC. RDS rotates
  natively. The managed secret only carries username/password, so the app now
  merges whatever the secret provides with env vars for host/port/dbname.
- Gated the whole DNS/TLS layer on `domain_name` being set, so the stack still
  applies without a registered domain. Will point a real domain at it later.
- Two Terraform lessons. First, module cycles: VPC endpoints need a security
  group and security groups need the VPC, so the endpoints had to move to their
  own module. Same problem again with DNS - CloudFront needs the ACM cert, so
  the apex alias record had to move up into the environment.
- Second, and more annoying: `cond ? {a=...} : {b=...}` fails with "Inconsistent
  conditional result types" when the two objects have different attributes.
  `cond ? {a=...} : {}` fails too. The pattern that works is a `for` over a
  conditional *list* - `for k in (cond ? ["https"] : [])` - because that unifies
  two lists of strings instead of two object types, then `merge()` the results.
- Kept Fargate and wrote an honest justification instead of pretending it was
  EC2+ASG. No host to patch, per-task billing, and per-task ENIs that make the
  SG chain describe tasks rather than hosts. Choosing EC2 to look more
  impressive would have been justifying infrastructure by what it teaches rather
  than what the workload needs.
- Added a "Deliberately Not Implemented" section to the infra doc. An
  architecture document that only lists what exists is half a document.

## Day 12 - Containerizing the frontend

The frontend was still the odd one out: Postgres, the dev IdP and the API ran in
compose, but the UI needed `npm install && npm start` on the host. Fixed that.

- Two build targets rather than one. `dev` runs the CRA dev server with hot
  reload; `production` serves the built bundle through nginx with the same
  static-vs-/api split CloudFront performs. The production target is what
  catches bundle-only problems - minification, a missing REACT_APP_* value, SPA
  routing that the dev server's catch-all hides.
- The `proxy` field in package.json only takes a literal string, which cannot
  work in both environments: on the host the API is localhost:3000, inside
  compose "localhost" is the frontend container itself. Replaced it with
  `src/setupProxy.js` reading `API_PROXY_TARGET`.
- Note the browser still talks to the dev IdP as `localhost:9000` while the API
  reaches it as `devidp:9000` - the same issuer/JWKS split the verifier was
  designed around on Day 8, showing up again for a different reason.
- `npm ci` failed in the build: adding a dependency on the host produced a
  lockfile my npm accepted but the container's npm 10 rejected (missing a
  transitive `yaml` entry). Regenerated the lockfile *inside* node:22-alpine so
  it matches what the image actually resolves. Worth remembering - a lockfile is
  only reproducible against the npm that wrote it.
- Needed `WATCHPACK_POLLING=true`; Docker Desktop bind mounts do not deliver
  inotify events, so without it host edits never trigger a rebuild. Verified by
  editing App.js and watching the served bundle change.
- Only `src/` and `public/` are mounted, not the whole directory - mounting all
  of it would shadow the image's node_modules with the host's, which breaks the
  moment the architectures differ.
- One real bug found while verifying. nginx does not merge `add_header` across
  levels: a location block declaring any add_header of its own silently discards
  every inherited one. So the server-level security headers were present on
  static assets but **missing on `/`** - the HTML document, which is the one
  response where X-Frame-Options actually protects against clickjacking. Had to
  repeat them in each location that sets caching headers.

## Day 13 - Redesign, light and dark modes

Rebuilt the UI against Monarch-style references: sidebar rail, stat tiles, real
charts, card layout, and a proper light/dark theme.

- Built the design system as CSS custom properties with dark declared twice -
  once under `prefers-color-scheme` for people who never touch the toggle, once
  under `[data-theme]` so an explicit choice wins in both directions. The
  `:not([data-theme="light"])` guard is what lets a light stamp beat OS-dark.
- Kept the maroon identity but inverted where it lives: in light mode the rail
  is deep maroon against a light page, which is the structure the references
  use to separate navigation from work.
- Wrote the charts as hand-built inline SVG instead of pulling in Recharts. The
  deciding reason was theming: every color is a CSS variable, so light/dark is
  a token swap with no re-render and no JS reading computed styles. Also avoids
  ~100KB of dependency for three chart types.
- Ran the series palette through the data-viz validator against both surfaces
  rather than eyeballing it. Passes the lightness band, chroma floor,
  color-blind separation, normal-vision separation, and contrast in both modes.
- Category bars are one hue, not twelve. Identity lives in the row label -
  twelve categories would need twelve hues nobody can tell apart, and would put
  identity in the least accessible channel available. Past six, the tail folds
  into "Other".
- Added `/api/summary` so the dashboard is one request instead of one per
  account, and so the balance arithmetic sits next to the data rather than in
  the browser. Balance history is reconstructed by walking *backwards* from the
  current balance - going forwards from zero plots cumulative movement, not
  balance, and would disagree with the figure on the account.

Four things went wrong, all caught by looking at real output rather than
assuming:

- **My own rate limiter blocked the seed script.** 85 of 99 writes came back
  429. Working exactly as designed; the seeder just had to be paced under
  60/min. Worth knowing the limit is real.
- **Inflow and outflow were computed from per-category nets**, which is wrong
  whenever a category holds movement in both directions. "transfer" held +1,800
  of savings deposits and -6,400 of a wire, netting to -4,600 - erasing 1,800 of
  real inflow and understating outflow by the same amount. The savings rate came
  out negative when it should have been +38%. Fixed by splitting on the sign of
  each row in SQL.
- **Rent was flagged as anomalous every month.** The stub compared each amount
  against the account-wide average, and rent is 8-15x a typical purchase.
  Comparing within its own category makes it unremarkable. That required running
  categorization *before* anomaly detection instead of concurrently - the
  ordering is the fix, and the concurrency was what forced the wrong comparison.
- I misread colors off screenshots twice (thought the rail wasn't theming, then
  thought a negative savings rate was rendering green). Both times measuring
  `getComputedStyle` showed it was already correct. Lesson: read the computed
  value, don't eyeball a PNG.

## Day 14 - Palette and typeface pass

- Darkened the brand maroon. Dark mode was `#e0566f`, which read as pink
  against a neutral shell. Walked it down and measured each step: `#b8354c` is
  the floor that still clears 3:1 on the dark surface, so `#c23a51` keeps
  margin. Light went to `#98192e` - `#8f1528` was fractionally under the
  validator's lightness band (0.422 vs the 0.43 floor).
- Swapped Inter/JetBrains for IBM Plex Sans/Mono. Plex reads more engineered
  than Inter's SaaS-default look, and Plex Mono's tabular figures are good in
  the money columns.
- Went from six hues to eight and used them on the category bars, which had
  been single-hue. Ordering matters more than the hues: orange next to green
  fails color-blind separation (ΔE 2.7) and magenta next to orange fails the
  normal-vision floor (11.6). Tested orderings until one cleared every adjacent
  gate in both modes - maroon, blue, orange, aqua, amber, magenta, violet,
  green.
- Color is keyed to the category name, never its rank in the sorted list, so
  filtering or a change in ranking never repaints the other bars. Eight
  categories get a hue; the rest and the "Other" rollup are neutral gray. A
  ninth hue would have to be a repeat, and a repeat is worse than an honest
  gray.
- Added the gradient fade from the reference via `color-mix`, and gave the area
  fill a third gradient stop - two stops leave a visible hard edge on dark,
  where fill and card are close in luminance.
- Same trap as Day 13, again: my scripted edit updated the
  `prefers-color-scheme` block but not `[data-theme]`, which would have left the
  toggle serving the old pink palette while OS-dark served the new one. Caught
  by grepping both blocks rather than trusting the replace count.

## Day 15 - Dropped the webfont

IBM Plex reads as the default "AI product" typeface now, so it went. Replaced
with the native system stack rather than another downloaded face:
SF Pro on macOS, Segoe UI Variable on Windows, Roboto on Android, with
ui-monospace (SF Mono / Consolas) for the money columns.

The argument for it is not only that it looks less trend-following. It removes
the last third-party origin from the frontend: one fewer request on first
paint, no flash of unstyled text, nothing to break when a font CDN is
unreachable, and no `fonts.googleapis.com` to allow in a CSP. Verified with the
network log - zero font requests, zero `@font-face` faces registered.

Also normalized font-weight 550/650 to 500/600. Those are variable-font weights;
static system fallbacks round them unpredictably.

## Day 16 - The data pipeline

Added a streaming analytics layer alongside the transactional database. Firehose
to an S3 lake, a nightly Glue PySpark job producing Parquet, Athena on top.

- Built it as a second root module with its own state key rather than folding it
  into the dev stack. The compute stack has an hourly floor and wants destroying
  between demos; the lake costs nothing idle and should survive that. Two stacks
  with no `terraform_remote_state` between them is what makes `terraform
  destroy` safe. I wire the outputs across by hand, which feels clumsy and is
  the entire point. Coupling them would defeat the separation.
- Firehose rather than Kinesis Data Streams. Data Streams bills per shard-hour
  whether or not anything is written, about $11/month as a floor. Direct PUT has
  no floor at all.
- Skipped the Glue crawler entirely. Partition projection describes the layout
  deterministically, so a new day becomes queryable without anything having to
  run first. One less scheduled job, one less thing to bill.
- Decided what the event carries by asking what analytics actually needs. Six
  fields: id, timestamp, amount, category, provider, severity. No description,
  no account id, no user. Wrote a test asserting exactly six fields so that a
  future "just add the description, it'd help with grouping" has to argue with a
  failing build.
- `count` can't depend on an apply-time value. A CloudWatch alarm gated on one
  failed the apply outright; changed it to a static bool.

## Day 17 - Deploying it, and two bugs found by looking

Deployed both stacks to a real account, seeded a demo dataset, and took
screenshots. Most of the day was spent on things the deploy surfaced.

- The account is a vended sandbox with SCPs above IAM: EC2 pinned to us-east-2,
  Firehose denied org-wide, GuardDuty denied, WAF denied at CloudFront scope.
  AdministratorAccess doesn't help, because an SCP sits above IAM and can't be
  overridden from inside. Turned each into a Terraform variable defaulting to
  the production-correct value and overrode them in gitignored tfvars, so the
  repo describes the architecture I'd deploy rather than the one this account
  permitted.
- Bedrock inference quota is 0.0 for every Claude model in every region here.
  The integration is real and `cmd/bedrockcheck` exercises it, but the demo runs
  the stub. Every result records its provider, so the insights page names the
  stub instead of quietly implying inference.
- Reported "INVOKABLE ✓" from a diagnostic whose catch-all case swallowed the
  actual error. Worth writing down: a diagnostic that can only print success is
  not a diagnostic.

**The $1,800 disagreement.** The dashboard said $10,812 of spending, the
insights page said $9,012, and the category bars summed to the smaller one. The
category query summed the *signed* amount per category, so anything with
movement in both directions reported the difference. Three $600 transfers into
savings canceled most of a $2,400 outbound wire; the transfer category claimed
$600 of spending while the anomaly panel a few inches away flagged the $2,400
wire it had just erased. Every category percentage was inflated to match.

The part I want to remember: the fix already existed. `cashflow()` had been
corrected weeks earlier and carried a comment spelling out exactly why
per-category nets can't be reused for this. It had never been applied to the
query directly above it, or to the third copy of the same query in the insights
handler. A correct comment sitting next to the bug it describes is worth less
than no comment at all, because it reads as though someone already checked.

Fixed by aggregating outflows only, so income drops out in SQL instead of being
filtered by every consumer, and collapsing the three copies into one function.
Verified against a throwaway Postgres: the old query returns transfer −600
across 4 rows and lets income in, the new one returns 2400 across 1 row and
doesn't. No unit test could have caught this. It was found by two numbers on
screen disagreeing.

**A plain `docker build` shipped the wrong binary.** The Dockerfile builds the
API server and the dev identity provider. `docker build .` with no `--target`
builds whichever stage is *last*, and devidp was last. The comment at the top of
the file asserted the opposite. I pushed that image to ECR and the service sat
at 1/2 for ten minutes while ECS killed task after task for failing health
checks. The dev IdP listens on 9000 and the target group probes 3000, so it
never passed and never received traffic.

That port mismatch is the only reason this was loud. Had they agreed, a public
endpoint would have been handing out tokens to anyone who asked. Reordered so
`server` is last: stage order is the mechanism, not the comment, and the default
target is now the safe one.

- Also fixed the anomaly reason text. When a category has no history the score
  falls back to an account-wide baseline, but the message still named the
  category, reporting "11.3x the usual for housing" on the first rent payment when
  housing had no history at all to be usual about. The message now names the
  baseline it actually used. Added a test for both branches.
- Rewrote the README around the story rather than the feature list, and split
  the data pipeline out into its own doc. The README had grown to the point
  where a third of it was one subsystem.
