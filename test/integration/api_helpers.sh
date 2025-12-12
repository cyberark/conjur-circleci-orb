#!/bin/bash

CIRCLECI_TOKEN="$API_KEY"
CIRCLECI_API_BASE_V2="https://circleci.com/api/v2"
CIRCLECI_API_BASE_V1="https://circleci.com/api/v1.1"
CIRCLECI_PROJECT_SLUG="circleci/c05f5799-3c32-45e3-98dd-cb4e90373966/$PROJECT_ID"
CIRCLECI_PIPELINE_DEFINITIONS_URL="$CIRCLECI_API_BASE_V2/projects/$PROJECT_ID/pipeline-definitions/"
CIRCLECI_CONTEXT_ID="$CONTEXT_ID"  # CircleCI Context ID for storing environment variables

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
	local conjur_secrets="$4"
	local conjur_url="$5"
	local conjur_orb="${6:-cyberark/conjur-circleci-orb@0.0.2}"

	# Build JSON payload for pipeline trigger
	local json_data
	json_data=$(cat <<EOF
{
	"definition_id": "${definition_id}",
	"config": {
		"branch": "${config_branch}"
	},
	"checkout": {
		"branch": "${checkout_branch}"
	},
	"parameters": {
		"conjur_secrets": "${conjur_secrets}",
		"conjur_url": "${conjur_url}",
		"conjur_orb": "${conjur_orb}"
	}
}
EOF
	)

	local response
	response=$(curl -X POST "$CIRCLECI_API_BASE_V2/project/$CIRCLECI_PROJECT_SLUG/pipeline/run" \
		-H "Circle-Token: $CIRCLECI_TOKEN" \
		-H "Content-Type: application/json" \
		--data "$json_data")
	echo "$response" | jq -r '.id'
}

# Gets the workflow ID from a given pipeline ID
function get_workflow_id_from_pipeline() {
	local pipeline_id="$1"
	local max_attempts=3
	local interval=3
	
	local attempt=1
	local workflow_id
	local response

	echo "Getting workflow ID for pipeline: $pipeline_id, Max Attempts: $max_attempts, Interval: ${interval}s" >&2

	while ((attempt <= max_attempts)); do
		echo "Attempt $attempt of $max_attempts" >&2
		response=$(curl -s -L "$CIRCLECI_API_BASE_V2/pipeline/${pipeline_id}/workflow" \
			-H "Circle-Token: $CIRCLECI_TOKEN")

		workflow_id=$(echo "$response" | jq -r '.items[0].id')
		echo "Workflow ID: $workflow_id" >&2

		if [[ "$workflow_id" != "null" && -n "$workflow_id" ]]; then
			echo "Workflow found: $workflow_id" >&2
			echo "$workflow_id"
			return 0
		fi

		((attempt++))
		sleep "$interval"
	done

	echo "Maximum attempts reached without finding workflow ID." >&2
	return 124
}

function add_or_update_environment_variable() {
	local variable_name="$1"
	local variable_value="$2"
	
	local json_payload
	json_payload=$(jq -n --arg value "$variable_value" '{"value": $value}')
	
	local response
	response=$(curl -s --request PUT \
		--url "https://circleci.com/api/v2/context/${CIRCLECI_CONTEXT_ID}/environment-variable/${variable_name}" \
		--header "Circle-Token: $CIRCLECI_TOKEN" \
		--header "Content-Type: application/json" \
		--data "$json_payload")
	echo "$response"
}

# Gets the job number from a given workflow ID
function get_job_number_from_workflow() {
	local workflow_id="$1"
	local response
	response=$(curl -s -L "$CIRCLECI_API_BASE_V2/workflow/${workflow_id}/job" \
		-H "Circle-Token: $CIRCLECI_TOKEN")
	echo "$response" | jq -r '.items[0].job_number'
}

# Gets the artifact URL for a specific job and artifact path
function get_artifact_from_job() {
	local job_number="$1"
	local artifact_path="$2"

	local response
	response=$(curl -s -L "$CIRCLECI_API_BASE_V2/project/$CIRCLECI_PROJECT_SLUG/${job_number}/artifacts" \
		-H "Circle-Token: $CIRCLECI_TOKEN")
	echo "$response" | jq -r --arg path "$artifact_path" '.items[] | select(.path==$path) | .url'
}

# Waits for a CircleCI workflow to complete, polling for status
function wait_for_workflow() {
	local workflow_id="$1"
	local max_attempts="$2"
	local interval="$3"
	local expected_status="$4"
	
	local attempt=1
	local current_status
	local response

	echo "Waiting for CircleCI workflow to reach status '$expected_status', Workflow ID: $workflow_id, Max Attempts: $max_attempts, Interval: ${interval}s"

	while ((attempt <= max_attempts)); do
		echo "Attempt $attempt of $max_attempts"
		response=$(curl -s "$CIRCLECI_API_BASE_V2/workflow/$workflow_id" \
			-H "Circle-Token: $CIRCLECI_TOKEN")
			
		current_status=$(echo "$response" | jq -r '.status')
		echo "Current status: $current_status"

		if [[ "$current_status" == "$expected_status" ]]; then
			echo "Workflow reached expected status: $expected_status"
			return 0
		elif [[ "$current_status" == "failed" && "$expected_status" != "failed" ]]; then
			echo "Workflow failed unexpectedly."
			return 1
		fi

		((attempt++))
		sleep "$interval"
	done

	echo "Maximum attempts reached without reaching expected status '$expected_status'."
	return 124
}

function get_artifact_content_from_job() {
	local artifact_url="$1"

	curl -L -s -H "Circle-Token: $CIRCLECI_TOKEN" "$artifact_url"
}

function get_step_output_by_name() {
	local job_number="$1"
	local step_name="$2"
	
	local response
	response=$(curl -s "$CIRCLECI_API_BASE_V1/project/${CIRCLECI_PROJECT_SLUG}/${job_number}" \
	         -H "Circle-Token: $CIRCLECI_TOKEN")
	
	local step_output_url
	step_output_url=$(echo "$response" | jq -r --arg name "$step_name" '.steps[] | select(.name == $name) | .actions[0].output_url // empty')
	
	if [[ -n "$step_output_url" ]]; then
		curl -s -L "$step_output_url"
	fi
}