#!/bin/bash
source "$(dirname "$0")/api_helpers.sh"

DEFINITION_ID=""
PIPELINE_ID=""
WORKFLOW_ID=""
JOB_ID=""

oneTimeSetUp() {
	upload_github_config

	DEFINITION_ID=$(get_first_definition_id)
	echo "$DEFINITION_ID"
	PIPELINE_ID=$(trigger_circleci_pipeline "$DEFINITION_ID" "main" "main")
	WORKFLOW_ID=$(get_workflow_id_from_pipeline "$PIPELINE_ID")

	wait_for_workflow_complete "$WORKFLOW_ID" 5 10

	JOB_ID=$(get_job_number_from_workflow "$WORKFLOW_ID")
}

function test_single_secret_retrieval() {
	local expected_secret="HelloFromFirstSecret"

	artifact_url=$(get_artifact_from_job "$JOB_ID" "conjur_single_secret_artifact")

	actual_content=$(get_artifact_content_from_job "$artifact_url")
	assertEquals "Secret value should match expected content" "$expected_secret" "$actual_content"
}

function test_multiple_secrets_retrieval() {
	expected_secrets=$(
		cat <<EOF
HelloFromFirstSecret
HelloFromSecondSecret
EOF
	)
	artifact_url=$(get_artifact_from_job "$JOB_ID" "conjur_multiple_secrets_artifact")
	actual_content=$(get_artifact_content_from_job "$artifact_url")
	assertEquals "Secret value should match expected content" "$expected_secrets" "$actual_content"

}

# Load shUnit2
. /usr/bin/shunit2
