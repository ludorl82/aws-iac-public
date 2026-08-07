"""Dead-man's switch: alert via SNS when homelab heartbeats go stale.

Two S3 heartbeat objects distinguish the failure domains:
  deadman/house.heartbeat   — pi-02 timer (tests house power/internet/host)
  deadman/cluster.heartbeat — k3s CronJob   (tests cluster/etcd/scheduling)

They live in their own bucket, not alongside the backups: a 5-minute
overwrite loop cannot share a bucket with Object Lock (see s3.tf).

This function runs OUTSIDE the VPC on an EventBridge schedule and alerts
through SNS email — deliberately not through Kuma/ntfy, which are part of
what it watches. A state marker per heartbeat dedupes alerts: one email when
a heartbeat goes stale, one when it recovers.
"""
import json
import os
from datetime import datetime, timezone

import boto3

s3 = boto3.client("s3")
sns = boto3.client("sns")

BUCKET = os.environ["BUCKET"]
TOPIC_ARN = os.environ["TOPIC_ARN"]
CHECKS = json.loads(os.environ["CHECKS"])  # {"deadman/house.heartbeat": 1800, ...}
STATE_PREFIX = "deadman/.alerted/"


def _exists(key):
    try:
        s3.head_object(Bucket=BUCKET, Key=key)
        return True
    except Exception:
        return False


def lambda_handler(event, context):
    now = datetime.now(timezone.utc)
    for key, max_age in CHECKS.items():
        name = key.rsplit("/", 1)[-1]
        state_key = STATE_PREFIX + name
        try:
            mtime = s3.head_object(Bucket=BUCKET, Key=key)["LastModified"]
            age = (now - mtime).total_seconds()
        except Exception:
            age = None

        stale = age is None or age > max_age
        alerted = _exists(state_key)

        if stale and not alerted:
            desc = "MISSING" if age is None else f"stale for {int(age // 60)} min"
            sns.publish(
                TopicArn=TOPIC_ARN,
                Subject=f"DEAD-MAN SWITCH: {name} {desc}",
                Message=(
                    f"Heartbeat s3://{BUCKET}/{key} is {desc} "
                    f"(threshold {max_age // 60} min).\n\n"
                    "Internal alerting (Kuma/ntfy) may be down along with it.\n"
                    "house.heartbeat = pi-02 timer -> house power/internet/host.\n"
                    "cluster.heartbeat = k3s CronJob -> cluster/etcd/scheduling.\n"
                ),
            )
            s3.put_object(Bucket=BUCKET, Key=state_key, Body=now.isoformat().encode())
        elif not stale and alerted:
            sns.publish(
                TopicArn=TOPIC_ARN,
                Subject=f"DEAD-MAN SWITCH: {name} recovered",
                Message=f"Heartbeat s3://{BUCKET}/{key} is fresh again.",
            )
            s3.delete_object(Bucket=BUCKET, Key=state_key)
    return {"ok": True}
