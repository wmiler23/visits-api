#!/usr/bin/env bash
# Upload the Lambda bundle to S3, once per commit. If the object already
# exists (a re-run), it is reused, so every environment deploys the same bytes.
#
# Usage:  scripts/publish_bundle.sh dist/app.zip
# Needs:  AWS credentials, ARTIFACT_BUCKET, ARTIFACT_KEY
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

ZIP="${1:?usage: scripts/publish_bundle.sh <zip>}"
: "${ARTIFACT_BUCKET:?set ARTIFACT_BUCKET}" "${ARTIFACT_KEY:?set ARTIFACT_KEY}"
[[ -f "$ZIP" ]] || fail "$ZIP not found. Run: python scripts/package.py $ZIP"
COMMIT="${GITHUB_SHA:-$(git rev-parse HEAD)}"

if aws s3api head-object --bucket "$ARTIFACT_BUCKET" --key "$ARTIFACT_KEY" >/dev/null 2>&1; then
  log "s3://$ARTIFACT_BUCKET/$ARTIFACT_KEY already exists, reusing it"
else
  log "Uploading $ZIP to s3://$ARTIFACT_BUCKET/$ARTIFACT_KEY"
  aws s3api put-object \
    --bucket "$ARTIFACT_BUCKET" \
    --key "$ARTIFACT_KEY" \
    --body "$ZIP" \
    --checksum-algorithm SHA256 \
    --metadata "commit=$COMMIT" >/dev/null
fi
