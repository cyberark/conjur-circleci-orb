#!/bin/bash -e

MODE="${1}"

#generate dist directory locally.
dist_dir="./dist"
mkdir "$dist_dir"

orb_version_dir="./orbversion"
mkdir "$orb_version_dir"

docker compose -f docker-compose.circleci.yml build
docker compose -f docker-compose.circleci.yml run \
  circleci bash -c "set -o pipefail;
           bash -x ./bin/generate_artifact.sh $MODE"
