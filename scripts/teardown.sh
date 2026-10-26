#!/usr/bin/env bash
# Delete everything this course created in AWS, in dependency order.
#
# Usage:  scripts/teardown.sh [--yes]
# Env:    AWS_PROFILE / AWS_REGION (admin), APP_NAME (visits)
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region || true)}}"
[[ -n "$AWS_REGION" ]] || fail "Set AWS_REGION to the region you deployed to"
export AWS_REGION

# Check the one local dependency before deleting anything.
python3 -c 'import boto3' 2>/dev/null \
  || fail "python3 cannot import boto3 (used to empty the bucket). Activate the venv and run make install."

if [[ "${1:-}" != "--yes" ]]; then
  printf 'This deletes the %s app stacks, their data, the artifact bucket and the bootstrap roles in %s.\n' "$APP_NAME" "$AWS_REGION"
  read -r -p "Type the app name to continue: " answer
  [[ "$answer" == "$APP_NAME" ]] || fail "Cancelled"
fi

delete_stack() {
  local stack="$1"
  if [[ "$(stack_status "$stack")" == NONE ]]; then
    log "$stack: already gone"
    return
  fi
  log "$stack: deleting"
  aws cloudformation delete-stack --stack-name "$stack"
  aws cloudformation wait stack-delete-complete --stack-name "$stack"
  log "$stack: deleted"
}

# 1. App stacks first. CloudFormation deletes them using the execution roles,
#    and those roles live in the bootstrap stacks, so order matters.
if [[ "$(stack_status "${APP_NAME}-prod")" != NONE ]]; then
  log "Turning off deletion protection on the prod table"
  aws dynamodb update-table --table-name "${APP_NAME}-prod-visits" \
    --no-deletion-protection-enabled >/dev/null || true
fi
delete_stack "${APP_NAME}-prod"
delete_stack "${APP_NAME}-dev"

# 2. Empty the versioned artifact bucket; CloudFormation cannot delete a full one.
ACCOUNT_STACK="${APP_NAME}-bootstrap-account"
if [[ "$(stack_status "$ACCOUNT_STACK")" != NONE ]]; then
  bucket="$(stack_output "$ACCOUNT_STACK" ArtifactBucketName)"
  log "Emptying s3://$bucket (all object versions)"
  python3 - "$bucket" "$AWS_REGION" <<'PY'
import sys
import boto3

boto3.resource("s3", region_name=sys.argv[2]).Bucket(sys.argv[1]).object_versions.delete()
PY
fi

# 3. Bootstrap stacks last. The OIDC provider goes only if this stack created it.
delete_stack "${APP_NAME}-bootstrap-prod"
delete_stack "${APP_NAME}-bootstrap-dev"
delete_stack "$ACCOUNT_STACK"
log "AWS teardown complete"
