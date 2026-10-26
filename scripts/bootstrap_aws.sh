#!/usr/bin/env bash
# One-time AWS setup for this repository. Run it from your laptop with
# credentials that can create IAM roles (an admin profile).
#
# Creates or updates three stacks:
#   <app>-bootstrap-account  GitHub OIDC provider, artifact bucket, PR preview role
#   <app>-bootstrap-dev      execution role, permissions boundary, deploy role for dev
#   <app>-bootstrap-prod     the same for prod
#
# Usage:  scripts/bootstrap_aws.sh
# Env:    AWS_PROFILE and AWS_REGION as usual
#         APP_NAME             resource prefix (default visits)
#         GITHUB_REPOSITORY    owner/repo (default: the repo gh sees in this folder)
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

command -v gh >/dev/null || fail "The GitHub CLI (gh) is required: https://cli.github.com"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region || true)}}"
[[ -n "$AWS_REGION" ]] || fail "Set AWS_REGION (for example: export AWS_REGION=us-east-1)"
export AWS_REGION
REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
ACCOUNT_STACK="${APP_NAME}-bootstrap-account"
log "Account $ACCOUNT | region $AWS_REGION | repo $REPO | app $APP_NAME"

# --- 1. Who the repository is, by name and by permanent ID --------------------
# GitHub's OIDC subject is repo:OWNER@OWNER_ID/REPO@REPO_ID:... for repos created
# after 15 July 2026 and repo:OWNER/REPO:... for older ones. The trust policies
# accept both forms, so all this needs is the four values.
use_default="$(gh api "repos/$REPO/actions/oidc/customization/sub" --jq .use_default)" \
  || fail "Could not read the OIDC settings of $REPO. Check: gh auth status"
[[ "$use_default" == "true" ]] \
  || fail "$REPO uses a custom OIDC subject template; the trust policies here expect the default one."
repo_info="$(gh api "repos/$REPO" --jq '[.owner.login, .owner.id, .name, .id] | @tsv')" \
  || fail "Could not read $REPO from the GitHub API"
IFS=$'\t' read -r GH_OWNER GH_OWNER_ID GH_REPO GH_REPO_ID <<<"$repo_info"
[[ -n "$GH_REPO_ID" ]] || fail "Could not read the IDs of $REPO"
log "Trusting repo:$GH_OWNER@$GH_OWNER_ID/$GH_REPO@$GH_REPO_ID (and the older repo:$GH_OWNER/$GH_REPO form)"
GH_PARAMS=("GitHubOwner=$GH_OWNER" "GitHubOwnerId=$GH_OWNER_ID" "GitHubRepo=$GH_REPO" "GitHubRepoId=$GH_REPO_ID")

deploy_stack() {  # <stack> <template> <Key=Value>...
  local stack="$1" template="$2"
  shift 2
  log "Deploying $stack from $template"
  aws cloudformation deploy \
    --stack-name "$stack" \
    --template-file "$template" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --parameter-overrides "$@" \
    --tags "app=$APP_NAME" "managed-by=bootstrap"
}

# --- 2. Account stack ---------------------------------------------------------
# An account holds one provider per URL. Reuse it if something else made it.
# Only decided on first creation; later runs keep the stack's previous value.
EXTRA=()
if [[ "$(stack_status "$ACCOUNT_STACK")" == NONE ]]; then
  existing="$(aws iam list-open-id-connect-providers \
    --query "OpenIDConnectProviderList[?ends_with(Arn, 'oidc-provider/token.actions.githubusercontent.com')].Arn | [0]" \
    --output text)"
  if [[ -n "$existing" && "$existing" != "None" ]]; then
    log "Reusing the GitHub OIDC provider that already exists: $existing"
    EXTRA=("ExistingOidcProviderArn=$existing")
  fi
fi
deploy_stack "$ACCOUNT_STACK" bootstrap/account.yaml \
  "AppName=$APP_NAME" "${GH_PARAMS[@]}" ${EXTRA[@]+"${EXTRA[@]}"}

PROVIDER_ARN="$(stack_output "$ACCOUNT_STACK" OidcProviderArn)"
BUCKET="$(stack_output "$ACCOUNT_STACK" ArtifactBucketName)"

# --- 3. One stack per environment ---------------------------------------------
for env in dev prod; do
  writer=false
  if [[ "$env" == dev ]]; then writer=true; fi  # only dev uploads bundles
  deploy_stack "${APP_NAME}-bootstrap-$env" bootstrap/environment.yaml \
    "AppName=$APP_NAME" "Environment=$env" "OidcProviderArn=$PROVIDER_ARN" \
    "${GH_PARAMS[@]}" "ArtifactBucketName=$BUCKET" "ArtifactWriter=$writer"
done

cat <<EOF

Bootstrap complete.
  Artifact bucket   $BUCKET
  Preview role      $(stack_output "$ACCOUNT_STACK" PreviewRoleArn)
  Dev deploy role   $(stack_output "${APP_NAME}-bootstrap-dev" DeployRoleArn)
  Prod deploy role  $(stack_output "${APP_NAME}-bootstrap-prod" DeployRoleArn)

Next: scripts/configure_github.sh
EOF
