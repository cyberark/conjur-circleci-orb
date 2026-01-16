#!/usr/bin/env bash
set -eu

MODE="${1:-private}" # public or private
ORB_NAME="${2:-conjur-circleci-orb}"  # can also be set as a custom name

function setModeConfig() {
    case "$MODE" in
        "private")
            NAMESPACE="$CIRCLECI_NAMESPACE_PRIVATE"
            VERSION_PREFIX="dev:"
            FLAG="--private"
            ;;
        "public")
            NAMESPACE="$CIRCLECI_NAMESPACE" 
            VERSION_PREFIX=""
            FLAG=""
            ;;
        *)
            echo "Error: Invalid mode '$MODE'"
            echo "Valid modes: private, public"
            exit 1
            ;;
    esac
}

function checkEnvVars() {
  if [[ -z "$1" ]]; then
    echo "Environment variable is not set"
    exit 1
  fi
}

function verifyNamespaceExistence() {
  circleci orb list "$NAMESPACE" $FLAG 
  if [[ $? -ne 0 ]]; then
    echo "No namespace '$NAMESPACE' was found in the CircleCI Orbs repository"
    exit 1
  fi
}

function verifyOrbExistence() {
  circleci orb list "$NAMESPACE" $FLAG | grep "$ORB_NAME"
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
  echo "Publishing $MODE orb: ${NAMESPACE}/${ORB_NAME}@${VERSION_PREFIX}${VERSION}"
  circleci orb publish "${ASSET_DIRECTORY}/orb.yml" "${NAMESPACE}/${ORB_NAME}@${VERSION_PREFIX}${VERSION}"
  if [[ $? -ne 0 ]]; then
    echo "Failed to publish orb, please check out error log"
    exit 1
  fi
}

function promotingOrb() {
  echo "Promoting $MODE orb: ${NAMESPACE}/${ORB_NAME}@${VERSION_PREFIX}${VERSION}"
  
  PROMOTE_OUTPUT=$(circleci orb publish promote "${NAMESPACE}/${ORB_NAME}@${VERSION_PREFIX}${VERSION}" patch 2>&1)
  
  if [[ $? -ne 0 ]]; then
    echo "Failed to promote orb, please check out error log"
    echo "$PROMOTE_OUTPUT"
    exit 1
  fi
  
  echo "$PROMOTE_OUTPUT"
  
  PROMOTED_ORB=$(echo "$PROMOTE_OUTPUT" | sed -n "s/.*was promoted to \`\\([^\`]*\\)\`.*/\\1/p")
  
  if [[ -n "$PROMOTED_ORB" ]]; then
    echo "Successfully promoted to: $PROMOTED_ORB"
    echo "Saving orb name to file orbversion/.published_orb_version"
    echo "$PROMOTED_ORB" > ./orbversion/.published_orb_version
  else
    echo "Warning: Could not extract promoted orb name from output"
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
  # Set configuration based on mode first
  setModeConfig  
  checkEnvVars "$CIRCLECI_API_KEY"
  checkEnvVars "$CIRCLECI_ORG_ID"
  checkEnvVars "$CIRCLECI_NAMESPACE"
  checkEnvVars "$CIRCLECI_NAMESPACE_PRIVATE"
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
  
  # Private orbs: promote dev version to numbered version (dev:3->0.0.1, dev:4->0.0.2)
  if [[ "$MODE" == "private" ]]; then
    echo "Promoting private dev version to numbered version..."
    promotingOrb
  fi
}

main