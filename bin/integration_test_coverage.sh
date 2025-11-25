#!/usr/bin/env bash
set -euo pipefail
source "./test/integration/scripts/helpers.sh"

validate_deployment_type "$@"
set_compose_file

# Always cleanup containers on exit
cleanup() {
	echo "[CLEANUP] Stopping and removing containers and volumes from docker-compose.yml."
	docker-compose -f "$COMPOSE_FILE" down -v
}
trap cleanup EXIT ERR INT

OUTPUT_DIR="./output-integration"

mkdir -p "$OUTPUT_DIR"

./test/integration/scripts/setup_integration_env.sh "$DEPLOYMENT_TYPE"

docker build -f dockerintegration/Dockerfile.integration -t integration-test .

docker run --rm \
	-v "$OUTPUT_DIR:/conjur-circleci-orb/output-integration" \
	integration-test \
	bash -c "test/integration/retrieve_secret_integration_tests.sh && /conjur-circleci-orb/bin/generate_junit_report.sh integration > /conjur-circleci-orb/output-integration/junit.xml"
# TODO: Update the generate_junit_report script to include integration test reports as well
