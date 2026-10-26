#!/usr/bin/env bash
# Deploy the app stack for one environment through CloudFormation, using the
# environment's execution role. The same script runs in CI and on a laptop.
#
# Usage:     scripts/deploy.sh <dev|prod>
# Needs:     AWS credentials, AWS_REGION, ARTIFACT_BUCKET, ARTIFACT_KEY
# Optional:  APP_NAME (visits), APP_VERSION (git HEAD), CFN_EXEC_ROLE_ARN (derived)
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

ENVIRONMENT="${1:-}"
[[ "$ENVIRONMENT" == dev || "$ENVIRONMENT" == prod ]] || fail "usage: scripts/deploy.sh <dev|prod>"
: "${ARTIFACT_BUCKET:?set ARTIFACT_BUCKET}" "${ARTIFACT_KEY:?set ARTIFACT_KEY}"

STACK="${APP_NAME}-${ENVIRONMENT}"
VERSION="${APP_VERSION:-$(git rev-parse HEAD)}"
ROLE_ARN="$(exec_role_arn "$ENVIRONMENT")"

# Refuse states that a deploy cannot fix by itself.
status="$(stack_status "$STACK")"
case "$status" in
  ROLLBACK_COMPLETE | ROLLBACK_FAILED | DELETE_FAILED | UPDATE_ROLLBACK_FAILED)
    fail "$STACK is in $status and needs a manual fix before it can deploy again (Module 9)." ;;
  REVIEW_IN_PROGRESS) ;;  # an empty stack left by an unexecuted change set; deploy handles it
  *_IN_PROGRESS)
    fail "$STACK is busy ($status). Wait for it to finish, then re-run the job." ;;
esac
log "Deploying $STACK (status: $status) at version $VERSION"

read_params "infra/params/${ENVIRONMENT}.params"

# 'deploy' creates a change set, waits for it, executes it and waits for the
# stack to settle. With no changes it exits 0 instead of failing.
if ! aws cloudformation deploy \
    --stack-name "$STACK" \
    --template-file infra/template.yaml \
    --role-arn "$ROLE_ARN" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --parameter-overrides ${PARAMS[@]+"${PARAMS[@]}"} \
      "AppName=$APP_NAME" \
      "Environment=$ENVIRONMENT" \
      "ArtifactBucket=$ARTIFACT_BUCKET" \
      "ArtifactKey=$ARTIFACT_KEY" \
      "AppVersion=$VERSION" \
    --tags "app=$APP_NAME" "env=$ENVIRONMENT" "managed-by=github-actions"; then
  log "Deployment failed. Most recent failure events:"
  aws cloudformation describe-stack-events --stack-name "$STACK" --max-items 30 \
    --query "StackEvents[?ends_with(ResourceStatus, 'FAILED')].[Timestamp, LogicalResourceId, ResourceStatus, ResourceStatusReason]" \
    --output table || true
  exit 1
fi

API_URL="$(stack_output "$STACK" ApiUrl)"
log "API URL: $API_URL"
gh_output api_url "$API_URL"
gh_summary \
  "### Deployed \`$STACK\`" \
  "" \
  "| Item | Value |" \
  "| --- | --- |" \
  "| Version | \`$VERSION\` |" \
  "| Bundle | \`$ARTIFACT_KEY\` |" \
  "| API | $API_URL |"
