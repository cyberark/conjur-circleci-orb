#!/bin/bash
source "$(dirname "$0")/api_helpers.sh"
source "$(dirname "$0")/scripts/helpers.sh"

DEFINITION_ID=""
PIPELINE_ID=""
WORKFLOW_ID=""
JOB_ID=""

function test_single_secret_retrieval_should_succeed() {
	local expected_secret_value
    expected_secret_value="HelloFromFirstSecret"

	set_secrets_in_circleci_yaml_config "circleci/firstSecret|FIRST_SECRET"
	upload_github_config "test_single_secret_retrieval_should_succeed"

	DEFINITION_ID=$(get_first_definition_id)
	PIPELINE_ID=$(trigger_circleci_pipeline "$DEFINITION_ID" "main" "main")
	WORKFLOW_ID=$(get_workflow_id_from_pipeline "$PIPELINE_ID")

	wait_for_workflow "$WORKFLOW_ID" 5 10 "success"

	JOB_ID=$(get_job_number_from_workflow "$WORKFLOW_ID")
	
	artifact_url=$(get_artifact_from_job "$JOB_ID" "conjur_single_secret_artifact")
	actual_content=$(get_artifact_content_from_job "$artifact_url")

	local output
    output=$(get_step_output_by_name "$JOB_ID" "Fetch Secret")

	assertEquals "Secret value should match expected content" "$expected_secret_value" "$actual_content"
 	assertContains "$output" "::debug Authenticate via Authn-JWT"
 	assertContains "$output" "Authentication Successful."
 	assertContains "$output" "Batch retrieval of secrets succeeded."
 	assertContains "$output" "Secret fetched successfully.  Environment variable FIRST_SECRET set. "
}

function test_multiple_secrets_retrieval_should_succeed() {
	local expected_secret_value
    expected_secrets_values=$(
		cat <<EOF
HelloFromFirstSecret
HelloFromSecondSecret
EOF
	)
	set_secrets_in_circleci_yaml_config "circleci/firstSecret|FIRST_SECRET;circleci/secondSecret|SECOND_SECRET"
	upload_github_config "test_multiple_secrets_retrieval_should_succeed"

	DEFINITION_ID=$(get_first_definition_id)
	PIPELINE_ID=$(trigger_circleci_pipeline "$DEFINITION_ID" "main" "main")
	WORKFLOW_ID=$(get_workflow_id_from_pipeline "$PIPELINE_ID")

	wait_for_workflow "$WORKFLOW_ID" 5 10 "success"

	JOB_ID=$(get_job_number_from_workflow "$WORKFLOW_ID")

	artifact_url=$(get_artifact_from_job "$JOB_ID" "conjur_multiple_secrets_artifact")
	actual_content=$(get_artifact_content_from_job "$artifact_url")

	local output
    output=$(get_step_output_by_name "$JOB_ID" "Fetch Secret")

	assertEquals "Secret value should match expected content" "$expected_secrets_values" "$actual_content"
	assertContains "$output" "::debug Authenticate via Authn-JWT"
 	assertContains "$output" "Authentication Successful."
 	assertContains "$output" "Batch retrieval of secrets succeeded."
 	assertContains "$output" "Secret fetched successfully.  Environment variable FIRST_SECRET set. "
 	assertContains "$output" "Secret fetched successfully.  Environment variable SECOND_SECRET set."
}

function test_non_existing_secrets_retrieval_should_fail() {
	set_secrets_in_circleci_yaml_config "circleci/nonExistingSecret|NON_EXISTING_SECRET"
	upload_github_config "test_non_existing_secrets_retrieval_should_fail"

	DEFINITION_ID=$(get_first_definition_id)
	PIPELINE_ID=$(trigger_circleci_pipeline "$DEFINITION_ID" "main" "main")
	WORKFLOW_ID=$(get_workflow_id_from_pipeline "$PIPELINE_ID")

	wait_for_workflow "$WORKFLOW_ID" 5 10 "failed"

	JOB_ID=$(get_job_number_from_workflow "$WORKFLOW_ID")

	local output
    output=$(get_step_output_by_name "$JOB_ID" "Fetch Secret")

	assertContains "$output" "::debug Authenticate via Authn-JWT"
 	assertContains "$output" "Authentication Successful."
	assertContains "$output" "variable:circleci/nonExistingSecret is empty or not found"
	assertContains "$output" "Batch retrieval failed, falling to single secret fetch."
	assertContains "$output" "Secret(s) are empty or not found :: circleci%2FnonExistingSecret"
}

