#!/usr/bin/env bash
# Post a file as a pull request comment, or update the comment posted earlier.
# The earlier comment is found by the first line of the file (an HTML comment
# such as <!-- cfn-preview -->), so other bot comments are never overwritten.
#
# Usage:  scripts/comment_on_pr.sh <pr-number> <file>
# Needs:  GH_TOKEN with pull-requests: write, GITHUB_REPOSITORY (owner/repo)
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

PR="${1:?usage: scripts/comment_on_pr.sh <pr-number> <file>}"
FILE="${2:?usage: scripts/comment_on_pr.sh <pr-number> <file>}"
: "${GITHUB_REPOSITORY:?set GITHUB_REPOSITORY to owner/repo}"
MARKER="$(head -n 1 "$FILE")"
[[ "$MARKER" == "<!--"*"-->" ]] || fail "$FILE must start with an HTML comment marker line"

existing="$(gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$PR/comments" \
  --jq ".[] | select(.user.login == \"github-actions[bot]\" and (.body | startswith(\"$MARKER\"))) | .id" \
  | tail -n 1)"

if [[ -n "$existing" ]]; then
  gh api -X PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$existing" -F "body=@$FILE" >/dev/null
  log "Updated comment $existing on PR #$PR"
else
  gh api -X POST "repos/$GITHUB_REPOSITORY/issues/$PR/comments" -F "body=@$FILE" >/dev/null
  log "Posted a new comment on PR #$PR"
fi
