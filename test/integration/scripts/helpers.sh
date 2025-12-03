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


#Injects into the CircleCI YAML file the SSL certificate fetched from the Conjur server
function set_conjur_certificate_in_circleci_yaml() {
	local cert_file="${1:-conjur.pem}"

   	awk -v cert_file="$cert_file" '
    BEGIN {
      while((getline line < cert_file) > 0) {
        cert_lines[++cert_count] = "            " line
      }
      close(cert_file)
      in_cert=0
    }
    /certificate: \|/ {
      print; in_cert=1;
      for(i=1; i<=cert_count; i++) {
        print cert_lines[i]
      }
      next
    }
    in_cert && /^[ ]+-----END CERTIFICATE-----/ {
      in_cert=0; next
    }
    in_cert {next}
    {print}
  ' "$CIRCLECI_YAML_FILE" >"${CIRCLECI_YAML_FILE}.tmp" && mv "${CIRCLECI_YAML_FILE}.tmp" "$CIRCLECI_YAML_FILE"

	echo "Certificate updated in $CIRCLECI_YAML_FILE"
}

function set_conjur_url_in_circleci_yaml_config(){
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
}

function set_secrets_in_circleci_yaml_config(){
	local secrets="${1}"
	awk -v secrets_var="$secrets" '{gsub(/secrets: ".*"/, "secrets: \"" secrets_var "\""); print}' "$CIRCLECI_YAML_FILE" > "${CIRCLECI_YAML_FILE}.tmp" && mv "${CIRCLECI_YAML_FILE}.tmp" "$CIRCLECI_YAML_FILE"
}