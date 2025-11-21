#!/bin/bash
set -euo pipefail

function configure_conjur_cli() {
	local conjur_env="$1"

	echo "[INFO] Initializing Conjur CLI for environment: $conjur_env"

	case "$conjur_env" in
	"oss")
		conjur init "$conjur_env" -u "$CONJUR_OSS_URL" --self-signed --account "$CONJUR_ACCOUNT"
		conjur login -i admin -p "$(awk '/API key for admin/{print $NF}' data/oss_admin_data | tr -d '\r')"
		;;
	"enterprise")
	conjur init "$conjur_env" -u "$CONJUR_URL" --self-signed --account "$CONJUR_ACCOUNT"
	conjur login -i admin -p "$CONJUR_ADMIN_PASSWORD"
	;;
	esac
}

configure_conjur_cli "${1:-enterprise}"