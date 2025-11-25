#!/bin/bash
set -euo pipefail
# Common helper functions

DEPLOYMENT_TYPE="${1}"

CONJUR_LEADER_CONTAINER="conjur-leader-1.mycompany.local"
CONJUR_CLI_CONTAINER="conjur-cli"
CONJUR_PROXY_CONTAINER="proxy"

function validate_deployment_type() {
	if [[ $# -ne 1 ]]; then
		echo "[ERROR] Usage: $(basename "$0") [oss|enterprise]"
		exit 1
	fi

	case "$DEPLOYMENT_TYPE" in
	"oss" | "enterprise")
		echo "[INFO] Using $DEPLOYMENT_TYPE deployment"
		;;
	*)
		echo "[ERROR] Invalid deployment type: $DEPLOYMENT_TYPE"
		echo "[ERROR] Valid options are: oss, enterprise"
		exit 1
		;;
	esac
}

function set_compose_file() {
	case "$DEPLOYMENT_TYPE" in
	"oss")
		COMPOSE_FILE="dockerIntegration/docker-compose.conjur-oss.yml"
		echo "[INFO] Using OSS compose file: $COMPOSE_FILE"
		;;
	"enterprise")
		COMPOSE_FILE="dockerIntegration/docker-compose.conjur-enterprise.yml"
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

function inject_conjur_cert_into_yaml() {
	local cert_file="conjur.pem"
	local yaml_file="test/integration/ci/config.yml"

	case "$DEPLOYMENT_TYPE" in
	"oss")
		proxyExec openssl s_client -connect proxy:443 -showcerts </dev/null 2>/dev/null |
		awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {print $0}' >"conjur.pem"
		awk '{gsub(/url: ".*"/, "url: \"https://proxy\""); print}' "$yaml_file" > "${yaml_file}.tmp" && mv "${yaml_file}.tmp" "$yaml_file"
		;;
	"enterprise")
		leaderExec openssl s_client -connect localhost:443 -showcerts </dev/null 2>/dev/null |
		awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {print $0}' >"conjur.pem"
		awk '{gsub(/url: ".*"/, "url: \"https://conjur-leader-1.mycompany.local\""); print}' "$yaml_file" > "${yaml_file}.tmp" && mv "${yaml_file}.tmp" "$yaml_file"
		;;
	esac
    
	# Replace only the certificate block in the YAML file
	awk -v cert_file="$cert_file" '
    BEGIN {in_cert=0}
    /^[ ]{10}certificate: \|/ {
      print; in_cert=1;
      while((getline line < cert_file) > 0) print "            " line;
      next
    }
    in_cert && (/^[ ]{12}/ || /^$/) {next}
    in_cert && !/^[ ]{12}/ {in_cert=0}
    {print}
  ' "$yaml_file" >"${yaml_file}.tmp" && mv "${yaml_file}.tmp" "$yaml_file"

	echo "Certificate updated in $yaml_file"
}