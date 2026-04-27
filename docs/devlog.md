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
