# MaroonLedger 🍁

*A production-grade personal finance platform on AWS — built to develop hands-on expertise across cloud engineering, DevOps, security, and networking.*

**MaroonLedger** is an end-to-end cloud engineering project that implements a production-grade personal finance platform on AWS. It demonstrates realistic cloud capabilities including secure user authentication and data storage, full CRUD operations over a relational database, and a scalable, highly available infrastructure deployed across multiple Availability Zones.

This project was built to demonstrate hands-on experience with the full AWS service ecosystem — from networking and container orchestration to identity, observability, and infrastructure-as-code — in a realistic, resume-ready portfolio piece

# Architecture

![MaroonLedger Architecture Diagram](docs/images/cloud-project-diagram-v1.png)

# Architecture Walkthrough
LayerPurposeKey Resources1 — NetworkingFoundation everything lives onVPC, 3-tier subnets (public/private/data), NAT Gateway, route tables2 — SecurityAccess control and encryptionSecurity group chain (ALB → ECS → RDS), KMS customer-managed key3 — DataPersistent storage and secretsRDS PostgreSQL Multi-AZ, Secrets Manager, automated backups4 — ComputeApplication runtime and ingressECS Fargate cluster, ALB with health checks, IAM roles5 — EdgeFrontend delivery and protectionCloudFront dual-origin, S3 static hosting, WAF with managed rules6 — ObservabilityMonitoring and complianceCloudTrail, GuardDuty, AWS Config
### Supporting Tools

- **Bash** — for repo-local scripting: build wrappers, local Terraform helpers, container entrypoints, and glue around the AWS CLI. Kept minimal and POSIX-compatible where possible.
- **AWS CLI** — for local interaction with the account during development, and for anything not yet managed through Terraform (one-off investigations, manual validation of deployed resources).
- **Git + GitHub** — version control and remote hosting. The repository is structured as a monorepo, with separate top-level directories for the Go backend, the React frontend, and the Terraform configuration.

### Planned Additions

- **GitHub Actions** — CI/CD pipeline for automated builds, tests, container image pushes to ECR, and Terraform plan/apply workflows. Not yet implemented; this is the next major piece of work on the infrastructure side.
