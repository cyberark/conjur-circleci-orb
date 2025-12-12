#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 3 ]; then
	echo "Incorrect number of parameters."
	echo "Usage: promote.sh <asset directory> <version> <mode-public|private>"
	exit 1
fi

export ASSET_DIRECTORY=$1
export VERSION=$2
MODE=$3

docker compose -f docker-compose.circleci.yml build
docker compose -f docker-compose.circleci.yml run \
	-v "$(pwd):$(pwd)" \
	circleci bash -c "set -o pipefail;
           bash -x ./bin/publish_artifact.sh $MODE"
