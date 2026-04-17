# MaroonLedger

*A production-grade personal finance platform on AWS — built to develop hands-on expertise across cloud engineering, DevOps, security, and networking.*

**MaroonLedger** is an end-to-end cloud engineering project that implements a production-grade personal finance platform on AWS. It demonstrates realistic cloud capabilities including secure user authentication and data storage, full CRUD operations over a relational database, and a scalable, highly available infrastructure deployed across multiple Availability Zones.

This project was built to demonstrate hands-on experience with the full AWS service ecosystem — from networking and container orchestration to identity, observability, and infrastructure-as-code — in a realistic, resume-ready portfolio piece

---------------------------------------------------------------------------------------------------

# Architecture

![MaroonLedger Architecture Diagram](docs/images/cep-v1.png)

# Architecture Walkthrough

## Layer 1: DNS & Edge

This layer is the public entry point for the application: resolving the domain, serving content from edge locations, and filtering malicious traffic before it reaches the VPC. It's made up of three services: **Amazon Route 53**, **Amazon CloudFront**, and **AWS WAF**.

### Amazon Route 53

**What it is.** AWS's managed DNS service, backed by a 100% uptime SLA.

**Role in this architecture.** Route 53 hosts the authoritative DNS records for the app's domain and resolves user requests to the CloudFront distribution using an alias record.

**Why this choice.** Alias records resolve directly to AWS resources without the extra hop of a standard DNS lookup, and Route 53 integrates cleanly with Cognito, CloudFront, and ACM. It also supports health checks and failover routing if the project ever goes multi-region.

### Amazon CloudFront

**What it is.** AWS's global CDN, delivering content from 400+ edge locations close to end users.

**Role in this architecture.** CloudFront is the single public entry point for all traffic. It serves the static frontend from an S3 origin and forwards `/api/*` requests to the ALB origin via path-based routing. TLS is terminated at the edge using an ACM certificate in `us-east-1`.

**Why this choice.** One distribution in front of both origins gives a unified domain, edge caching for static assets, and a single attachment point for WAF. It also includes AWS Shield Standard for free, providing baseline DDoS protection at the edge.

### AWS WAF

**What it is.** A managed Web Application Firewall that inspects HTTP/HTTPS requests and blocks anything matching its rule sets.

**Role in this architecture.** WAF attaches to the CloudFront distribution via a Web ACL, evaluating every request at the edge. Attacks get blocked before they reach S3 or the ALB, and both origins are protected under one policy.

**Why this choice.** Edge-deployed WAF rejects attacks closer to the source and benefits from CloudFront's caching, which lowers evaluation volume and cost. It also layers cleanly with Shield Standard for volumetric protection.


## Layer 2: Identity

This layer handles user authentication and session management, sitting alongside the edge layer as part of the user-facing surface. It's built around a single service: **Amazon Cognito**.

### Amazon Cognito

**What it is.** AWS's managed identity service, providing user directories, authentication flows, and token issuance via OAuth 2.0 and OIDC.

**Role in this architecture.** Cognito is the first thing a user interacts with. A Cognito User Pool handles sign-up, sign-in, password resets, and MFA enrollment through Cognito's Hosted UI, and issues a JWT on successful authentication. The frontend attaches that JWT to API calls, and the ECS tasks validate it against Cognito's JWKS endpoint before serving the request.

**Why this choice.** Cognito removes the need to build and maintain a custom auth stack — password hashing, session storage, MFA, token rotation, account recovery — while still integrating natively with the rest of the AWS ecosystem. The Hosted UI handles the login page out of the box, removing the need to implement Cognito's SRP auth flow in the frontend. A self-hosted solution would mean more infrastructure to secure and audit for no meaningful gain on a project this size.


