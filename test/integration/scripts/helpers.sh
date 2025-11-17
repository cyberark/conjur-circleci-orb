#!/bin/bash
set -euo pipefail
# Common helper functions

CONJUR_LEADER_CONTAINER="conjur-leader-1.mycompany.local"
CONJUR_CLI_CONTAINER="conjur-cli"

function leaderExec() {
	docker exec "$CONJUR_LEADER_CONTAINER" "$@"
}

function cliExec() {
	docker exec "$CONJUR_CLI_CONTAINER" "$@"
}

function inject_conjur_cert_into_yaml() {
	local cert_file="conjur.pem"
	local yaml_file="test/integration/ci/config.yml"

	# Extract certificate from conjur-leader container
	leaderExec openssl s_client -connect localhost:443 -showcerts </dev/null 2>/dev/null |
		awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {print $0}' >"$cert_file"

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