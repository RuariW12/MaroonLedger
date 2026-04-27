# MaroonLedger 🍁

*A production-grade personal finance platform on AWS — built to develop hands-on expertise across cloud engineering, DevOps, security, and networking.*

**MaroonLedger** is an end-to-end cloud engineering project that implements a production-grade personal finance platform on AWS. It demonstrates realistic cloud capabilities including secure user authentication and data storage, full CRUD operations over a relational database, and a scalable, highly available infrastructure deployed across multiple Availability Zones.

This project was built to demonstrate hands-on experience with the full AWS service ecosystem — from networking and container orchestration to identity, observability, and infrastructure-as-code — in a realistic, resume-ready portfolio piece

# Architecture

![MaroonLedger Architecture Diagram](docs/images/cloud-project-diagram-v1.png)

# Architecture Walkthrough
**Layer 1: Networking**
Foundation everything lives on. VPC, 3-tier subnets, (public/private/data), NAT Gateway, route tables
**Layer 2: Security**
Access control and encryption. Security group chain, (ALB -> ECS -> RDS). KMS customer managed key
**Layer 3: Data**
Persistent storage and secrets. RDS PostgreSQL across 2 AZ's, Secrets Manager, automated backups
**Layer 4: Compute**
Application runtime and ingress. ECS Fargate Cluster, ALB with health checks, IAM roles
**Layer 5: Edge**
Frontend delivery and protection. Cloudfront, S3 static hosting, WAF
**Layer 6: Observability**
Monitoring and compliance with CloudTrail, GuardDuty, and AWS Config

# Tech Stack
**Infrastructure** - Terraform, AWS
**Backend** - Go, PostgreSQL, Docker
**Frontend** React, (HTML, CSS, JavaScript)
**Tools**: Bash scripting, AWS CLI, Git version control, tmux, vim

# Project Structure
cloud-project-v1/
├── infrastructure/
│   ├── bootstrap/          # S3 state bucket + DynamoDB lock table
│   ├── modules/
│   │   ├── vpc/            # Three-tier VPC across 2 AZs
│   │   ├── security-groups/# SG chain: ALB → ECS → RDS
│   │   ├── kms/            # Customer-managed encryption key
│   │   ├── rds/            # PostgreSQL Multi-AZ + Secrets Manager
│   │   ├── alb/            # Application Load Balancer + target group
│   │   ├── ecs/            # Fargate cluster, task def, service, IAM
│   │   ├── ecr/            # Container image repository
│   │   ├── cdn/            # CloudFront + S3 frontend + WAF
│   │   └── observability/  # CloudTrail, GuardDuty, AWS Config
│   └── environments/
│       └── dev/            # Wires all modules together
├── app/
│   ├── cmd/server/         # Go entrypoint
│   ├── internal/
│   │   ├── handlers/       # REST API handlers
│   │   ├── database/       # Connection pool + migrations
│   │   └── models/         # Data structures
│   ├── frontend/           # React dashboard
│   ├── Dockerfile          # Multi-stage production build
│   └── docker-compose.yml  # Local dev (Postgres)
├── docs/
│   ├── infrastructure.md   # Layer-by-layer infrastructure breakdown
│   ├── devlog.md           # Build journal with timestamps
│   └── screenshots/        # Dashboard and deployment screenshots
└── README.md


