# Lab M6.02 - Create Basic Threshold Alert

## Overview

This lab implements a CloudWatch-based alerting strategy for an EC2 instance running a Flask API. Alerts are delivered via SNS email notifications when key resource metrics exceed defined thresholds. The strategy covers CPU utilization (AWS/EC2 namespace), memory and disk (via CloudWatch Agent custom metrics), and application error rate (derived from structured log metric filters).

## Alarms Created

| Alarm Name | Metric | Namespace | Threshold | Evaluation Period |
|---|---|---|---|---|
| HighCPUUtilization | CPUUtilization | AWS/EC2 | > 80% | 2 × 5 min (10 min) |
| HighMemoryUtilization | MemoryUtilization | CWAgent | > 85% | 2 × 5 min (10 min) |
| LowDiskSpace | disk_used_percent | CWAgent | > 80% | 1 × 5 min |
| HighErrorRate | ErrorCount | Application | > 10 per 5 min | 1 × 5 min |

## Threshold Rationale

**HighCPUUtilization – 80%**
A t3.micro instance under normal API load runs well below 40% CPU. The 80% threshold leaves a safe buffer before performance degrades while still catching runaway processes or traffic spikes. Two evaluation periods (10 min total) prevent false positives from short transient spikes.

**HighMemoryUtilization – 85%**
The instance has ~914 MB RAM. At 85% (~777 MB used) the OS starts swapping aggressively, causing latency spikes. Two periods ensure the alert reflects sustained pressure, not a brief GC pause.

**LowDiskSpace – 80%**
At 80% disk utilization there is still time to react before the disk fills completely. A single evaluation period is used because disk usage grows monotonically — there is no value in waiting for a second period once the threshold is crossed.

**HighErrorRate – 10 errors per 5 minutes**
Normal API traffic produces zero ERROR-level log entries. A threshold of 10 errors per 5-minute window gives a meaningful signal that something is systematically failing without alerting on isolated one-off errors.

## Setup Commands

### 1. Create SNS Topic and Email Subscription

```bash
# Create topic
TOPIC_ARN=$(aws sns create-topic \
  --name CloudWatchAlerts \
  --tags Key=Environment,Value=Production \
  --query 'TopicArn' \
  --output text)

echo "Topic ARN: $TOPIC_ARN"

# Subscribe email (replace with your address)
aws sns subscribe \
  --topic-arn $TOPIC_ARN \
  --protocol email \
  --notification-endpoint your-email@example.com
```

> **Important:** Check your inbox and click the AWS confirmation link before proceeding.

### 2. CPU Alarm

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

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
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --alarm-actions $TOPIC_ARN \
  --ok-actions $TOPIC_ARN \
  --treat-missing-data notBreaching
```

### 3. Memory Alarm (requires CloudWatch Agent)

```bash
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
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --alarm-actions $TOPIC_ARN
```

### 4. Disk Space Alarm (requires CloudWatch Agent)

```bash
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
  --dimensions Name=InstanceId,Value=$INSTANCE_ID Name=path,Value=/ \
  --alarm-actions $TOPIC_ARN
```

### 5. Application Error Rate Alarm

```bash
# Create metric filter on application log group
aws logs put-metric-filter \
  --log-group-name /aws/application/api \
  --filter-name ErrorCount \
  --filter-pattern '[timestamp, request_id, level = "ERROR", ...]' \
  --metric-transformations \
    metricName=ErrorCount,metricNamespace=Application,metricValue=1

# Create alarm on that metric
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
  --alarm-actions $TOPIC_ARN
```

## Testing

### CPU Alarm Test

The `cpu_load.py` script was copied to the EC2 instance and launched in the background:

```bash
scp -i bootcamp-week2-key.pem cpu_load.py ubuntu@<EC2-IP>:~/
ssh -i bootcamp-week2-key.pem ubuntu@<EC2-IP> \
  "nohup python3 ~/cpu_load.py > ~/cpu_load.log 2>&1 &"
```

CPU immediately reached **100%** (all vCPUs saturated). After two 5-minute evaluation periods CloudWatch transitioned the alarm to `ALARM` state and sent an SNS email notification. The stress processes were then killed and the alarm returned to `OK`.

### Error Rate Alarm Test

The application (`server.py`) uses structured JSON logging (structlog). The CloudWatch Logs metric filter expects space-separated fields, so ERROR entries were written directly to the tailed log file:

```bash
for i in $(seq 1 20); do
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) req-$(cat /proc/sys/kernel/random/uuid | cut -d- -f1) ERROR Unhandled exception in request handler" \
    >> /home/ubuntu/app/application.log
done
```

The CloudWatch agent shipped the 20 entries to the `/aws/application/api` log group. Within one evaluation period the `HighErrorRate` alarm transitioned to `ALARM` (20 errors > threshold of 10) and an email notification was delivered.

### Manual Alarm State Test

To verify the full SNS → email pipeline before real metrics arrived:

```bash
aws cloudwatch set-alarm-state \
  --alarm-name HighCPUUtilization \
  --state-value ALARM \
  --state-reason "Stress test: manually triggering alarm to validate SNS notification pipeline"
```

## Screenshots

- SNS topic and confirmed subscription
- Alarm in OK and ALARM states
- Email notification received

> Add your screenshots here.

## Challenges & Solutions

**Challenge 1 – Wrong SSH user**
Initial SCP attempts used `ec2-user` but the AMI is Ubuntu-based, so the correct default user is `ubuntu`. Switched the username and the connection succeeded immediately.

**Challenge 2 – Metric filter pattern vs. structured logs**
The CloudWatch Logs metric filter pattern `[timestamp, request_id, level = "ERROR", ...]` uses space-separated field matching. The application writes JSON-formatted log lines via structlog, which do not match this pattern. To trigger the alarm during testing, ERROR log entries were written directly in the expected space-separated format. In production the filter pattern should be updated to use a JSON filter (e.g., `{ $.level = "ERROR" }`) to match the actual log format.

**Challenge 3 – INSUFFICIENT_DATA for Memory and Disk alarms**
These alarms depend on metrics published by the CloudWatch Agent (`CWAgent` namespace). While the agent was running, the `mem_used_percent` and `disk_used_percent` metric collection was not enabled in the agent config at the time of testing. To fully activate these alarms, the agent config (`/opt/aws/amazon-cloudwatch-agent/etc/config.json`) must include the `metrics` section with `mem` and `disk` plugins.
