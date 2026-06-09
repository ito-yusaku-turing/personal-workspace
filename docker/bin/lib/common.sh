APP_NAME=personal-workspace
USER_ID=$(id -u)
GROUP_ID=$(id -g)
USER_NAME=$(id -u -n)
GROUP_NAME=$(id -g -n)
COMPOSE_PROJECT_NAME=$APP_NAME-$(whoami)
export USER_ID
export GROUP_ID
export USER_NAME
export GROUP_NAME
export COMPOSE_PROJECT_NAME

CONFIG_PATH="../config.sh"

if [[ -f $CONFIG_PATH ]]; then
  if [[ "${SHOW_CONFIG}" == "1" ]]; then
    echo "---CONFIG---"
    cat $CONFIG_PATH
    echo "------------"
  fi
  # shellcheck source=../../config.sh
  . "${CONFIG_PATH}"
else
  if [[ "${SHOW_CONFIG}" == "1" ]]; then
    echo "Config file: not found."
  fi
fi

COMPOSE=$(command -v "docker-compose" 2>&1)
export COMPOSE

function docker_compose()
{
  if [[ -z "${COMPOSE}" ]];then
    docker compose "$@"
  else
    $COMPOSE "$@"
  fi
}

function up_service()
{
  SERVICE="$1"
  MODE="$2"
  case "$MODE" in
	"-d")
	  echo "Start with detach mode"
	  docker_compose up -d "$SERVICE"
	  ;;
	"-c")
	  echo "Start without detach mode"
	  docker_compose up "$SERVICE"
	  ;;
	*)
	  echo "Start without detach mode"
	  docker_compose up "$SERVICE"
	  ;;
  esac
}
