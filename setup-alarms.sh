#!/usr/bin/env bash
# setup-alarms.sh
# Creates SNS topic, email subscription, and all CloudWatch alarms.
# Usage: EMAIL=you@example.com bash setup-alarms.sh

set -euo pipefail

EMAIL="${EMAIL:-your-email@example.com}"

echo "==> Creating SNS topic..."
TOPIC_ARN=$(aws sns create-topic \
  --name CloudWatchAlerts \
  --tags Key=Environment,Value=Production \
  --query 'TopicArn' \
  --output text)
echo "    Topic ARN: $TOPIC_ARN"

echo "==> Subscribing $EMAIL to topic..."
aws sns subscribe \
  --topic-arn "$TOPIC_ARN" \
  --protocol email \
  --notification-endpoint "$EMAIL"
echo "    Check your inbox and confirm the subscription before alarms will deliver email."

echo "==> Discovering running EC2 instance..."
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)
echo "    Instance ID: $INSTANCE_ID"

echo "==> Creating HighCPUUtilization alarm..."
aws cloudwatch put-metric-alarm \
  --alarm-name HighCPUUtilization \
  --alarm-description "Alert when CPU exceeds 80% for 10 minutes" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --alarm-actions "$TOPIC_ARN" \
  --ok-actions "$TOPIC_ARN" \
  --treat-missing-data notBreaching

echo "==> Creating HighMemoryUtilization alarm..."
aws cloudwatch put-metric-alarm \
  --alarm-name HighMemoryUtilization \
  --alarm-description "Alert when memory exceeds 85%" \
  --metric-name MemoryUtilization \
  --namespace CWAgent \
  --statistic Average \
  --period 300 \
  --threshold 85 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --alarm-actions "$TOPIC_ARN"

echo "==> Creating LowDiskSpace alarm..."
aws cloudwatch put-metric-alarm \
  --alarm-name LowDiskSpace \
  --alarm-description "Alert when disk usage exceeds 80%" \
  --metric-name disk_used_percent \
  --namespace CWAgent \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" Name=path,Value=/ \
  --alarm-actions "$TOPIC_ARN"

echo "==> Creating log metric filter for ErrorCount..."
aws logs create-log-group --log-group-name /aws/application/api 2>/dev/null || true
aws logs put-metric-filter \
  --log-group-name /aws/application/api \
  --filter-name ErrorCount \
  --filter-pattern '[timestamp, request_id, level = "ERROR", ...]' \
  --metric-transformations \
    metricName=ErrorCount,metricNamespace=Application,metricValue=1

echo "==> Creating HighErrorRate alarm..."
aws cloudwatch put-metric-alarm \
  --alarm-name HighErrorRate \
  --alarm-description "Alert when error rate exceeds 10 per 5 minutes" \
  --metric-name ErrorCount \
  --namespace Application \
  --statistic Sum \
  --period 300 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions "$TOPIC_ARN"

echo ""
echo "==> All alarms created. Current state:"
aws cloudwatch describe-alarms \
  --alarm-names HighCPUUtilization HighMemoryUtilization LowDiskSpace HighErrorRate \
  --query 'MetricAlarms[*].{Alarm:AlarmName,State:StateValue,Threshold:Threshold}' \
  --output table
