# Lab M6.02 - Create Basic Threshold Alert

## Overview

This lab implements a CloudWatch-based alerting strategy for a t3.micro EC2 instance running a Flask API. Alerts are delivered via Amazon SNS email notifications when key resource metrics exceed defined thresholds. The strategy monitors CPU utilization (AWS/EC2 namespace), memory and disk usage (via CloudWatch Agent custom metrics), and application error rate (derived from a CloudWatch Logs metric filter on structured application logs).

## Alarms Created

| Alarm Name | Metric | Namespace | Threshold | Evaluation Period |
|---|---|---|---|---|
| HighCPUUtilization | CPUUtilization | AWS/EC2 | > 80% | 2 × 5 min (10 min) |
| HighMemoryUtilization | MemoryUtilization | CWAgent | > 85% | 2 × 5 min (10 min) |
| LowDiskSpace | disk_used_percent | CWAgent | > 80% | 1 × 5 min |
| HighErrorRate | ErrorCount | Application | > 10 per 5 min | 1 × 5 min |

## Threshold Rationale

See [config/thresholds.md](config/thresholds.md) for detailed reasoning behind each threshold value.

In summary:
- **80% CPU / 10 min** — leaves headroom above normal load while filtering transient spikes
- **85% memory / 10 min** — catches sustained pressure before swap degrades latency
- **80% disk / 5 min** — single period sufficient; disk grows monotonically
- **10 errors / 5 min** — zero errors is normal; 10 catches systematic failures quickly

## Testing

See [tests/test-plan.md](tests/test-plan.md) for the full test plan and [tests/test-results.md](tests/test-results.md) for results.

### CPU Alarm
A Python multi-process stress script (`cpu_load.py`) was deployed to the EC2 instance and ran all vCPUs at 100% for 15 minutes. After two evaluation periods CloudWatch transitioned `HighCPUUtilization` to `ALARM` state and an SNS email notification was delivered.

### Error Rate Alarm
The application uses structlog JSON-format logging. To match the space-separated metric filter pattern, 20 ERROR log entries were written directly to the application log file. The CloudWatch agent shipped them to the `/aws/application/api` log group. Within one 5-minute window the `HighErrorRate` alarm fired (20 > threshold of 10).

## Screenshots

| # | Screenshot | Description |
|---|---|---|
| 01 | [SNS Topic](screenshots/01-sns-topic.png) | SNS topic `CloudWatchAlerts` created with confirmed email subscription |
| 02 | [Email Confirmation](screenshots/02-email-confirmation.png) | AWS subscription confirmation email received and clicked |
| 03 | [Alarm OK State](screenshots/03-alarm-ok-state.png) | `HighCPUUtilization` alarm in OK state after stress test ended |
| 04 | [Alarm ALARM State](screenshots/04-alarm-alarm-state.png) | `HighCPUUtilization` alarm in ALARM state during stress test |
| 05 | [Email Notification](screenshots/05-email-notification.png) | SNS alarm email received in inbox |

## Challenges & Solutions

**Wrong SSH user**
Initial SCP attempts used `ec2-user`. The AMI is Ubuntu-based, so the correct user is `ubuntu`. Switching the username resolved the connection immediately.

**Metric filter pattern vs. structured logs**
The CloudWatch Logs metric filter `[timestamp, request_id, level = "ERROR", ...]` uses space-separated field matching. The Flask application writes JSON log lines via structlog, which do not match. For the test, ERROR entries were written in the expected space-separated format. In production the filter should use JSON syntax: `{ $.level = "ERROR" }`.

**Memory and Disk alarms stuck in INSUFFICIENT_DATA**
These alarms depend on the CloudWatch Agent publishing `MemoryUtilization` and `disk_used_percent` metrics. While the agent was running, the `mem` and `disk` plugins were not enabled in the agent config (`/opt/aws/amazon-cloudwatch-agent/etc/config.json`). Adding those sections and restarting the agent would activate these alarms.

## Repository Structure

```
ce-lab-threshold-alerts/
├── README.md
├── config/
│   ├── sns-topic-config.txt      # SNS topic details and subscription info
│   ├── alarm-configs.txt         # Full alarm configuration with CLI commands
│   └── thresholds.md             # Rationale for each threshold value
├── tests/
│   ├── test-plan.md              # Step-by-step test procedures
│   └── test-results.md           # Actual test outcomes and metric data
└── screenshots/
    ├── 01-sns-topic.png
    ├── 02-email-confirmation.png
    ├── 03-alarm-ok-state.png
    ├── 04-alarm-alarm-state.png
    └── 05-email-notification.png
```
