# Lab M6.03 - Build Dashboard for Web Tier Health

## Dashboard Design Rationale

The dashboard is organized in five rows, each serving a distinct triage purpose:

**Row 1 — KPI strip (single-value widgets):** Four at-a-glance numbers across the full width — Request Rate, Error Rate %, P95 Latency, and Healthy Targets. These answer the question *"is something wrong right now?"* in under two seconds without scrolling.

**Row 2 — Golden Signals (time series, 3-hour window):** Four panels covering Traffic, Errors, Latency, and Saturation — the four signals from Google SRE. Placed immediately below the KPIs so the on-call engineer can see the trend behind each number and identify when a degradation started.

**Row 3 — EC2 Resource Utilization:** CPU, Memory, Network, and Disk on a 5-minute granularity. Intentionally placed *below* the golden signals because resource problems are typically a cause, not a symptom. You look here after the golden signals confirm something is wrong.

**Row 4 — Correlation View:** A single full-width chart overlaying Latency P95, Request Rate, 5XX Error Rate, and CPU on a dual Y-axis. Placed last because it is used for root cause analysis once an incident is identified — not for first-look triage.

Annotations are consistent across all time-series widgets:
- **Red horizontal lines** mark SLO thresholds (breach = immediate action)
- **Green vertical lines** mark the last deployment timestamp so regressions can be spotted instantly

---

## Widget Explanations

| Widget | Type | Metric Source | Purpose |
|---|---|---|---|
| Current Request Rate | Single Value | `AWS/ApplicationELB` RequestCount | Instant read of traffic volume hitting the ALB |
| Error Rate % | Single Value | Math: `(5XX / Total) × 100` | Derived error percentage — more meaningful than raw counts |
| P95 Latency | Single Value | `AWS/ApplicationELB` TargetResponseTime p95 | User-facing tail latency at a glance |
| Healthy Targets | Single Value | `AWS/ApplicationELB` HealthyHostCount | Count of targets passing ALB health checks |
| Traffic — Request Rate | Time Series | `AWS/ApplicationELB` RequestCount (1-min) | Traffic volume trend; capacity-limit annotation at 1000 req/min |
| Errors — HTTP Status Codes + Rate | Time Series | 5XX/4XX/2XX counts + math expressions on right axis | Stacked error counts with overlaid `%` rate on dual Y-axis; 1% SLO line |
| Latency — Response Time Percentiles | Time Series | TargetResponseTime p50 / p95 / p99 | Full percentile spread; SLO annotations at 500ms (P95) and 1s (P99) |
| Saturation — Target Health | Time Series | HealthyHostCount + UnHealthyHostCount | Tracks target churn; unhealthy spike correlates with 5XX spikes |
| CPU Utilization | Time Series | `AWS/EC2` CPUUtilization | Instance CPU with 80% warning threshold line |
| Memory Utilization | Time Series | `CWAgent` mem_used_percent | Requires CloudWatch Agent; 85% warning threshold line |
| Network In/Out | Time Series | `AWS/EC2` NetworkIn + NetworkOut | Bytes transferred; useful for detecting data-exfiltration or traffic asymmetry |
| Disk Usage | Time Series | `CWAgent` disk_used_percent (path=/) | Root volume utilisation; 80% warning threshold line |
| Correlation View | Time Series | Latency P95 + Request Rate + 5XX Rate % + CPU | Dual Y-axis overlay for root cause analysis — all four signals on one chart |

---

## Math Expressions Used

**Error Rate % (KPI widget)**
```json
[{"expression": "(m1/m2)*100", "label": "Error Rate %", "id": "e1"}]
```
`m1` = 5XX count, `m2` = total request count. Produces a percentage that scales correctly with traffic volume — raw error counts are misleading during traffic spikes or troughs.

**5XX Error Rate % (Errors time-series widget)**
```json
[{"expression": "(m5xx/mtotal)*100", "label": "5XX Error Rate %", "id": "e5xx", "yAxis": "right"}],
[{"expression": "(m4xx/mtotal)*100", "label": "4XX Error Rate %", "id": "e4xx", "yAxis": "right"}]
```
Raw counts on the left axis, derived rates on the right axis — both visible simultaneously for correlation without losing absolute numbers.

**Error Rate in Correlation View**
```json
[{"expression": "(mcorr_5xx/mcorr_total)*100", "label": "5XX Error Rate %", "id": "ecorr_rate", "yAxis": "right"}]
```
Same derivation re-applied in the correlation chart so all four signals are comparable on one canvas.

---

## Annotations Reference

| Widget | Horizontal Annotation | Vertical Annotation |
|---|---|---|
| Traffic — Request Rate | `1000 req/min` capacity limit (red) | Last deployment (green) |
| Errors — HTTP Status Codes | `1%` 5XX SLO on right axis (red) | Last deployment (green) |
| Latency — Percentiles | `500ms` P95 SLO + `1s` P99 SLO (red) | Last deployment (green) |
| Correlation View | `500ms` P95 SLO on left axis (red) | Last deployment (green) |
| CPU Utilization | `80%` alarm threshold (orange) | — |
| Memory Utilization | `85%` alarm threshold (orange) | — |
| Disk Usage | `80%` alarm threshold (orange) | — |

---

## How to Use This Dashboard

1. **Start at the KPI row** — four single-value widgets answer *"is anything broken right now?"*. If all green, no further action needed.

2. **Check Golden Signals for trends** — if a KPI is elevated, scroll to the Golden Signals row to see when it started and whether it is growing or recovering.

3. **Look for the deployment marker** — each time-series chart has a green vertical line at the last deployment timestamp. If degradation started at that line, the deploy is the likely cause.

4. **Check EC2 resources if Golden Signals are elevated** — high CPU or memory often explains latency increases. Cross-reference the CPU chart timestamp with the latency chart.

5. **Use the Correlation View for root cause** — the full-width bottom chart overlays Latency P95, Request Rate, 5XX Error Rate %, and CPU on a dual Y-axis. Patterns to watch:
   - Latency spike with no error increase → resource saturation (check CPU/Memory)
   - Error spike with flat latency → application-level failure (check logs)
   - Error spike following traffic increase → capacity limit (check request rate vs 1000 req/min line)
   - All metrics flat except CPU → background job or memory leak

---

## Dashboard CLI Commands

```bash
# Deploy / update dashboard
aws cloudwatch put-dashboard \
  --dashboard-name WebTierMonitoring \
  --dashboard-body file://dashboard.json

# List dashboards
aws cloudwatch list-dashboards

# Open in browser (replace region if needed)
echo "https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=WebTierMonitoring"
```

---

## Screenshots

- `screenshots/01-full-dashboard.png` — full dashboard overview
- `screenshots/02-golden-signals.png` — Golden Signals row (Traffic, Errors, Latency, Saturation)
- `screenshots/03-resource-utilization.png` — EC2 CPU, Memory, Network, Disk row
- `screenshots/04-correlation-view.png` — Correlation view with all four signals overlaid

> Add your screenshots here.

---

## Infrastructure Details

| Resource | Value |
|---|---|
| Dashboard Name | `WebTierMonitoring` |
| EC2 Instance | `i-06c37f7d08d0c85a2` (t3.micro, name: cloudwatch) |
| ALB | `app/project1-tf-alb/672a5c798070df76` |
| Target Group | `targetgroup/project1-tf-app-tg/b36816f6fa55a324` |
| Region | `us-east-1` |
| CloudWatch Agent | Active — tailing `/home/ubuntu/app/application.log` |
