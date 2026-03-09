# Threshold Rationale

## Instance Context

| Property | Value |
|---|---|
| Instance ID | i-06c37f7d08d0c85a2 |
| Instance Type | t3.micro |
| vCPUs | 2 |
| RAM | ~914 MB |
| OS | Ubuntu (Linux) |
| Application | Flask API (structlog JSON logging) |

---

## HighCPUUtilization — 80% over 10 minutes

**Threshold: > 80%**
**Evaluation: 2 × 5-minute periods**

A t3.micro under normal API load stays well below 40% CPU. The 80% threshold provides a meaningful signal that something is wrong (runaway process, traffic spike, or poorly optimised job) without alerting during routine short bursts.

Two evaluation periods (10 minutes total) are required so that transient spikes — such as a scheduled cron job, a GC pause, or a burst of concurrent requests — do not produce false positives. Sustained 80%+ CPU for 10 minutes indicates a genuine problem requiring intervention.

**Why not lower (e.g., 60%)?**
Too many false positives during normal deploy or warm-up bursts.

**Why not higher (e.g., 95%)?**
At 95% the instance is already degraded; response times will have spiked and user impact is already occurring.

---

## HighMemoryUtilization — 85% over 10 minutes

**Threshold: > 85%**
**Evaluation: 2 × 5-minute periods**

At ~914 MB total RAM, 85% equates to approximately 777 MB in use. Beyond this point the OS begins actively swapping to disk, causing significant API latency increases. Two evaluation periods guard against short-lived spikes from in-memory caching or temporary large payloads.

**Requires:** CloudWatch Agent with `mem_used_percent` metric collection enabled.

---

## LowDiskSpace — 80% used

**Threshold: > 80%**
**Evaluation: 1 × 5-minute period**

Disk usage is monotonically increasing under normal operation. Once 80% is reached there is still ~20% headroom — enough time to investigate and act (clear old logs, extend the volume, or redeploy) before the disk fills completely and the application starts failing to write logs or temp files.

A single evaluation period is appropriate because disk growth is gradual and does not produce transient spikes; any reading above 80% is a genuine signal requiring attention.

**Requires:** CloudWatch Agent with `disk_used_percent` metric collection enabled for path `/`.

---

## HighErrorRate — 10 errors per 5 minutes

**Threshold: > 10 errors in a 5-minute window**
**Evaluation: 1 × 5-minute period**

Under normal operation the application produces zero ERROR-level log entries. A threshold of 10 allows for a small number of isolated errors (network hiccups, retried requests) before raising an alert, while still catching systematic failures — such as a bad deployment, a downstream service outage, or an unhandled exception path — quickly within the first 5-minute window.

A single evaluation period is used because error rates can spike and resolve within minutes; waiting for two periods would delay the alert by 5 minutes during which many requests could be failing.

**Metric source:** CloudWatch Logs metric filter on `/aws/application/api` log group, counting log lines matching `level = "ERROR"`.
