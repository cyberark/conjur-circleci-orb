#!/bin/bash
set -euo pipefail

function load_jwt_policies() {
  echo "[INFO] Loading authenticator policy"
  conjur policy load -f /tmp/policies/authenticator.yml -b root

  echo "[INFO] Loading host policy"
  conjur policy load -f /tmp/policies/host.yml -b root

  echo "[INFO] Loading grant access policy"
  conjur policy load -f /tmp/policies/grant-access.yml -b root
}

function set_jwt_variables() {
  echo "[INFO] Setting JWT values to variables in Conjur"
  conjur variable set -i conjur/authn-jwt/circleci/jwks-uri -v "$JWKS_URI"
  conjur variable set -i conjur/authn-jwt/circleci/issuer -v "$ISSUER"
  conjur variable set -i conjur/authn-jwt/circleci/audience -v "$AUDIENCE"
  conjur variable set -i conjur/authn-jwt/circleci/token-app-property -v "$TOKEN_APP_PROPERTY"
  conjur variable set -i conjur/authn-jwt/circleci/identity-path -v "$IDENTITY_PATH"
  conjur variable set -i circleci/secretJwtVar -v 'HelloCircleCi'
}

main() {
  load_jwt_policies
  set_jwt_variables
}

main