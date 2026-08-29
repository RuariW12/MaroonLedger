output "cloudtrail_bucket_name" {
  description = "S3 bucket name for CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail.id
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = one(aws_guardduty_detector.main[*].id)
}

output "alerts_topic_arn" {
  description = "SNS topic receiving GuardDuty findings and CloudWatch alarms"
  value       = aws_sns_topic.alerts.arn
}
