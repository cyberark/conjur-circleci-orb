#!/bin/bash
set -euo pipefail
# Common helper functions

if [[ -z "${DEPLOYMENT_TYPE:-}" && $# -gt 0 ]]; then
    DEPLOYMENT_TYPE="${1}"
fi

# Export DEPLOYMENT_TYPE so it's available to sourced scripts
export DEPLOYMENT_TYPE

CONJUR_LEADER_CONTAINER="conjur-leader-1.mycompany.local"
CONJUR_CLI_CONTAINER="conjur-cli"
CONJUR_PROXY_CONTAINER="proxy"
CIRCLECI_YAML_FILE="./test/integration/ci/config.yml"

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

: '
Injects into the CircleCI YAML file the URL of the Conjur instance as well as the SSL certificate,
depending on the deployment type.
 '
function prepare_circleci_yaml() {
	local cert_file="conjur.pem"

	case "$DEPLOYMENT_TYPE" in
	"oss")
		proxyExec openssl s_client -connect proxy:443 -showcerts </dev/null 2>/dev/null |
		awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {print $0}' >"conjur.pem"
		awk '{gsub(/url: ".*"/, "url: \"https://proxy\""); print}' "$CIRCLECI_YAML_FILE" > "${CIRCLECI_YAML_FILE}.tmp" && mv "${CIRCLECI_YAML_FILE}.tmp" "$CIRCLECI_YAML_FILE"
		;;
	"enterprise")
		leaderExec openssl s_client -connect localhost:443 -showcerts </dev/null 2>/dev/null |
		awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {print $0}' >"conjur.pem"
		awk '{gsub(/url: ".*"/, "url: \"https://conjur-leader-1.mycompany.local\""); print}' "$CIRCLECI_YAML_FILE" > "${CIRCLECI_YAML_FILE}.tmp" && mv "${CIRCLECI_YAML_FILE}.tmp" "$CIRCLECI_YAML_FILE"
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
  ' "$CIRCLECI_YAML_FILE" >"${CIRCLECI_YAML_FILE}.tmp" && mv "${CIRCLECI_YAML_FILE}.tmp" "$CIRCLECI_YAML_FILE"

	echo "Certificate updated in $CIRCLECI_YAML_FILE"
}

function set_secrets_in_circleci_yaml_config(){
	local secrets="${1}"
	echo $secrets
	awk -v secrets_var="$secrets" '{gsub(/secrets: ".*"/, "secrets: \"" secrets_var "\""); print}' "$CIRCLECI_YAML_FILE" > "${CIRCLECI_YAML_FILE}.tmp" && mv "${CIRCLECI_YAML_FILE}.tmp" "$CIRCLECI_YAML_FILE"
}