#!/bin/bash
set -euo pipefail
set -euo errexit

COMPOSE_FILE=""
CONJUR_CLI_CONTAINER="conjur-cli"
CONJUR_LEADER_CONTAINER="conjur-leader-1.mycompany.local"
CONJUR_NETWORK="conjur"

# Create and start all the services from compose file and 
# Configure Conjur master (sets up admin password, account, and initial settings)
function setup_environment() {
    echo "[INFO] Start all the services from compose file"
    docker compose -f "$COMPOSE_FILE" up -d
    echo "[INFO] Configuring Conjur master"
    docker exec $CONJUR_LEADER_CONTAINER bash ./configure-conjur.sh configure
}

# Connects a running container to a specified Docker network
function join_network() {
    local container="$1"
    local network="$1"

    if docker network inspect "${network}" > /dev/null 2>&1
    then
        echo "[INFO] Network '${network}' already exists"
    else
        echo "[WARN] Network '${network}' doesn't exist; creating it"
        docker network create "${network}" > /dev/null
    fi

    docker network connect "$network" "$container"
    echo "[INFO] Connected container '$container' to network '$network'"
}

# Removes all containers and volumes for the integration environment
# Called automatically on script error (via trap)
function cleanup() {
  echo "[ERROR] Removing containers due to failure"
  docker compose -f "$COMPOSE_FILE" down -v || true
}

# Runs the CLI configuration script
function setup_conjur_cli() {
    echo "[INFO] Configuring Conjur CLI"
    docker exec $CONJUR_CLI_CONTAINER bash /cli-config/configure-cli.sh
}

main() {
  setup_environment
  join_network "$CONJUR_CLI_CONTAINER" "$CONJUR_NETWORK"
  join_network "$CONJUR_LEADER_CONTAINER" "$CONJUR_NETWORK"
  join_network "$CONJUR_CLI_CONTAINER" "$CONJUR_NETWORK"
  setup_conjur_cli
}

trap cleanup ERR 
main
echo "[INFO] Integration environment is ready."