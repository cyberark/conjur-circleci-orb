#!/bin/bash

CIRCLECI_TOKEN=""
CIRCLECI_API_BASE="https://circleci.com/api/v2"
CIRCLECI_PROJECT_SLUG="circleci/1c7e7303-b9fc-427b-9dcc-e9976ec6e1c6/72974ed5-1055-4b5f-86fd-cddd77e44c01"
CIRCLECI_PIPELINE_DEFINITIONS_URL="$CIRCLECI_API_BASE/projects/72974ed5-1055-4b5f-86fd-cddd77e44c01/pipeline-definitions/"

GITHUB_TOKEN=""
GITHUB_OWNER="Itso-Dimitrov-CyberArk"
GITHUB_REPO="CircleCiPocDoc"
GITHUB_BRANCH="main"
GITHUB_USER_AGENT="MyApp-GitHubClient"
GITHUB_API_BASE="https://api.github.com"

# === GitHub API: Upload config.yml ===
# Uploads a local config.yml to the GitHub repo as .circleci/config.yml
function upload_github_config() {
	echo "[SETUP] Uploading GitHub config.yml"

	local FILE_PATH_IN_REPO=".circleci/config.yml"
	local COMMIT_MESSAGE="Add demo upload test file"
	local CONTENT
	local ENCODED_CONTENT
	local SHA
	local JSON_BODY
	local HTTP_STATUS

	CONTENT=$(cat test/integration/ci/config.yml)
	ENCODED_CONTENT=$(echo -n "$CONTENT" | base64 -w 0)

	SHA=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
		-H "User-Agent: $GITHUB_USER_AGENT" \
		"$GITHUB_API_BASE/repos/$GITHUB_OWNER/$GITHUB_REPO/contents/$FILE_PATH_IN_REPO" | jq -r '.sha')

	JSON_BODY=$(
		cat <<EOF
{
  "message": "$COMMIT_MESSAGE",
  "content": "$ENCODED_CONTENT",
  "branch": "$GITHUB_BRANCH",
  "sha": "$SHA"
}
EOF
	)

	HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
		-H "Authorization: Bearer $GITHUB_TOKEN" \
		-H "User-Agent: $GITHUB_USER_AGENT" \
		-H "Content-Type: application/json" \
		--data "$JSON_BODY" \
		"$GITHUB_API_BASE/repos/$GITHUB_OWNER/$GITHUB_REPO/contents/$FILE_PATH_IN_REPO")

	if [[ "$HTTP_STATUS" -ne 200 ]]; then
		echo "[ERROR] GitHub API upload failed with status: $HTTP_STATUS"
		exit 1
	fi
}

# === CircleCI API Functions ===
# Gets the first pipeline definition ID from CircleCI project
function get_first_definition_id() {
	local response
	response=$(curl -s -L "$CIRCLECI_PIPELINE_DEFINITIONS_URL" \
		-H "Circle-Token: $CIRCLECI_TOKEN")
	echo "$response" | jq -r '.items[0].id'
}

# Triggers a CircleCI pipeline using a definition ID, branch and checkout names
function trigger_circleci_pipeline() {
	local definition_id="$1"
	local config_branch="$2"
	local checkout_branch="$3"

	# Request Body/Data could be in a separate JSON file
	local response
	response=$(curl -X POST "$CIRCLECI_API_BASE/project/$CIRCLECI_PROJECT_SLUG/pipeline/run" \
		-H "Circle-Token: $CIRCLECI_TOKEN" \
		-H "Content-Type: application/json" \
		--data '{"definition_id":"'"${definition_id}"'","config":{"branch":"'"${config_branch}"'"},"checkout":{"branch":"'"${checkout_branch}"'"}}')
	echo "$response" | jq -r '.id'
}

# Gets the workflow ID from a given pipeline ID
function get_workflow_id_from_pipeline() {
	local pipeline_id="$1"
	local response
	response=$(curl -s -L "$CIRCLECI_API_BASE/pipeline/${pipeline_id}/workflow" \
		-H "Circle-Token: $CIRCLECI_TOKEN")
	echo "$response" | jq -r '.items[0].id'
}

# Gets the job number from a given workflow ID
function get_job_number_from_workflow() {
	local workflow_id="$1"
	local response
	response=$(curl -s -L "$CIRCLECI_API_BASE/workflow/${workflow_id}/job" \
		-H "Circle-Token: $CIRCLECI_TOKEN")
	echo "$response" | jq -r '.items[0].job_number'
}

# Gets the artifact URL for a specific job and artifact path
function get_artifact_from_job() {
	local job_number="$1"
	local artifact_path="$2"

	local response
	response=$(curl -s -L "$CIRCLECI_API_BASE/project/$CIRCLECI_PROJECT_SLUG/${job_number}/artifacts" \
		-H "Circle-Token: $CIRCLECI_TOKEN")
	echo "$response" | jq -r --arg path "$artifact_path" '.items[] | select(.path==$path) | .url'
}

# Waits for a CircleCI workflow to complete, polling for status
function wait_for_workflow_complete() {
	local workflow_id="$1"
	local max_attempts="$2"
	local interval="$3"
	local attempt=1
	local status=""
	local response

	echo "Waiting for CircleCI workflow to complete, Workflow ID: $workflow_id, Max Attempts: $max_attempts, Interval: ${interval}s"

	while ((attempt <= max_attempts)); do
		echo "Attempt $attempt of $max_attempts"
		response=$(curl -s "$CIRCLECI_API_BASE/workflow/$workflow_id" \
			-H "Circle-Token: $CIRCLECI_TOKEN")

		status=$(echo "$response" | jq -r '.status')
		echo "   Current status: $status"

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

# Downloads and returns the content of an artifact from its URL
function get_artifact_content_from_job() {
	local artifact_url="$1"

	curl -L -s -H "Circle-Token: $CIRCLECI_TOKEN" "$artifact_url"
}
