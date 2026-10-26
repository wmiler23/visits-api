#!/usr/bin/env bash
# Smoke test a deployed API: it answers, it runs the version just deployed,
# and the data path works.
#
# Usage:  scripts/smoke_test.sh <api_url> [expected_version]
# Env:    SMOKE_WRITE=true also exercises POST /visits (the pipeline sets it for dev only)
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

API_URL="${1:?usage: scripts/smoke_test.sh <api_url> [expected_version]}"
API_URL="${API_URL%/}"
EXPECTED_VERSION="${2:-}"
ATTEMPTS=10

json_field() {
  python3 -c 'import json, sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"
}

# 1. /health returns the version we just deployed. A fresh API or a just-updated
#    function can take a few seconds to serve the new code, so retry briefly.
version=""
for attempt in $(seq 1 "$ATTEMPTS"); do
  if body="$(curl -fsS --max-time 10 "$API_URL/health")"; then
    version="$(printf '%s' "$body" | json_field version)"
    if [[ -z "$EXPECTED_VERSION" || "$version" == "$EXPECTED_VERSION" ]]; then
      log "GET /health ok: version $version (attempt $attempt)"
      break
    fi
    log "GET /health is still serving $version, waiting for $EXPECTED_VERSION"
  fi
  if (( attempt < ATTEMPTS )); then sleep 6; fi
done
[[ -n "$version" ]] || fail "GET /health never answered at $API_URL"
[[ -z "$EXPECTED_VERSION" || "$version" == "$EXPECTED_VERSION" ]] \
  || fail "GET /health serves $version, expected $EXPECTED_VERSION"

# 2. The read path reaches DynamoDB.
before="$(curl -fsS --max-time 10 "$API_URL/visits" | json_field visits)"
[[ "$before" =~ ^[0-9]+$ ]] || fail "GET /visits returned '$before', expected a number"
log "GET /visits ok: $before"

# 3. The write path works (dev only, so prod data stays real).
if [[ "${SMOKE_WRITE:-false}" == "true" ]]; then
  after="$(curl -fsS --max-time 10 -X POST "$API_URL/visits" | json_field visits)"
  if ! [[ "$after" =~ ^[0-9]+$ ]] || (( after <= before )); then
    fail "POST /visits returned $after, expected more than $before"
  fi
  log "POST /visits ok: $before -> $after"
fi

# 4. Unknown routes are rejected by API Gateway, not handled by a catch-all.
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$API_URL/does-not-exist")"
[[ "$code" == "404" ]] || fail "GET /does-not-exist returned $code, expected 404"
log "Unknown route ok: 404"

log "Smoke test passed"
