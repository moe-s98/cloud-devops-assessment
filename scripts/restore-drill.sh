#!/usr/bin/env bash
# Backup restore drill: proves point-in-time recovery works and measures RTO.
#
#   1. write marker A through the public API, note time T, then write marker B
#   2. restore the database to time T as a NEW instance (production is untouched)
#   3. run a one-off ECS task inside the VPC that queries the restored copy:
#        marker A present  (data up to T recovered)
#        marker B absent   (restore is truly point-in-time)
#   4. report RPO/RTO and delete the drill instance
#
# Usage: scripts/restore-drill.sh <env> <app-url>      e.g. dev https://dxxxx.cloudfront.net
set -euo pipefail

ENV="${1:?env}"; URL="${2:?app url}"
PREFIX="guestbook-${ENV}"
SRC="${PREFIX}-postgres"
DRILL="${PREFIX}-postgres-drill-$(date +%H%M)"
CLUSTER="${PREFIX}-cluster"
SERVICE="${PREFIX}-api"
REGION="${AWS_REGION:-eu-north-1}"
export AWS_REGION="$REGION"

log() { printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
post() { curl -fsS -X POST "$URL/api/messages" -H 'Content-Type: application/json' \
           -d "{\"author\":\"restore-drill\",\"body\":\"$1\"}" >/dev/null; }

cleanup() {
  log "Cleanup: deleting drill instance $DRILL"
  aws rds delete-db-instance --db-instance-identifier "$DRILL" \
    --skip-final-snapshot --delete-automated-backups >/dev/null 2>&1 || true
}
trap cleanup EXIT

MARK_A="drill-A-$(date +%s)"; MARK_B="drill-B-$(date +%s)"

log "Writing marker A ($MARK_A)"
post "$MARK_A"
sleep 5
RESTORE_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
log "Restore point T = $RESTORE_TIME"
sleep 5
log "Writing marker B ($MARK_B), must NOT exist in the restored copy"
post "$MARK_B"

log "Waiting until T is inside the restorable window (transaction logs ship every ~5 min)"
until [[ "$(aws rds describe-db-instances --db-instance-identifier "$SRC" \
          --query 'DBInstances[0].LatestRestorableTime' --output text)" > "$RESTORE_TIME" ]]; do
  sleep 30
done

read -r SUBNET_GROUP DB_SG CLASS < <(aws rds describe-db-instances --db-instance-identifier "$SRC" \
  --query 'DBInstances[0].[DBSubnetGroup.DBSubnetGroupName,VpcSecurityGroups[0].VpcSecurityGroupId,DBInstanceClass]' --output text)

log "Restoring $SRC to $RESTORE_TIME as $DRILL"
START=$(date +%s)
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier "$SRC" \
  --target-db-instance-identifier "$DRILL" \
  --restore-time "$RESTORE_TIME" \
  --db-subnet-group-name "$SUBNET_GROUP" \
  --vpc-security-group-ids "$DB_SG" \
  --db-instance-class "$CLASS" \
  --no-multi-az --no-publicly-accessible \
  --tags Key=Purpose,Value=restore-drill Key=backup,Value=false >/dev/null
aws rds wait db-instance-available --db-instance-identifier "$DRILL"
RTO=$(( $(date +%s) - START ))
DRILL_HOST=$(aws rds describe-db-instances --db-instance-identifier "$DRILL" \
  --query 'DBInstances[0].Endpoint.Address' --output text)
log "Restored in ${RTO}s -> $DRILL_HOST"

log "Verifying from inside the VPC with a one-off ECS task (same image, same network)"
TASK_DEF=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].taskDefinition' --output text)
NETCFG=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].networkConfiguration' --output json)
QUERY="import os,psycopg; c=psycopg.connect(host=os.environ['DB_HOST'],dbname=os.environ['DB_NAME'],user=os.environ['DB_USER'],password=os.environ['DB_PASSWORD'],sslmode='require'); f=lambda m: c.execute('select count(*) from messages where body=%s',(m,)).fetchone()[0]; print('DRILL_RESULT', 'A=%d' % f('$MARK_A'), 'B=%d' % f('$MARK_B'))"
OVERRIDES=$(python3 -c "import json,sys; print(json.dumps({'containerOverrides':[{'name':'api','command':['python','-c',sys.argv[1]],'environment':[{'name':'DB_HOST','value':sys.argv[2]}]}]}))" "$QUERY" "$DRILL_HOST")
TASK_ARN=$(aws ecs run-task --cluster "$CLUSTER" --task-definition "$TASK_DEF" --launch-type FARGATE \
  --network-configuration "$NETCFG" --overrides "$OVERRIDES" --query 'tasks[0].taskArn' --output text)
aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$TASK_ARN"
sleep 5
RESULT=$(aws logs get-log-events --log-group-name "/${PREFIX}/ecs/api" \
  --log-stream-name "api/api/${TASK_ARN##*/}" --query 'events[].message' --output text | grep -o 'DRILL_RESULT.*' || true)
log "Query result: ${RESULT:-<none>}"

if [[ "$RESULT" == *"A=1 B=0"* ]]; then
  log "PASS  RPO: restored to the exact second requested (T=$RESTORE_TIME)  |  RTO: ${RTO}s ($((RTO / 60)) min)"
else
  log "FAIL  expected 'A=1 B=0'"; exit 1
fi