function test_providing_wrong_certificate_should_fail() {	
	set_conjur_certificate_in_circleci_yaml "./invalid_cert.pem"
	upload_github_config "test_providing_wrong_certificate_should_fail"

	DEFINITION_ID=$(get_first_definition_id)
	PIPELINE_ID=$(trigger_circleci_pipeline "$DEFINITION_ID" "main" "main")
	WORKFLOW_ID=$(get_workflow_id_from_pipeline "$PIPELINE_ID")

	wait_for_workflow "$WORKFLOW_ID" 5 10 "failed"
	JOB_ID=$(get_job_number_from_workflow "$WORKFLOW_ID")

	local output
    output=$(get_step_output_by_name "$JOB_ID" "Fetch Secret")

	assertContains "$output" "::debug Authenticate via Authn-JWT"
 	assertContains "$output" "curl: (60) SSL certificate problem: self-signed certificate"
	assertContains "$output" "Exited with code exit status 60"
}

function test_existing_empty_secret_retrieval_should_fail() {
	set_secrets_in_circleci_yaml_config "circleci/emptySecret|FIRST_SECRET"
	set_conjur_certificate_in_circleci_yaml
	upload_github_config "test_existing_empty_secret_retrieval_should_fail"

	DEFINITION_ID=$(get_first_definition_id)
	PIPELINE_ID=$(trigger_circleci_pipeline "$DEFINITION_ID" "main" "main")
	WORKFLOW_ID=$(get_workflow_id_from_pipeline "$PIPELINE_ID")

	wait_for_workflow "$WORKFLOW_ID" 5 10 "failed"

	JOB_ID=$(get_job_number_from_workflow "$WORKFLOW_ID")
	
	local output
    output=$(get_step_output_by_name "$JOB_ID" "Fetch Secret")

	assertContains "$output" "::debug Authenticate via Authn-JWT"
 	assertContains "$output" "Authentication Successful."
	assertContains "$output" "variable:circleci/emptySecret is empty or not found."
	assertContains "$output" "Batch retrieval failed, falling to single secret fetch."
 	assertContains "$output" "Secret(s) are empty or not found :: circleci%2FemptySecret"
}

# There is a bug currently and the host access denial is not working as expected.
# Once fixed this test should be enabled: https://ca-il-jira.il.cyber-ark.com:8443/browse/CNJR-12020
# function test_host_access_to_variable_should_be_denied() {
# 	set_secrets_in_circleci_yaml_config "circleci/secretWithoutHostPermit|FIRST_SECRET"
# 	set_conjur_certificate_in_circleci_yaml
# 	upload_github_config "test_host_access_to_variable_should_be_denied"

# 	DEFINITION_ID=$(get_first_definition_id)
# 	PIPELINE_ID=$(trigger_circleci_pipeline "$DEFINITION_ID" "main" "main")
# 	WORKFLOW_ID=$(get_workflow_id_from_pipeline "$PIPELINE_ID")

# 	wait_for_workflow "$WORKFLOW_ID" 5 10 "failed"

# 	JOB_ID=$(get_job_number_from_workflow "$WORKFLOW_ID")
	
# 	local output
#     output=$(get_step_output_by_name "$JOB_ID" "Fetch Secret")

# 	assertContains "$output" "::debug Authenticate via Authn-JWT"
#  	TODO: Add assertContains for access denied message when the bug is fixed
# }

# Load shUnit2
. /usr/bin/shunit2
