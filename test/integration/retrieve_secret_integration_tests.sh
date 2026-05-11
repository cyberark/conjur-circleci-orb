#!/bin/bash
source "$(dirname "$0")/api_helpers.sh"
source "./secrets-manager-integration-environment-bootstrap/scripts/helpers.sh"

# Load the deployment-specific secret prefix
load_secret_prefix

DEFINITION_ID=""
PIPELINE_ID=""
WORKFLOW_ID=""
JOB_ID=""
CONJUR_CERTIFICATE_VALID_B64=""
CONJUR_CERTIFICATE_INVALID_B64=""
TEST_ORB=""

function oneTimeSetUp() {
	# Read published orb version if available
  if [[ -f "orbversion/.published_orb_version" ]]; then
    TEST_ORB=$(cat "orbversion/.published_orb_version")
    echo "Testing with published orb: $TEST_ORB"
  else
    echo "No published orb version found, using default"
  fi

  local cert_path="./conjur.pem"
  if [[ -f "./output-integration/conjur.pem" ]]; then
    cert_path="./output-integration/conjur.pem"
  fi

  CONJUR_CERTIFICATE_VALID_B64=$(base64 < "$cert_path" | tr -d '\n')
  CONJUR_CERTIFICATE_INVALID_B64=$(base64 < ./invalid_cert.pem | tr -d '\n')
  add_or_update_environment_variable "CONJUR_CERTIFICATE_B64" "$CONJUR_CERTIFICATE_VALID_B64"
}

function test_single_secret_retrieval_should_succeed() {
	local expected_secret_value
    expected_secret_value="HelloFromFirstSecret"

	DEFINITION_ID=$(get_first_definition_id)
	echo "CONJUR URL: $CONJUR_URL"
	PIPELINE_ID=$(trigger_circleci_pipeline "$DEFINITION_ID" "circleci-project-setup" "circleci-project-setup" "$SECRET_PREFIX/firstSecret|FIRST_SECRET" "$CONJUR_URL" "$TEST_ORB")
	WORKFLOW_ID=$(get_workflow_id_from_pipeline "$PIPELINE_ID")
	wait_for_workflow "$WORKFLOW_ID" 6 10 "success"

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

	DEFINITION_ID=$(get_first_definition_id)
	PIPELINE_ID=$(trigger_circleci_pipeline "$DEFINITION_ID" "circleci-project-setup" "circleci-project-setup" "$SECRET_PREFIX/firstSecret|FIRST_SECRET;$SECRET_PREFIX/secondSecret|SECOND_SECRET" "$CONJUR_URL" "$TEST_ORB")
	WORKFLOW_ID=$(get_workflow_id_from_pipeline "$PIPELINE_ID")

	wait_for_workflow "$WORKFLOW_ID" 6 10 "success"

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
	DEFINITION_ID=$(get_first_definition_id)
	PIPELINE_ID=$(trigger_circleci_pipeline "$DEFINITION_ID" "circleci-project-setup" "circleci-project-setup" "$SECRET_PREFIX/nonExistingSecret|NON_EXISTING_SECRET" "$CONJUR_URL" "$TEST_ORB")
	WORKFLOW_ID=$(get_workflow_id_from_pipeline "$PIPELINE_ID")

	wait_for_workflow "$WORKFLOW_ID" 6 10 "failed"

	JOB_ID=$(get_job_number_from_workflow "$WORKFLOW_ID")

	local output
    output=$(get_step_output_by_name "$JOB_ID" "Fetch Secret")

	assertContains "$output" "::debug Authenticate via Authn-JWT"
 	assertContains "$output" "Authentication Successful."
	assertContains "$output" "variable:$SECRET_PREFIX/nonExistingSecret is empty or not found"
	assertContains "$output" "Batch retrieval failed, falling to single secret fetch."
	assertContains "$output" "Secret(s) are empty or not found"
}

function test_providing_wrong_certificate_should_fail() {
	# Skip this test for SaaS deployments - they use trusted CA certificates
	if [[ "${DEPLOYMENT_TYPE:-}" == "saas" ]]; then
		echo "[INFO] Skipping certificate test for SaaS deployment - uses trusted CA certificates"
		return 0
	fi
	
	add_or_update_environment_variable "CONJUR_CERTIFICATE_B64" "$CONJUR_CERTIFICATE_INVALID_B64"

	DEFINITION_ID=$(get_first_definition_id)
	PIPELINE_ID=$(trigger_circleci_pipeline "$DEFINITION_ID" "circleci-project-setup" "circleci-project-setup" "$SECRET_PREFIX/firstSecret|FIRST_SECRET" "$CONJUR_URL" "$TEST_ORB")
	WORKFLOW_ID=$(get_workflow_id_from_pipeline "$PIPELINE_ID")

	wait_for_workflow "$WORKFLOW_ID" 6 10 "failed"
	JOB_ID=$(get_job_number_from_workflow "$WORKFLOW_ID")

	local output
    output=$(get_step_output_by_name "$JOB_ID" "Fetch Secret")

	assertContains "$output" "::debug Authenticate via Authn-JWT"
 	assertContains "$output" "curl: (60) SSL certificate problem: self-signed certificate"
	assertContains "$output" "Exited with code exit status 60"
}

function test_existing_empty_secret_retrieval_should_fail() {
	add_or_update_environment_variable "CONJUR_CERTIFICATE_B64" "$CONJUR_CERTIFICATE_VALID_B64"

	DEFINITION_ID=$(get_first_definition_id)
	PIPELINE_ID=$(trigger_circleci_pipeline "$DEFINITION_ID" "circleci-project-setup" "circleci-project-setup" "$SECRET_PREFIX/emptySecret|FIRST_SECRET" "$CONJUR_URL" "$TEST_ORB")
	WORKFLOW_ID=$(get_workflow_id_from_pipeline "$PIPELINE_ID")

	wait_for_workflow "$WORKFLOW_ID" 6 10 "failed"

	JOB_ID=$(get_job_number_from_workflow "$WORKFLOW_ID")
	
	local output
    output=$(get_step_output_by_name "$JOB_ID" "Fetch Secret")

	assertContains "$output" "::debug Authenticate via Authn-JWT"
 	assertContains "$output" "Authentication Successful."
	assertContains "$output" "variable:$SECRET_PREFIX/emptySecret is empty or not found."
	assertContains "$output" "Batch retrieval failed, falling to single secret fetch."
 	assertContains "$output" "Secret(s) are empty or not found"
}

# There is a bug currently and the host access denial is not working as expected.
# Once fixed this test should be enabled: https://ca-il-jira.il.cyber-ark.com:8443/browse/CNJR-12020
# function test_host_access_to_variable_should_be_denied() {
# 	DEFINITION_ID=$(get_first_definition_id)
# 	PIPELINE_ID=$(trigger_circleci_pipeline "$DEFINITION_ID" "circleci-project-setup" "circleci-project-setup")
# 	WORKFLOW_ID=$(get_workflow_id_from_pipeline "$PIPELINE_ID")

# 	wait_for_workflow "$WORKFLOW_ID" 6 10 "failed"

# 	JOB_ID=$(get_job_number_from_workflow "$WORKFLOW_ID")
	
# 	local output
#     output=$(get_step_output_by_name "$JOB_ID" "Fetch Secret")

# 	assertContains "$output" "::debug Authenticate via Authn-JWT"
#  	TODO: Add assertContains for access denied message when the bug is fixed
# }

# Load shUnit2
. /usr/bin/shunit2