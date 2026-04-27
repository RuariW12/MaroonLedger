# MaroonLedger 🍁

*A production-grade personal finance platform on AWS — built to develop hands-on expertise across cloud engineering, DevOps, security, and networking.*

**MaroonLedger** is an end-to-end cloud engineering project that implements a production-grade personal finance platform on AWS. It demonstrates realistic cloud capabilities including secure user authentication and data storage, full CRUD operations over a relational database, and a scalable, highly available infrastructure deployed across multiple Availability Zones.

This project was built to demonstrate hands-on experience with the full AWS service ecosystem — from networking and container orchestration to identity, observability, and infrastructure-as-code — in a realistic, resume-ready portfolio piece

# Architecture

![MaroonLedger Architecture Diagram](docs/images/cloud-project-diagram-v1.png)

# Architecture Walkthrough
#### For more advanced infrastructure explanation, check /docs/infrastructure.md
### **Layer 1: Networking**
Foundation everything lives on. VPC, 3-tier subnets, (public/private/data), NAT Gateway, route tables
### **Layer 2: Security**
Access control and encryption. Security group chain, (ALB -> ECS -> RDS). KMS customer managed key
### **Layer 3: Data**
Persistent storage and secrets. RDS PostgreSQL across 2 AZ's, Secrets Manager, automated backups
### **Layer 4: Compute**
Application runtime and ingress. ECS Fargate Cluster, ALB with health checks, IAM roles
### **Layer 5: Edge**
Frontend delivery and protection. Cloudfront, S3 static hosting, WAF
### **Layer 6: Observability**
Monitoring and compliance with CloudTrail, GuardDuty, and AWS Config

# Tech Stack
### **Infrastructure**
- Terraform (infrastructure-as-code, module based application.)
- AWS (Utilized AWS as cloud provider for resources and services)
### **Backend**
- Go (Golang for backend, REST, HTTP Server with Health Checks)
- PostgreSQL (Database server and language)
- Docker (Containerization for local and production testing)
### **Frontend**
- React (HTML, CSS, JavaScript) (Served frontend UI/UX)
### **Tools** 
- Bash (local scripting)
- AWS CLI (API calls for certain outputs, configuration)
- Git (version control)
- tmux, nvim (enhanced efficiency for local production)


