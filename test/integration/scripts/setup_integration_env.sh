#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

COMPOSE_FILE="dockerIntegration/docker-compose.conjur.yml"
CONJUR_CLI_CONTAINER="conjur-cli"
CONJUR_LEADER_CONTAINER="conjur-leader-1.mycompany.local"

# Create and start all the services from compose file and 
# Configure Conjur master (sets up admin password, account, and initial settings)
function setup_environment() {
    echo "[INFO] Start all the services from compose file"
    docker compose -f "$COMPOSE_FILE" up -d
    echo "[INFO] Configuring Conjur master"
    docker exec $CONJUR_LEADER_CONTAINER bash /scripts/configure-conjur.sh
}

# Connects a running container to a specified Docker network
function join_network() {
    local container="$1"
    local network="$2"

    if docker network inspect "${network}" > /dev/null 2>&1
    then
        echo "[INFO] Network '${network}' already exists"
    else
        echo "[WARN] Network '${network}' doesn't exist. Creating it"
        docker network create "${network}" > /dev/null
    fi

    docker network connect "$network" "$container"
    echo "[INFO] Connected container '$container' to network '$network'"
}

# Runs the CLI configuration script
function setup_conjur_cli() {
    echo "[INFO] Configuring Conjur CLI"
    docker exec $CONJUR_CLI_CONTAINER bash /scripts/configure-cli.sh
}

function configure_jwt() {
    echo "[INFO] Configuring JWT: loading policies, and setting variables."
    docker exec $CONJUR_CLI_CONTAINER bash /scripts/configure-jwt.sh
}

# Removes all containers and volumes for the integration environment
# Only removes on error (non-zero exit code)
function cleanup() {
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo "[ERROR] Removing containers due to failure (exit code: $exit_code)"
        docker compose -f "$COMPOSE_FILE" down -v
    fi
}
trap cleanup EXIT

main() {
  setup_environment
  setup_conjur_cli
  configure_jwt
  inject_conjur_cert_into_yaml
}
main

echo "[INFO] Integration environment is ready."