#!/usr/bin/env bash
# generate-errors.sh
# Writes 20 ERROR log entries to the application log file to trigger HighErrorRate alarm.
# Run this ON the EC2 instance (or via SSH).

LOG_FILE="${LOG_FILE:-/home/ubuntu/app/application.log}"
COUNT="${COUNT:-20}"

echo "Writing $COUNT ERROR entries to $LOG_FILE..."

for i in $(seq 1 "$COUNT"); do
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) req-$(cat /proc/sys/kernel/random/uuid | cut -d- -f1) ERROR Unhandled exception in request handler" \
    >> "$LOG_FILE"
done

echo "Done. CloudWatch agent will ship these to /aws/application/api."
echo "Check alarm state in ~2 minutes:"
echo "  aws cloudwatch describe-alarms --alarm-names HighErrorRate"
