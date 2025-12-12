#!/bin/bash

MODE="${1}" # public or private
ORB_NAME="${2:-conjur-circleci-orb}"  # can also be set as a custom name

function setModeConfig() {
    case "$MODE" in
        "private")
            NAMESPACE="$CIRCLECI_NAMESPACE_PRIVATE"
            FLAG="--private"
            ;;
        "public")
            NAMESPACE="$CIRCLECI_NAMESPACE" 
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
    [[ $? -ne 0 ]] && { echo "No namespace '$NAMESPACE' was found in the CircleCI Orbs repository" ; exit 1 ; }
}

function verifyOrbExistence() {
    circleci orb list "$NAMESPACE" $FLAG | grep "$ORB_NAME" 
    case $? in
        0) ;;
        *)
            setupCircleCI
            createOrb
        ;;
    esac
}

function setupCircleCI() {
    circleci setup --no-prompt \
    --host https://circleci.com \
    --token $CIRCLECI_API_KEY &>/dev/null
    [[ $? -ne 0 ]] && { echo "Failed to setup CircleCI, Please verify your API Token" ; exit 1 ; }

}

function createOrb() {
    circleci orb create "$NAMESPACE"/"$ORB_NAME"  --no-prompt "$FLAG"
    [[ $? -ne 0 ]] && { echo "Failed to create the CircleCI Orb" ; exit 1 ; }
}

function orbPack() {
    [[ -z "$(find src -mindepth 1 -maxdepth 1)" ]] && { echo "The conjur-circleci-orb source code does not exist" ; exit 1 ; }
    circleci orb pack ./src > ./orb.yml
    [[ ! -s "./orb.yml" ]] && { echo "Failed to create the CircleCI Orb" ; exit 1 ; }
}

function orbValidate() {
    circleci orb validate ./orb.yml &>/dev/null
    [[ $? -ne 0 ]] && { echo "conjur-circleci-orb is not a valid orb" ; exit 1 ; }
    cp -f ./orb.yml ./dist &>/dev/null
    sha256sum ./dist/orb.yml > ./dist/conjur-circleci-orb_SHA256SUMS
    echo "Successfully generated the conjur-circleci-orb"
}

function main() {
    checkEnvVars "$CIRCLECI_API_KEY"
    checkEnvVars "$CIRCLECI_ORG_ID"
    checkEnvVars "$CIRCLECI_NAMESPACE"
    checkEnvVars "$CIRCLECI_NAMESPACE_PRIVATE"
    setModeConfig
    
    # Setup CircleCI CLI first for private mode so we can access private orbs in account
    if [[ "$MODE" == "private" ]]; then
        echo "Setting up CircleCI CLI for private orb access"
        setupCircleCI
    fi
    
    #Verify the namespace existence
    verifyNamespaceExistence
    #Validate and create the orb
    verifyOrbExistence
    #Pack the orb
    orbPack
    #Validate the orb
    orbValidate
}

main
