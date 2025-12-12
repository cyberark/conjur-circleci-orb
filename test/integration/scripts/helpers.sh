#!/bin/bash
set -euo pipefail
# Common helper functions

if [[ -z "${DEPLOYMENT_TYPE:-}" && $# -gt 0 ]]; then
    DEPLOYMENT_TYPE="${1}"
fi

export DEPLOYMENT_TYPE

CONJUR_LEADER_CONTAINER="conjur-leader-1.mycompany.local"
CONJUR_CLI_CONTAINER="conjur-cli"
CONJUR_PROXY_CONTAINER="proxy"

function validate_deployment_type() {
	if [[ $# -ne 1 ]]; then
		echo "[ERROR] Usage: $(basename "$0") [oss|enterprise]"
		exit 1
	fi

	case "$DEPLOYMENT_TYPE" in
	"oss")
		echo "[INFO] Using $DEPLOYMENT_TYPE deployment"
		export CONJUR_URL="https://proxy"
		;;
	"enterprise")
		echo "[INFO] Using $DEPLOYMENT_TYPE deployment"
		export CONJUR_URL="https://conjur-leader-1.mycompany.local"
		;;
	*)
		echo "[ERROR] Invalid deployment type: $DEPLOYMENT_TYPE"
		echo "[ERROR] Valid options are: oss, enterprise"
		exit 1
		;;
	esac
	
	echo "[INFO] Conjur URL set to: $CONJUR_URL"
}

function set_compose_file() {
	case "$DEPLOYMENT_TYPE" in
	"oss")
		COMPOSE_FILE="dockerintegration/docker-compose.conjur-oss.yml"
		echo "[INFO] Using OSS compose file: $COMPOSE_FILE"
		;;
	"enterprise")
		COMPOSE_FILE="dockerintegration/docker-compose.conjur-enterprise.yml"
		echo "[INFO] Using Enterprise compose file: $COMPOSE_FILE"
		;;
	*)
		echo "[ERROR] Invalid deployment type for compose file: $DEPLOYMENT_TYPE"
		exit 1
		;;
	esac
}

function leaderExec() {
	docker exec "$CONJUR_LEADER_CONTAINER" "$@"
}

function cliExec() {
	docker exec "$CONJUR_CLI_CONTAINER" "$@"
}

function proxyExec() {
	docker exec "$CONJUR_PROXY_CONTAINER" "$@"
}

# Retrieves the SSL certificate from the Conjur server and saves it to conjur.pem
# - OSS: Connects to proxy of OSS container
# - Enterprise: Connects to the enterprise container
function retrieve_conjur_certificate(){
	case "$DEPLOYMENT_TYPE" in
	"oss")
		proxyExec openssl s_client -connect proxy:443 -showcerts </dev/null 2>/dev/null |
		awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {print $0}' >"conjur.pem"
		;;
	"enterprise")
		leaderExec openssl s_client -connect localhost:443 -showcerts </dev/null 2>/dev/null |
		awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {print $0}' >"conjur.pem"
		;;
	esac
}