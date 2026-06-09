#!/bin/bash
DIR=$(realpath "$(dirname "$(readlink -f "$0" || echo "$0")")/../")
cd "$DIR" || exit
. "$DIR"/lib/common.sh
cd ../
docker_compose run --rm ai-agents-gdc
