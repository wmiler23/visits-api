#!/usr/bin/env bash
# Wire the GitHub repository to the AWS bootstrap: environments, deployment
# branch rules, secrets, variables and branch protection. Safe to re-run.
#
# Usage:  scripts/configure_github.sh
# Env:    AWS_PROFILE / AWS_REGION (to read the bootstrap stack outputs)
#         APP_NAME (visits), GITHUB_REPOSITORY (owner/repo, default: from gh)
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region || true)}}"
[[ -n "$AWS_REGION" ]] || fail "Set AWS_REGION to the region you bootstrapped"
export AWS_REGION
REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"

ACCOUNT_STACK="${APP_NAME}-bootstrap-account"
[[ "$(stack_status "$ACCOUNT_STACK")" != NONE ]] || fail "$ACCOUNT_STACK not found in $AWS_REGION. Run scripts/bootstrap_aws.sh first."
BUCKET="$(stack_output "$ACCOUNT_STACK" ArtifactBucketName)"
PREVIEW_ROLE="$(stack_output "$ACCOUNT_STACK" PreviewRoleArn)"
DEV_ROLE="$(stack_output "${APP_NAME}-bootstrap-dev" DeployRoleArn)"
PROD_ROLE="$(stack_output "${APP_NAME}-bootstrap-prod" DeployRoleArn)"

# --- Environments -----------------------------------------------------------
# Both accept deployments from main only. Neither waits for a reviewer: prod
# starts as soon as the dev deploy and its smoke test have passed.
BRANCH_RULE='{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'

configure_environment() {  # <name>
  local env="$1"
  gh api -X PUT "repos/$REPO/environments/$env" --input - <<<"$BRANCH_RULE" >/dev/null \
    || fail "Could not create environment $env. Private repos on GitHub Free have no environments."
  if ! gh api "repos/$REPO/environments/$env/deployment-branch-policies" \
      --jq '.branch_policies[].name' | grep -qx main; then
    gh api -X POST "repos/$REPO/environments/$env/deployment-branch-policies" \
      -f name=main -f type=branch >/dev/null
  fi
  log "Environment $env: deploys from main only"
}

configure_environment dev
configure_environment prod

# --- Variables (visible) and secrets (masked in logs) -------------------------
# Role ARNs contain the account ID, so they are secrets. The bucket name does not.
gh variable set AWS_REGION      --repo "$REPO" --body "$AWS_REGION"
gh variable set APP_NAME        --repo "$REPO" --body "$APP_NAME"
gh variable set ARTIFACT_BUCKET --repo "$REPO" --body "$BUCKET"
gh secret set AWS_PREVIEW_ROLE_ARN --repo "$REPO" --body "$PREVIEW_ROLE"
gh secret set AWS_DEPLOY_ROLE_ARN  --repo "$REPO" --env dev  --body "$DEV_ROLE"
gh secret set AWS_DEPLOY_ROLE_ARN  --repo "$REPO" --env prod --body "$PROD_ROLE"
log "Variables and secrets set"

# --- Branch protection on main ------------------------------------------------
# Changes reach main through a pull request whose Lint and Unit tests checks pass.
if gh api "repos/$REPO/branches/main" >/dev/null 2>&1; then
  if gh api -X PUT "repos/$REPO/branches/main/protection" --input - >/dev/null <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "checks": [{"context": "Lint"}, {"context": "Unit tests"}]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {"required_approving_review_count": 0},
  "restrictions": null
}
JSON
  then
    log "Branch protection on main: pull request + passing Lint and Unit tests"
  else
    warn "Could not protect main. Private repos on GitHub Free have no branch protection."
  fi
else
  warn "main is not on GitHub yet. Push it, then re-run this script to protect it."
fi

log "GitHub configuration complete for $REPO"
