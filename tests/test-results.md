# Test Results

**Date:** 2026-03-09
**AWS Account:** 677746514416
**Region:** us-east-1
**Instance:** i-06c37f7d08d0c85a2 (t3.micro, name: cloudwatch)

---

## Test 1: SNS Pipeline Verification — PASSED

| Step | Result |
|---|---|
| SNS topic created | `arn:aws:sns:us-east-1:677746514416:CloudWatchAlerts` |
| Email subscription created | rizwan.nasir@hotmail.com — pending confirmation |
| Confirmation email received | Yes |
| Subscription confirmed | Yes — `SubscriptionsConfirmed: 1` |
| Test message published | MessageId: `cb93a258-4d93-54a1-a5bc-c070bf582cc2` |
| Test email received | Yes |

**Outcome:** SNS topic and email subscription fully operational.

---

## Test 2: CPU Alarm — Manual State Trigger — PASSED

| Step | Result |
|---|---|
| Alarm forced to ALARM | State: `ALARM`, reason: "Manual test: validating SNS notification pipeline" |
| ALARM email received | Yes |
| Alarm reset to OK | State: `OK`, reason: "Stress test complete - resetting to OK" |
| OK email received | Yes (OKActions configured on this alarm) |

**Outcome:** Full alarm → SNS → email pipeline verified.

---

## Test 3: CPU Alarm — Real Metric Trigger — PASSED

| Step | Result |
|---|---|
| Script copied to instance | Success (ubuntu@44.220.45.168) |
| Script launched in background | PID: 7522 |
| CPU saturation confirmed | `%Cpu(s): 100.0 us` — both vCPUs at 100% |

**CloudWatch CPU Metrics Observed:**

| Timestamp (UTC) | CPU % |
|---|---|
| 2026-03-09 17:02 | 0.41% (baseline) |
| 2026-03-09 17:07 | 44.73% (stress starting) |
| 2026-03-09 17:12 | 99.99% |
| 2026-03-09 17:17 | 99.99% |

**Alarm Transition:**

| Time (UTC+1) | State | Reason |
|---|---|---|
| 17:07:27 | OK | Alarm created |
| 17:21:16 | ALARM | "2 datapoints [99.99 (16:16:00), 99.99 (16:11:00)] were greater than threshold (80.0)" |
| 17:29:16 | OK | "1 datapoint [53.79 (16:24:00)] was not greater than threshold (80.0)" |

**Outcome:** Alarm correctly fired after 2 consecutive evaluation periods above 80%. ALARM and OK emails received. Stress processes killed after test.

---

## Test 4: Error Rate Alarm — Log Injection — PASSED

| Step | Result |
|---|---|
| 20 ERROR entries written to log file | Success — `application.log` updated |
| CloudWatch agent shipped logs | Entries appeared in `/aws/application/api` |
| Alarm evaluation period | 1 × 5 minutes |

**Alarm Transition:**

| Time (UTC+1) | State | Reason |
|---|---|---|
| 17:08:17 | INSUFFICIENT_DATA | Alarm created |
| 17:29:38 | ALARM | "1 datapoint [20.0 (16:24:00)] was greater than threshold (10.0)" |

**Outcome:** 20 errors in one evaluation window (threshold: 10) triggered the alarm. Email notification received.

---

## Test 5: Memory and Disk Alarms — Observation — PARTIAL

| Alarm | State | Notes |
|---|---|---|
| HighMemoryUtilization | INSUFFICIENT_DATA | CloudWatch Agent `mem` plugin not enabled in config |
| LowDiskSpace | INSUFFICIENT_DATA | CloudWatch Agent `disk` plugin not enabled in config |

**Alarm configurations verified as correct:**
- HighMemoryUtilization: namespace=CWAgent, metric=MemoryUtilization, threshold=85%, 2 periods
- LowDiskSpace: namespace=CWAgent, metric=disk_used_percent, threshold=80%, 1 period, path=/

**Resolution required:** Add `mem` and `disk` sections to `/opt/aws/amazon-cloudwatch-agent/etc/config.json` and restart the agent.

---

## Summary

| Alarm | Triggered | Email Received | State |
|---|---|---|---|
| HighCPUUtilization | Yes (real + manual) | Yes | OK |
| HighErrorRate | Yes (log injection) | Yes | ALARM |
| HighMemoryUtilization | No (agent config gap) | N/A | INSUFFICIENT_DATA |
| LowDiskSpace | No (agent config gap) | N/A | INSUFFICIENT_DATA |

**2 of 4 alarms fully validated end-to-end. 2 alarms configured correctly but pending CloudWatch Agent metric plugin activation.**
