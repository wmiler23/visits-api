#!/usr/bin/env bash
# Preview what the current branch would change in the dev stack.
# Creates a CloudFormation change set, writes a Markdown summary, and always
# deletes the change set afterwards. Nothing is ever executed.
#
# Usage:     scripts/preview_changeset.sh <output.md>
# Needs:     AWS credentials (the preview role in CI), AWS_REGION
# Optional:  APP_NAME (visits), PR_NUMBER, HEAD_SHA (commit to show in the summary)
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

OUT="${1:?usage: scripts/preview_changeset.sh <output.md>}"
STACK="${APP_NAME}-dev"
CHANGE_SET="preview-pr${PR_NUMBER:-local}-${GITHUB_RUN_ID:-$(date +%s)}-${GITHUB_RUN_ATTEMPT:-1}"
COMMIT="${HEAD_SHA:-$(git rev-parse HEAD)}"
JSON="$(mktemp)"

# The marker lets the workflow find and update its own comment on later pushes.
# shellcheck disable=SC2016  # backticks are Markdown here, not command substitution
printf '<!-- cfn-preview -->\n### CloudFormation preview: `%s`\n\n' "$STACK" > "$OUT"

if [[ "$(stack_status "$STACK")" == NONE ]]; then
  echo "The dev stack does not exist yet. The first merge to \`main\` creates every resource in the template." >> "$OUT"
  exit 0
fi

# Values in the params file come from this branch. Values the pipeline sets at
# deploy time (bundle, version) keep whatever dev is running now.
read_params infra/params/dev.params
CFN_PARAMS=()
for kv in ${PARAMS[@]+"${PARAMS[@]}"}; do
  CFN_PARAMS+=("ParameterKey=${kv%%=*},ParameterValue=${kv#*=}")
done
for key in AppName Environment ArtifactBucket ArtifactKey AppVersion; do
  CFN_PARAMS+=("ParameterKey=$key,UsePreviousValue=true")
done

cleanup() {
  aws cloudformation delete-change-set --stack-name "$STACK" --change-set-name "$CHANGE_SET" >/dev/null 2>&1 || true
  rm -f "$JSON"
}
trap cleanup EXIT

log "Creating change set $CHANGE_SET on $STACK"
if ! err="$(aws cloudformation create-change-set \
    --stack-name "$STACK" \
    --change-set-name "$CHANGE_SET" \
    --change-set-type UPDATE \
    --template-body file://infra/template.yaml \
    --parameters "${CFN_PARAMS[@]}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --role-arn "$(exec_role_arn dev)" \
    --description "Preview only. Deleted after rendering, never executed." 2>&1 >/dev/null)"; then
  # shellcheck disable=SC2016
  printf 'CloudFormation rejected the template:\n\n```\n%s\n```\n' "$err" >> "$OUT"
  exit 1
fi

if ! aws cloudformation wait change-set-create-complete \
    --stack-name "$STACK" --change-set-name "$CHANGE_SET" 2>/dev/null; then
  reason="$(aws cloudformation describe-change-set --stack-name "$STACK" \
    --change-set-name "$CHANGE_SET" --query StatusReason --output text)"
  if [[ "$reason" == *"didn't contain changes"* || "$reason" == *"No updates are to be performed"* ]]; then
    echo "No infrastructure changes. Code-only changes do not show here: the Lambda bundle is built after merge." >> "$OUT"
    exit 0
  fi
  # shellcheck disable=SC2016
  printf 'The change set failed:\n\n```\n%s\n```\n' "$reason" >> "$OUT"
  exit 1
fi

aws cloudformation describe-change-set --stack-name "$STACK" \
  --change-set-name "$CHANGE_SET" --output json > "$JSON"
python3 scripts/render_changeset.py "$JSON" "$COMMIT" >> "$OUT"
log "Preview written to $OUT"
