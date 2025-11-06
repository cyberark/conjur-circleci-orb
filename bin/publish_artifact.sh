#!/usr/bin/env bash
set -eu

ORB_NAME="${1:-conjur-circleci-orb}"  # can also be set as a custom name

function checkEnvVars() {
  if [[ -z "$1" ]]; then
    echo "Environment variable is not set"
    exit 1
  fi
}

function verifyNamespaceExistence() {
  circleci orb list "$CIRCLECI_NAMESPACE"
  if [[ $? -ne 0 ]]; then
    echo "No namespace was found in the CircleCI Orbs repository"
    exit 1
  fi
}

function verifyOrbExistence() {
  circleci orb list "$CIRCLECI_NAMESPACE" | grep "$ORB_NAME"
  if [[ $? -ne 0 ]]; then
    echo "Unable to find orb"
    exit 1
  fi
}

function orbValidate() {
  circleci orb validate "${ASSET_DIRECTORY}/orb.yml"
  if [[ $? -ne 0 ]]; then
    echo "conjur-circleci-orb is not a valid orb"
    exit 1
  fi
}

function publishOrb() {
  circleci orb publish "${ASSET_DIRECTORY}/orb.yml" "${CIRCLECI_NAMESPACE}/${ORB_NAME}@${VERSION}"
  if [[ $? -ne 0 ]]; then
    echo "Failed to publish orb, please check out error log"
    exit 1
  fi
}

function setupCircleCI() {
  circleci setup --no-prompt \
  --host https://circleci.com \
  --token $CIRCLECI_API_KEY 

  if [[ $? -ne 0 ]]; then
    echo "Failed to setup CircleCI, Please verify your API Token"
    exit 1
  fi
}

function main() {
  checkEnvVars "$CIRCLECI_API_KEY"
  checkEnvVars "$CIRCLECI_ORG_ID"
  checkEnvVars "$CIRCLECI_NAMESPACE"
  checkEnvVars "$VERSION"
  checkEnvVars "$ASSET_DIRECTORY"
  setupCircleCI
  #Verify the namespace existence
  verifyNamespaceExistence
  #Validate and create the orb
  verifyOrbExistence
  #Verify we have a valid orb file
  orbValidate
  #Publish the orb
  publishOrb
}

main