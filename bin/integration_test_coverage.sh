#!/usr/bin/env bash
set -euo pipefail

SUBMODULE_BASE_DIR=secrets-manager-integration-environment-bootstrap

DEPLOYMENT_TYPE="$1"
INTEGRATION_CONFIG="$2"
OUTPUT_DIR="${3:-output-integration}"

"./$SUBMODULE_BASE_DIR/scripts/create-integration.sh" --name circleci --auth jwt --signing jwks-uri --env-vars true
source "./$SUBMODULE_BASE_DIR/scripts/setup_integration_env.sh" "$DEPLOYMENT_TYPE" "$INTEGRATION_CONFIG" "$OUTPUT_DIR"

cleanup() {
  echo "[CLEANUP] Stopping and removing containers and volumes from docker-compose.yml."
  docker compose -f "$COMPOSE_FILE" -f "$SUBMODULE_BASE_DIR/docker-compose/common-services.yml" --profile "$PROFILE" down -v
}
trap cleanup EXIT ERR INT

docker build -f dockerintegration/Dockerfile.integration -t integration-test .
docker run --rm \
  -v "$OUTPUT_DIR:/conjur-circleci-orb/output-integration" \
  -e "CONJUR_URL=${CONJUR_URL}" \
  -e "DEPLOYMENT_TYPE=${DEPLOYMENT_TYPE}" \
  -e "API_KEY=${API_KEY}" \
  -e "PROJECT_ID=${PROJECT_ID}" \
  -e "CONTEXT_ID=${CONTEXT_ID}" \
  -e "SECRET_PREFIX=${SECRET_PREFIX}" \
  -e "OUTPUT_DIR=/conjur-circleci-orb/output-integration" \
  integration-test \
  bash -c "test/integration/retrieve_secret_integration_tests.sh && /conjur-circleci-orb/bin/generate_junit_report.sh integration > /conjur-circleci-orb/output-integration/junit.xml"