#!/bin/bash
# smoke-test.sh — Verify o11y-platform OpenSearch deployment: SSM outputs, domain status, cluster health.
# Run from any workstation with AWS credentials exported. No VPC access required.
#
# Usage:
#   bash scripts/smoke-test.sh <dev|test|prod>
#
# Requires exported AWS credentials (not AWS_PROFILE — use eval $(aws configure export-credentials ...)):
#   eval $(aws configure export-credentials --profile <your-profile> --format env)
#   unset AWS_PROFILE
#   bash scripts/smoke-test.sh dev

set -euo pipefail

VENUE="${1:?Usage: $0 <dev|test|prod>}"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"
PASS=0
FAIL=0

pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }

echo "== SSM parameters (venue: $VENUE) =="

ENDPOINT=$(aws ssm get-parameter \
  --name /pds/o11y-platform/opensearch/opensearch_endpoint \
  --region "$REGION" --query Parameter.Value --output text 2>/dev/null || true)
if [[ -n "$ENDPOINT" ]]; then
  pass "opensearch_endpoint: $ENDPOINT"
else
  fail "opensearch_endpoint not found at /pds/o11y-platform/opensearch/opensearch_endpoint"
fi

ARN=$(aws ssm get-parameter \
  --name /pds/o11y-platform/opensearch/opensearch_arn \
  --region "$REGION" --query Parameter.Value --output text 2>/dev/null || true)
if [[ -n "$ARN" ]]; then
  pass "opensearch_arn: $ARN"
else
  fail "opensearch_arn not found at /pds/o11y-platform/opensearch/opensearch_arn"
fi

SG_ID=$(aws ssm get-parameter \
  --name /pds/o11y-platform/opensearch/opensearch_security_group_id \
  --region "$REGION" --query Parameter.Value --output text 2>/dev/null || true)
if [[ -n "$SG_ID" ]]; then
  pass "opensearch_security_group_id: $SG_ID"
else
  fail "opensearch_security_group_id not found at /pds/o11y-platform/opensearch/opensearch_security_group_id"
fi

echo ""
echo "== Security group exists =="

if [[ -n "$SG_ID" ]]; then
  if aws ec2 describe-security-groups --group-ids "$SG_ID" --region "$REGION" \
      --query "SecurityGroups[0].GroupId" --output text &>/dev/null; then
    pass "SG $SG_ID exists in $REGION"
  else
    fail "SG $SG_ID not found in $REGION"
  fi
else
  echo "  SKIP  (no SG ID from SSM)"
fi

echo ""
echo "== OpenSearch domain status =="

if [[ -z "$ARN" ]]; then
  echo "  SKIP  (no ARN from SSM)"
else
  DOMAIN_NAME=$(echo "$ARN" | sed 's|.*/domain/||')

  DOMAIN_JSON=$(aws opensearch describe-domain \
    --domain-name "$DOMAIN_NAME" --region "$REGION" \
    --query "DomainStatus" --output json 2>/dev/null || true)

  if [[ -z "$DOMAIN_JSON" ]]; then
    fail "describe-domain: domain $DOMAIN_NAME not found"
  else
    CREATED=$(echo "$DOMAIN_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['Created'])" 2>/dev/null || echo "false")
    PROCESSING=$(echo "$DOMAIN_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['Processing'])" 2>/dev/null || echo "true")

    if [[ "$CREATED" == "True" ]]; then
      pass "domain created: $DOMAIN_NAME"
    else
      fail "domain not yet created: $DOMAIN_NAME"
    fi

    if [[ "$PROCESSING" == "False" ]]; then
      pass "domain not processing (stable)"
    else
      fail "domain is currently processing (mid-update or still provisioning)"
    fi
  fi
fi

echo ""
echo "== OpenSearch cluster health =="

if [[ -z "$ARN" ]]; then
  echo "  SKIP  (no ARN from SSM)"
else
  DOMAIN_NAME=$(echo "$ARN" | sed 's|.*/domain/||')

  HEALTH_JSON=$(aws opensearch describe-domain-health \
    --domain-name "$DOMAIN_NAME" --region "$REGION" \
    --output json 2>/dev/null || true)

  if [[ -z "$HEALTH_JSON" ]]; then
    fail "describe-domain-health: no response for $DOMAIN_NAME"
  else
    HEALTH=$(echo "$HEALTH_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['HealthStatus'])" 2>/dev/null || echo "Unknown")
    NODES=$(echo "$HEALTH_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['DataNodeCount'])" 2>/dev/null || echo "?")
    UNASSIGNED=$(echo "$HEALTH_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['TotalUnAssignedShards'])" 2>/dev/null || echo "?")

    if [[ "$HEALTH" == "Green" || "$HEALTH" == "Yellow" ]]; then
      pass "cluster health: status=$HEALTH nodes=$NODES unassigned_shards=$UNASSIGNED"
    else
      fail "cluster health: status=$HEALTH nodes=$NODES unassigned_shards=$UNASSIGNED (expected Green or Yellow)"
    fi
  fi
fi

echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "All $PASS check(s) passed."
  exit 0
else
  echo "$FAIL check(s) FAILED, $PASS passed — see above."
  exit 1
fi
