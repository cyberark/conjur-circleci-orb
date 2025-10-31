#!/bin/bash
set -euo pipefail

function get_first_definition_id() {
  local response
  response=$(curl -s -L https://circleci.com/api/v2/projects/72974ed5-1055-4b5f-86fd-cddd77e44c01/pipeline-definitions/ \
    -H 'Circle-Token: ')
  
   echo "$response" | jq -r '.items[0].id'
}

function trigger_circleci_pipeline() {
  local definition_id="$1"
  local config_branch="$2"
  local checkout_branch="$3"

  local response
  response=$(curl -X POST "https://circleci.com/api/v2/project/circleci/1c7e7303-b9fc-427b-9dcc-e9976ec6e1c6/72974ed5-1055-4b5f-86fd-cddd77e44c01/pipeline/run" \
    -H "Circle-Token: " \
    -H "Content-Type: application/json" \
    --data '{"definition_id":"'"${definition_id}"'","config":{"branch":"'"${config_branch}"'"},"checkout":{"branch":"'"${checkout_branch}"'"}}')

    echo "$response" | jq -r '.id'
}

function get_workflow_id_from_pipeline() {
  local pipeline_id="$1"

  local response
  response=$(curl -s -L "https://circleci.com/api/v2/pipeline/${pipeline_id}/workflow" \
    -H 'Circle-Token: ')
    echo "$response" | jq -r '.items[0].id'
}

#TODO function to retrieve job information so I can take the job number and then to get artificat
#   --url https://circleci.com/api/v2/workflow/260729b9-c07e-48e4-850a-6c544d103546/job \ -> Will return job number per workflow id 
#  https://circleci.com/api/v2/project/circleci/1c7e7303-b9fc-427b-9dcc-e9976ec6e1c6/72974ed5-1055-4b5f-86fd-cddd77e44c01//182/artifacts \ -> Will return artifact per job number

function wait_for_workflow_complete() {
  local workflow_id="$1"
  local max_attempts="$2"
  local interval="$3"
  local attempt=1
  local status=""

  while ((attempt <= max_attempts )); do
    response=$(curl -s "https://circleci.com/api/v2/workflow/$workflow_id" \
    -H 'Circle-Token: ')

     status=$(echo "$response" | jq -r '.status')
     
    if [[ "$status" == "success" ]]; then
      echo "Workflow succeeded."
      return 0
    elif [[ "$status" == "failed" ]]; then
      echo "Workflow failed."
      return 1
    fi

    ((attempt++))
    sleep "$interval"
  done

  echo "Maximum attempts reached without completion."
  return 124
}

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
  CONTENT=$(cat test/integration/ci/config.yml)
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

DEFINITION_ID=$(get_first_definition_id)
PIPELINE_ID=$(trigger_circleci_pipeline "$DEFINITION_ID" "main" "main")
echo "$PIPELINE_ID"
WORKFLOW_ID=$(get_workflow_id_from_pipeline "$PIPELINE_ID")
echo "$WORKFLOW_ID"
wait_for_workflow_complete "$WORKFLOW_ID" 60 10
}

function oneTimeTearDown() {
  echo "[TEARDOWN] Cleaning up"
}

# function test_retrieve_single_secret() {
#     assert pass pass
# }

# Load shUnit2
. /usr/bin/shunit2