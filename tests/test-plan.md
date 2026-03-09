# Test Plan

## Objective

Verify that each CloudWatch alarm transitions to `ALARM` state and delivers an SNS email notification when its threshold is exceeded.

---

## Test 1: SNS Pipeline Verification

**Goal:** Confirm the SNS topic and email subscription work before any alarms fire.

**Steps:**
1. Create SNS topic `CloudWatchAlerts`
2. Subscribe `rizwan.nasir@hotmail.com` via email protocol
3. Click the AWS confirmation link in the received email
4. Publish a manual test message:
   ```bash
   aws sns publish \
     --topic-arn $TOPIC_ARN \
     --subject "Test Alert" \
     --message "This is a test alert from CloudWatch"
   ```
5. Verify email is received in inbox

**Pass Criteria:** Email received with subject "Test Alert"

---

## Test 2: CPU Alarm — Manual State Trigger

**Goal:** Validate the alarm → SNS → email pipeline without waiting for real metrics.

**Steps:**
1. Force alarm into `ALARM` state:
   ```bash
   aws cloudwatch set-alarm-state \
     --alarm-name HighCPUUtilization \
     --state-value ALARM \
     --state-reason "Manual test: validating SNS notification pipeline"
   ```
2. Check email for ALARM notification
3. Reset to OK:
   ```bash
   aws cloudwatch set-alarm-state \
     --alarm-name HighCPUUtilization \
     --state-value OK \
     --state-reason "Manual test complete"
   ```
4. Check email for OK notification (OKActions configured)

**Pass Criteria:** Two emails received — one for ALARM, one for OK

---

## Test 3: CPU Alarm — Real Metric Trigger (Stress Test)

**Goal:** Trigger `HighCPUUtilization` with actual CPU load to validate the full metric → alarm → SNS pipeline.

**Steps:**
1. Copy stress script to EC2 instance:
   ```bash
   scp -i bootcamp-week2-key.pem cpu_load.py ubuntu@44.220.45.168:~/
   ```
2. Launch script in background:
   ```bash
   ssh -i bootcamp-week2-key.pem ubuntu@44.220.45.168 \
     "nohup python3 ~/cpu_load.py > ~/cpu_load.log 2>&1 &"
   ```
3. Confirm CPU saturation:
   ```bash
   ssh -i bootcamp-week2-key.pem ubuntu@44.220.45.168 "top -bn1 | head -4"
   # Expected: %Cpu(s): ~100.0 us
   ```
4. Wait 10 minutes for 2 evaluation periods to complete
5. Poll alarm state:
   ```bash
   aws cloudwatch describe-alarms \
     --alarm-names HighCPUUtilization \
     --query 'MetricAlarms[0].StateValue'
   ```
6. Verify ALARM email received
7. Stop stress processes and verify alarm returns to OK

**Pass Criteria:**
- CPU metric shows > 80% in CloudWatch console
- Alarm transitions to `ALARM` after 2 periods
- ALARM email received
- Alarm returns to `OK` after load removed

---

## Test 4: Error Rate Alarm — Log Injection

**Goal:** Trigger `HighErrorRate` by writing ERROR log entries to the application log tailed by the CloudWatch agent.

**Background:** The application (`server.py`) uses structlog JSON format. The metric filter pattern uses space-separated field matching, so ERROR entries must be written in the matching format.

**Steps:**
1. SSH to instance and inject 20 ERROR entries:
   ```bash
   ssh -i bootcamp-week2-key.pem ubuntu@44.220.45.168 \
     'for i in $(seq 1 20); do
       echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) req-$(cat /proc/sys/kernel/random/uuid | cut -d- -f1) ERROR Unhandled exception in request handler" \
         >> /home/ubuntu/app/application.log
     done'
   ```
2. Wait ~2 minutes for CloudWatch agent to ship logs and alarm to evaluate
3. Check alarm state:
   ```bash
   aws cloudwatch describe-alarms --alarm-names HighErrorRate \
     --query 'MetricAlarms[0].{State:StateValue,Reason:StateReason}'
   ```
4. Verify ALARM email received

**Pass Criteria:**
- CloudWatch Logs shows 20 new ERROR entries in `/aws/application/api`
- `HighErrorRate` transitions to `ALARM` (20 > threshold of 10)
- Email notification received

---

## Test 5: Memory and Disk Alarms — Observation

**Goal:** Confirm alarms are correctly configured (thresholds, dimensions, actions).

**Note:** These alarms require the CloudWatch Agent `mem` and `disk` plugins to be enabled in the agent config. They will remain in `INSUFFICIENT_DATA` until those metrics are being published.

**Steps:**
1. Describe alarm configurations:
   ```bash
   aws cloudwatch describe-alarms \
     --alarm-names HighMemoryUtilization LowDiskSpace \
     --query 'MetricAlarms[*].{Name:AlarmName,Namespace:Namespace,Metric:MetricName,Threshold:Threshold,State:StateValue}'
   ```
2. Verify alarm ARNs, dimensions, and SNS actions are correct

**Pass Criteria:** Alarms exist with correct configuration; noted as pending CloudWatch Agent metric plugin activation
