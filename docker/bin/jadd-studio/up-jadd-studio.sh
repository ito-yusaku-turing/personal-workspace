#!/bin/bash
DIR=$(realpath "$(dirname "$(readlink -f "$0" || echo "$0")")/../")
cd "$DIR" || exit
export SHOW_CONFIG=1
. "$DIR"/lib/common.sh
cd ../

up_service "jadd_studio3" "$1"
