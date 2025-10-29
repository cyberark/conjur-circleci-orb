#!/bin/bash
set -euo pipefail

function configure_conjur_cli() {
	local conjur_env="$1"
	echo "[INFO] Initializing Conjur CLI for environment: $conjur_env..."

	conjur init "$conjur_env" -u "$CONJUR_URL" --self-signed --account "$CONJUR_ACCOUNT"
	conjur login -i admin -p "$CONJUR_ADMIN_PASSWORD"
}

configure_conjur_cli "${1:-enterprise}"