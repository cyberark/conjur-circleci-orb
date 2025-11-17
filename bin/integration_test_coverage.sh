#!/usr/bin/env bash

set -euo pipefail

# Always cleanup Dockerfile.integration on exit
cleanup() {
	echo "[CLEANUP] Stopping and removing containers and volumes from docker-compose.yml."
	docker-compose -f dockerIntegration/docker-compose.conjur.yml down -v
}
trap cleanup EXIT ERR INT

OUTPUT_DIR="./output-integration"

mkdir -p "$OUTPUT_DIR"

./test/integration/scripts/setup_integration_env.sh

docker build -f dockerintegration/Dockerfile.integration -t integration-test .

docker run --rm \
	-v "$OUTPUT_DIR:/conjur-circleci-orb/output-integration" \
	integration-test \
	bash -c "test/integration/retrieve_secret_integration_tests.sh && \
           /conjur-circleci-orb/bin/generate_junit_report.sh integration > /conjur-circleci-orb/output-integration/junit.xml"
# TODO: Update the generate_junit_report script to include integration test reports as well
