# Alerting: an SNS topic, the CloudWatch alarms that publish to it, and the
# EventBridge rule that turns GuardDuty findings into notifications.
#
# CloudTrail and GuardDuty (in main.tf) record and detect. Nothing in that pair
# tells a human something happened -- this file is what closes that gap.

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"

  # SNS messages can contain finding details, so the topic is encrypted. The
  # AWS-managed key is used rather than the RDS customer-managed key: sharing
  # one key across unrelated purposes couples their key policies together.
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

# Subscriptions need confirming by the recipient, so this is only created when
# an address is supplied. Confirmation arrives as an email with a link.
resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- GuardDuty findings -----------------------------------------------------

# GuardDuty writes findings to its console whether or not anyone looks. This
# rule forwards the ones worth waking up for.
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "${var.project_name}-guardduty-findings"
  description = "Route medium and high severity GuardDuty findings to SNS"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      # GuardDuty severity is 1-8.9. Filtering at 4.0 keeps low-severity
      # informational findings out of the alert path -- an alert channel that
      # is mostly noise stops being read.
      severity = [{ numeric = [">=", 4.0] }]
    }
  })

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.alerts.arn

  # The raw finding is large and hard to read in an email. This extracts the
  # fields that decide whether to act.
  input_transformer {
    input_paths = {
      severity    = "$.detail.severity"
      type        = "$.detail.type"
      description = "$.detail.description"
      region      = "$.detail.region"
    }
    input_template = "\"GuardDuty <severity> severity finding in <region>: <type>. <description>\""
  }
}

# EventBridge is a service principal, not an IAM role, so permission to publish
# is granted by the topic's own policy.
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.alerts.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.guardduty_findings.arn
          }
        }
      },
      {
        Sid    = "AllowCloudWatchAlarmsPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# --- Service health alarms --------------------------------------------------

# The application is returning errors to users. This is the alarm that
# corresponds most directly to "the site is broken".
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  count = var.alb_arn_suffix != "" ? 1 : 0

  alarm_name          = "${var.project_name}-alb-5xx"
  alarm_description   = "Application is returning server errors through the ALB"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  # No errors in a period reports as no data, not zero. Without this the alarm
  # sits in INSUFFICIENT_DATA whenever the service is healthy.
  treat_missing_data = "notBreaching"

  dimensions    = { LoadBalancer = var.alb_arn_suffix }
  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# Every task failing its health check means the service is down even though
# the ALB itself is fine.
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  count = var.alb_arn_suffix != "" && var.target_group_arn_suffix != "" ? 1 : 0

  alarm_name          = "${var.project_name}-no-healthy-targets"
  alarm_description   = "No healthy ECS tasks are registered with the target group"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  count = var.db_instance_identifier != "" ? 1 : 0

  alarm_name          = "${var.project_name}-rds-cpu-high"
  alarm_description   = "RDS CPU sustained above 80%"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions    = { DBInstanceIdentifier = var.db_instance_identifier }
  alarm_actions = [aws_sns_topic.alerts.arn]
}

# db.t4g.micro allows roughly 340 connections. Alarming well below that leaves
# room to react before the pool starts refusing writes.
resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  count = var.db_instance_identifier != "" ? 1 : 0

  alarm_name          = "${var.project_name}-rds-connections-high"
  alarm_description   = "RDS connection count approaching the instance limit"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 150
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions    = { DBInstanceIdentifier = var.db_instance_identifier }
  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  count = var.db_instance_identifier != "" ? 1 : 0

  alarm_name          = "${var.project_name}-rds-storage-low"
  alarm_description   = "RDS free storage below 2 GB"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = 2147483648 # 2 GiB in bytes
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions    = { DBInstanceIdentifier = var.db_instance_identifier }
  alarm_actions = [aws_sns_topic.alerts.arn]
}
