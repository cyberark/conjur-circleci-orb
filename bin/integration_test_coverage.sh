#!/usr/bin/env bash
set -euo pipefail

# Using helpers from the secrets-manager-integration-environment-bootstrap repo to setup the environment for integration tests
SUBMODULE_BASE_DIR=secrets-manager-integration-environment-bootstrap
source "./$SUBMODULE_BASE_DIR/scripts/helpers.sh"

validate_deployment_type "$@"
set_compose_file

# Load config to set PROFILE environment variable
CONFIG_FILE="./$SUBMODULE_BASE_DIR/configs/${INTEGRATION_TYPE}.env"
if [[ -f "$CONFIG_FILE" ]]; then
    set -a  # Export all subsequent variable assignments
    source "$CONFIG_FILE"
    set +a  # Stop exporting
    echo "[INFO] Using profile: $PROFILE"
else
    echo "[ERROR] Config file not found: $CONFIG_FILE"
    exit 1
fi

# Always cleanup containers on exit
cleanup() {
	echo "[CLEANUP] Stopping and removing containers and volumes from docker-compose.yml."
	docker compose -f "$COMPOSE_FILE" -f "$SUBMODULE_BASE_DIR/docker-compose/common-services.yml" --profile "$PROFILE" down -v
}
trap cleanup EXIT ERR INT

OUTPUT_DIR="./output-integration"

mkdir -p "$OUTPUT_DIR"

./$SUBMODULE_BASE_DIR/scripts/setup_integration_env.sh "$DEPLOYMENT_TYPE" "$INTEGRATION_TYPE"

docker build -f dockerintegration/Dockerfile.integration -t integration-test .
docker run  --rm \
	-v "$OUTPUT_DIR:/conjur-circleci-orb/output-integration" \
	-v "$(pwd)/$SUBMODULE_BASE_DIR/configs:/configs:rw" \
	-e "CONJUR_URL=${CONJUR_URL}" \
	-e "DEPLOYMENT_TYPE=${DEPLOYMENT_TYPE}" \
	-e "API_KEY=${API_KEY}" \
	-e "PROJECT_ID=${PROJECT_ID}" \
	-e "CONTEXT_ID=${CONTEXT_ID}" \
	integration-test \
	bash -c "test/integration/retrieve_secret_integration_tests.sh && /conjur-circleci-orb/bin/generate_junit_report.sh integration > /conjur-circleci-orb/output-integration/junit.xml"
# TODO: Update the generate_junit_report script to include integration test reports as well