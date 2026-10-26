# shellcheck shell=bash
# Shared helpers, sourced by the other scripts. Written for bash 3.2 too,
# so the scripts you run from a Mac behave the same as on the CI runner.

APP_NAME="${APP_NAME:-visits}"

log()  { printf '==> %s\n' "$*" >&2; }

warn() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then printf '::warning::%s\n' "$*" >&2
  else printf 'WARNING: %s\n' "$*" >&2; fi
}

fail() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then printf '::error::%s\n' "$*" >&2
  else printf 'ERROR: %s\n' "$*" >&2; fi
  exit 1
}

# Print a stack's status, or NONE if it does not exist. Any other error
# (expired credentials, access denied) stops the calling script.
stack_status() {
  local out
  if out="$(aws cloudformation describe-stacks --stack-name "$1" \
      --query 'Stacks[0].StackStatus' --output text 2>&1)"; then
    printf '%s\n' "$out"
  elif [[ "$out" == *"does not exist"* ]]; then
    printf 'NONE\n'
  else
    printf '%s\n' "$out" >&2
    return 1
  fi
}

# Print one output value of a stack.
stack_output() {
  aws cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue | [0]" --output text
}

# Load infra/params/<env>.params into the PARAMS array as Key=Value strings,
# skipping blank lines and comments.
read_params() {
  PARAMS=()
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    PARAMS+=("$line")
  done < "$1"
}

# ARN of the CloudFormation execution role for an environment. The name is a
# convention set by bootstrap/environment.yaml, so only the account is looked
# up. Set CFN_EXEC_ROLE_ARN to override.
exec_role_arn() {
  if [[ -n "${CFN_EXEC_ROLE_ARN:-}" ]]; then
    printf '%s\n' "$CFN_EXEC_ROLE_ARN"
    return
  fi
  local caller partition account
  caller="$(aws sts get-caller-identity --query Arn --output text)"
  partition="$(printf '%s' "$caller" | cut -d: -f2)"
  account="$(printf '%s' "$caller" | cut -d: -f5)"
  printf 'arn:%s:iam::%s:role/%s-%s-cfn-exec\n' "$partition" "$account" "$APP_NAME" "$1"
}

# Hand a value to later workflow steps (no-op outside GitHub Actions).
gh_output() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"; fi
}

# Append lines to the job summary page (no-op outside GitHub Actions).
gh_summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then printf '%s\n' "$@" >> "$GITHUB_STEP_SUMMARY"; fi
}
