# Architecture inventory

The diagrams in `docs/images/` are generated from `docs/diagrams/`, and every box
on them maps to something in `infrastructure/`. This is the mapping, so the
diagrams can be checked rather than trusted.

It exists because the previous diagram could not be. It showed four EC2
instances inside the ECS cluster, an Auto Scaling boundary, and one ALB per
availability zone. None of the three had ever been true. There is no
`aws_instance`, no `aws_autoscaling_group`, and one `aws_lb`. A diagram nobody
can check against the code drifts silently, and this one had drifted for months.

## Diagram 1: core

| Box | Backed by |
|---|---|
| Route 53 | `modules/dns` &#183; `aws_route53_zone.main`, `aws_route53_record.apex` in the dev root |
| CloudFront | `modules/cdn` &#183; `aws_cloudfront_distribution.main`, `aws_cloudfront_origin_access_control.s3` |
| S3 (React bundle) | `modules/cdn` &#183; `aws_s3_bucket.frontend` + policy, OAC, SSE, public-access-block |
| WAF | `modules/cdn` &#183; `aws_wafv2_web_acl.main`, `var.enable_waf` |
| Cognito | `modules/cognito` &#183; user pool, hosted-UI domain, app client |
| Bedrock | no Terraform resource; reached at runtime under `aws_iam_role_policy.ecs_task_bedrock` |
| ECR | `modules/ecr` &#183; `aws_ecr_repository.app` |
| Secrets Manager | `modules/rds` &#183; RDS-managed master secret, read by `aws_iam_role_policy.ecs_secrets` |
| KMS | `modules/kms` &#183; community `terraform-aws-modules/kms/aws` |
| VPC, subnets, IGW, NAT | `modules/vpc` &#183; community `terraform-aws-modules/vpc/aws`, three tiers across two AZs |
| Application Load Balancer | `modules/alb` &#183; community `terraform-aws-modules/alb/aws`. **One** regional resource, subnets in both AZs |
| ECS Fargate tasks | `modules/ecs` &#183; cluster, `FARGATE` capacity provider, task definition, service at `desired_count = 2` |
| Execution / task roles | `modules/ecs` &#183; `aws_iam_role.ecs_execution` and `.ecs_task`, kept separate on purpose |
| RDS primary / standby | `modules/rds` &#183; community `terraform-aws-modules/rds/aws`, `var.rds_multi_az` |
| VPC endpoints | `modules/vpc-endpoints` &#183; `aws_vpc_endpoint.interface` (ecr.api, ecr.dkr, logs, secretsmanager) + `.s3` gateway |
| Observability row | `modules/observability` &#183; CloudWatch log group and 5 alarms, SNS topic + subscription, CloudTrail, GuardDuty, Config |

## Diagram 2: analytics

| Box | Backed by |
|---|---|
| ECS Fargate task (producer) | `app/internal/pipeline` &#183; Firehose emitter, permitted by `aws_iam_role_policy.ecs_task_firehose` |
| Kinesis Firehose | `modules/firehose` &#183; `aws_kinesis_firehose_delivery_stream.transactions` + role, policy, log group |
| S3 data lake / curated | `modules/datalake` &#183; `aws_s3_bucket.lake` + lifecycle, versioning, SSE, public-access-block |
| EventBridge Scheduler | `modules/glue` &#183; `aws_scheduler_schedule.nightly_etl` + `aws_iam_role.scheduler`. Targets the **Glue job** |
| Glue PySpark ETL | `modules/glue` &#183; `aws_glue_job.transactions_etl`, script uploaded as `aws_s3_object.etl_script` |
| Glue Data Catalog | `modules/glue` &#183; `aws_glue_catalog_database.analytics`, `aws_glue_catalog_table.transactions` |
| Athena | `modules/athena` &#183; `aws_athena_workgroup.analytics` + results bucket, lifecycle, SSE |

## Every resource, by module

