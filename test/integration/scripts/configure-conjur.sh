#!/bin/bash
set -euo pipefail

# Configure Conjur master (sets up admin password, account, and initial settings)
function configure() {
	evoke configure master \
		--hostname=conjur-leader-1.mycompany.local \
		--master-altnames="localhost,conjur-leader.mycompany.local,conjur-leader-1.mycompany.local" \
		--accept-eula \
		--admin-password="$CONJUR_ADMIN_PASSWORD" \
		"$CONJUR_ACCOUNT"
}

# Allowlists the JWT authenticator by setting the CONJUR_AUTHENTICATORS variable.
function allowlist_authenticator() {
	echo "[INFO] Enable the JWT authenticator by allowlisting it in the CONJUR_AUTHENTICATORS environment variable"
	evoke variable set CONJUR_AUTHENTICATORS authn-jwt/circleci
}

main() {
	configure
	#allowlist_authenticator -> Handled as an environment variable in Docker Compose, but worth having as a separate function as well
}

main