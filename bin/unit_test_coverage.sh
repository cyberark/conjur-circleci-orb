#!/usr/bin/env bash

# Runs unit tests in a Docker container and generates code coverage for the src/scripts/retrieve_secret.sh script
set -euo pipefail

OUTPUT_DIR="./output"

mkdir -p "$OUTPUT_DIR"

docker build -f Dockerfile.test -t unit-test .

docker run --rm \
  -v "$OUTPUT_DIR:/conjur-circleci-orb/coverage" \
  unit-test \
  bash -c "\
    bashcov --root . -- test/unit/retrieve_secret_unit_test.sh && \
    ruby -r '/conjur-circleci-orb/test/test_helper.rb' && \
    ./bin/generate_junit_report.sh > /conjur-circleci-orb/coverage/junit.xml"
