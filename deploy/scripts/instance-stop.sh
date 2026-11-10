#!/usr/bin/env bash
# instance-stop.sh / instance-start.sh — the duty-cycle cost levers.
# Stopping the instance keeps the EIP + root EBS (small charges) and stops
# the ~USD 0.39/hr compute. Workspaces' data is on the root volume — safe.
# Run from an operator machine with AWS credentials.
set -euo pipefail

cmd="${1:-}"
instance="${AWS_POC_INSTANCE_ID:?set AWS_POC_INSTANCE_ID (terraform output instance_id)}"
region="${AWS_REGION:-ap-southeast-1}"

case "$cmd" in
  stop)
    echo "stopping $instance (workspace data persists on EBS)"
    aws ec2 stop-instances --region "$region" --instance-ids "$instance"
    ;;
  start)
    echo "starting $instance"
    aws ec2 start-instances --region "$region" --instance-ids "$instance"
    aws ec2 wait instance-status-ok --region "$region" --instance-ids "$instance"
    echo "platform auto-starts via docker restart policy; coder UI follows"
    ;;
  *)
    echo "usage: $0 stop|start   (requires AWS_POC_INSTANCE_ID + credentials)"
    exit 64
    ;;
esac
