#!/bin/bash
set -euo pipefail

oneTimeSetUp() {
  echo "[SETUP] Uploading GitHub config.yml"

  local FILE_PATH_IN_REPO=".circleci/config.yml"
  local COMMIT_MESSAGE="Add demo upload test file"
  local GITHUB_TOKEN=""
  local OWNER="Itso-Dimitrov-CyberArk"
  local REPO="CircleCiPocDoc"
  local BRANCH="main"
  local USER_AGENT="MyApp-GitHubClient"
  local API_BASE="https://api.github.com"

  local CONTENT
  CONTENT=$(cat ./ci/config.yml)
  local ENCODED_CONTENT
  ENCODED_CONTENT=$(echo -n "$CONTENT" | base64 -w 0)

  local SHA
  SHA=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "User-Agent: $USER_AGENT" \
    "$API_BASE/repos/$OWNER/$REPO/contents/$FILE_PATH_IN_REPO" | jq -r '.sha')

  local JSON_BODY
  JSON_BODY=$(cat <<EOF
{
  "message": "$COMMIT_MESSAGE",
  "content": "$ENCODED_CONTENT",
  "branch": "$BRANCH",
  "sha": "$SHA"
}
EOF
)
  local HTTP_STATUS
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "User-Agent: $USER_AGENT" \
    -H "Content-Type: application/json" \
    --data "$JSON_BODY" \
    "$API_BASE/repos/$OWNER/$REPO/contents/$FILE_PATH_IN_REPO")

  if [[ "$HTTP_STATUS" -ne 200 ]]; then
  echo "[ERROR] GitHub API upload failed with status: $HTTP_STATUS"
  exit 1
fi
}

oneTimeTearDown() {
  echo "[TEARDOWN] Cleaning up"
}

function test_UpliadingTest() {
    echo "test"
    assertEquals 1 1
}

. /usr/bin/shunit2