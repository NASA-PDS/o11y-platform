#!/bin/bash
# smoke-test.sh — Verify o11y-platform OpenSearch deployment: SSM outputs, domain health, SG.
# Run from any workstation with AWS credentials exported and VPC access to the domain.
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
echo "== OpenSearch cluster health =="

if [[ -z "$ENDPOINT" ]]; then
  echo "  SKIP  (no endpoint from SSM)"
else
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    --aws-sigv4 "aws:amz:${REGION}:es" \
    --user "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID not set}:${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY not set}" \
    -H "x-amz-security-token: ${AWS_SESSION_TOKEN:-}" \
    "https://${ENDPOINT}/_cluster/health?pretty" 2>/dev/null || true)

  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  BODY=$(echo "$RESPONSE" | head -n -1)

  if [[ "$HTTP_CODE" == "200" ]]; then
    STATUS=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['status'])" "$BODY" 2>/dev/null || echo "unknown")
    NODES=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['number_of_nodes'])" "$BODY" 2>/dev/null || echo "?")
    if [[ "$STATUS" == "green" || "$STATUS" == "yellow" ]]; then
      pass "cluster health: status=$STATUS nodes=$NODES"
    else
      fail "cluster health: status=$STATUS nodes=$NODES (expected green or yellow)"
    fi
  else
    fail "cluster health: HTTP $HTTP_CODE (expected 200 — verify VPC access and credentials)"
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
