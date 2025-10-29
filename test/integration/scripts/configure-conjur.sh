#!/bin/bash
set -euo pipefail

function configure() {
    evoke configure master \
    --hostname=conjur-leader-1.mycompany.local \
    --master-altnames="localhost,conjur-leader.mycompany.local,conjur-leader-1.mycompany.local" \
    --accept-eula \
    --admin-password="$CONJUR_ADMIN_PASSWORD" \
    "$CONJUR_ACCOUNT"
}

configure