| Module | Count | Resources |
|---|---|---|
| `alb` | 1 | `(community) terraform-aws-modules/alb/aws` |
| `athena` | 5 | `aws_s3_bucket.results`, `aws_s3_bucket_public_access_block.results`, `aws_s3_bucket_server_side_encryption_configuration.results`, `aws_s3_bucket_lifecycle_configuration.results`, `aws_athena_workgroup.analytics` |
| `cdn` | 8 | `aws_s3_bucket.frontend`, `aws_s3_bucket_public_access_block.frontend`, `aws_s3_bucket_ownership_controls.frontend`, `aws_s3_bucket_server_side_encryption_configuration.frontend`, `aws_cloudfront_origin_access_control.s3`, `aws_cloudfront_distribution.main`, `aws_s3_bucket_policy.frontend`, `aws_wafv2_web_acl.main` |
| `cognito` | 3 | `aws_cognito_user_pool.main`, `aws_cognito_user_pool_domain.main`, `aws_cognito_user_pool_client.web` |
| `datalake` | 5 | `aws_s3_bucket.lake`, `aws_s3_bucket_public_access_block.lake`, `aws_s3_bucket_server_side_encryption_configuration.lake`, `aws_s3_bucket_versioning.lake`, `aws_s3_bucket_lifecycle_configuration.lake` |
| `dns` | 7 | `aws_route53_zone.main`, `aws_acm_certificate.edge`, `aws_route53_record.edge_validation`, `aws_acm_certificate_validation.edge`, `aws_acm_certificate.alb`, `aws_route53_record.alb_validation`, `aws_acm_certificate_validation.alb` |
| `ecr` | 1 | `aws_ecr_repository.app` |
| `ecs` | 11 | `aws_ecs_cluster.main`, `aws_ecs_cluster_capacity_providers.main`, `aws_cloudwatch_log_group.ecs`, `aws_ecs_task_definition.app`, `aws_ecs_service.app`, `aws_iam_role.ecs_execution`, `aws_iam_role_policy_attachment.ecs_execution`, `aws_iam_role_policy.ecs_secrets`, `aws_iam_role.ecs_task`, `aws_iam_role_policy.ecs_task_bedrock`, `aws_iam_role_policy.ecs_task_firehose` |
| `firehose` | 4 | `aws_kinesis_firehose_delivery_stream.transactions`, `aws_cloudwatch_log_group.firehose`, `aws_iam_role.firehose`, `aws_iam_role_policy.firehose` |
| `glue` | 9 | `aws_iam_role.glue`, `aws_iam_role_policy.glue`, `aws_scheduler_schedule.nightly_etl`, `aws_iam_role.scheduler`, `aws_iam_role_policy.scheduler`, `aws_s3_object.etl_script`, `aws_glue_catalog_database.analytics`, `aws_glue_catalog_table.transactions`, `aws_glue_job.transactions_etl` |
| `kms` | 1 | `(community) terraform-aws-modules/kms/aws` |
| `observability` | 21 | `aws_sns_topic.alerts`, `aws_sns_topic_subscription.email`, `aws_cloudwatch_event_rule.guardduty_findings`, `aws_cloudwatch_event_target.guardduty_to_sns`, `aws_sns_topic_policy.alerts`, `aws_cloudwatch_metric_alarm.alb_5xx`, `aws_cloudwatch_metric_alarm.alb_unhealthy_hosts`, `aws_cloudwatch_metric_alarm.rds_cpu`, `aws_cloudwatch_metric_alarm.rds_connections`, `aws_cloudwatch_metric_alarm.rds_storage`, `aws_s3_bucket.cloudtrail`, `aws_s3_bucket_policy.cloudtrail`, `aws_cloudtrail.main`, `aws_guardduty_detector.main`, `aws_config_configuration_recorder.main`, `aws_config_delivery_channel.main`, `aws_config_configuration_recorder_status.main`, `aws_s3_bucket.config`, `aws_s3_bucket_policy.config`, `aws_iam_role.config`, `aws_iam_role_policy_attachment.config` |
| `rds` | 1 | `(community) terraform-aws-modules/rds/aws` |
| `security-groups` | 11 | `aws_security_group.alb`, `aws_vpc_security_group_ingress_rule.alb_from_cloudfront`, `aws_vpc_security_group_egress_rule.alb_out`, `aws_security_group.ecs`, `aws_vpc_security_group_ingress_rule.ecs_from_alb`, `aws_vpc_security_group_egress_rule.ecs_out`, `aws_security_group.rds`, `aws_vpc_security_group_ingress_rule.rds_from_ecs`, `aws_vpc_security_group_egress_rule.rds_out`, `aws_security_group.vpce`, `aws_vpc_security_group_ingress_rule.vpce_from_ecs` |
| `vpc` | 1 | `(community) terraform-aws-modules/vpc/aws` |
| `vpc-endpoints` | 2 | `aws_vpc_endpoint.interface`, `aws_vpc_endpoint.s3` |

Plus the dev root module's own `aws_route53_record.apex`, and the data root's
module wiring.

## Deliberately not drawn

Drawing everything is how a diagram becomes unreadable. Left off, with reasons:

- **Individual IAM policies.** The roles are drawn; the policies attached to them
  are not. Which role can reach what is stated on the arrows instead.
- **S3 bucket sub-resources.** Public-access-block, SSE, ownership controls,
  versioning, lifecycle. Five resources per bucket that would add five boxes and
  no understanding.
- **ACM certificates and their validation records.** Inert until `domain_name`
  is set.
- **Security group rules as boxes.** SG chaining is the point, so it is drawn as
  the direction of the arrows between tiers rather than as eight more nodes.
- **CloudWatch log groups.** Implied by the CloudWatch box.
- **The bootstrap stack** (state bucket). It exists to make the other stacks
  possible and is not part of the running architecture.

## Known divergences from what was actually deployed

The diagrams show the defaults, which is the architecture the repository
describes. The account it was deployed into is a vended sandbox whose SCPs
forbid several of them:

| Drawn | As deployed | Why |
|---|---|---|
| WAF on CloudFront | absent | SCP denies WAF at CloudFront scope |
| GuardDuty | absent | SCP denies GuardDuty |
| RDS Multi-AZ + standby | single-AZ | not available on the free tier |
| Firehose | absent | SCP denies Firehose org-wide |
| Bedrock serving inference | stub provider | account inference quota is 0 for every Claude model |
