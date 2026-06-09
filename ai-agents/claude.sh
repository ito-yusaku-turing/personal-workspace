#!/bin/bash

if [[ -f "$HOME/.local/bin/claude" ]]; then
  export PATH="$HOME"/.local/bin:$PATH

  if [[ "$HOME" == "/usr/home" ]]; then
    echo -e "\033[31;1;5m -------------------- BRAVE MODE ------------------- \033[0m"
    echo "Claude-Code(native) brave mode"
    "$HOME"/.local/bin/claude --dangerously-skip-permissions "$@"
  else
    echo "Claude-Code(native) safety mode"
    "$HOME"/.local/bin/claude "$@"
  fi
  exit
else
  echo "How to install claude code native:"
  echo "curl -fsSL https://claude.ai/install.sh | bash"
  exit
fi
