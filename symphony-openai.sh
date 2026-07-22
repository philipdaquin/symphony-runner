#!/bin/bash
set -e

VERSION="1.0.0"
DEFAULT_ORIGINAL_BIN="/Users/philipdaquin/Documents/symphony/symphony/elixir"
ORIGINAL_BIN="${SYMPHONY_ORIGINAL_BIN:-$DEFAULT_ORIGINAL_BIN}"

usage() {
  cat <<'EOF'
Usage:
  symphony-openai [WORKFLOW.md] [Symphony options]
  symphony-openai build
  symphony-openai install
  symphony-openai version

Environment:
  SYMPHONY_ORIGINAL_BIN  Path to the upstream Symphony elixir directory

Examples:
  symphony-openai
  symphony-openai /path/to/WORKFLOW.md --port 4000
  symphony-openai build
  SYMPHONY_ORIGINAL_BIN=/path/to/symphony/elixir symphony-openai
EOF
}

require_original_checkout() {
  if [ ! -d "$ORIGINAL_BIN" ]; then
    echo "Error: upstream Symphony checkout not found: $ORIGINAL_BIN" >&2
    echo "Set SYMPHONY_ORIGINAL_BIN to the upstream elixir directory." >&2
    exit 1
  fi
}

build_original() {
  require_original_checkout
  echo "Building upstream Symphony from: $ORIGINAL_BIN"
  (cd "$ORIGINAL_BIN" && mise exec -- mix build)
}

install_launcher() {
  local install_dir="$HOME/.local/bin"
  mkdir -p "$install_dir"
  cp "$0" "$install_dir/symphony-openai"
  chmod +x "$install_dir/symphony-openai"
  echo "Installed upstream launcher to: $install_dir/symphony-openai"
}

run_original() {
  require_original_checkout

  local workflow_path="$ORIGINAL_BIN/WORKFLOW.md"
  if [ "$#" -gt 0 ] && [[ "$1" != --* ]]; then
    workflow_path="$1"
    shift
  fi

  if [ ! -f "$workflow_path" ]; then
    echo "Error: workflow file not found: $workflow_path" >&2
    exit 1
  fi

  if [ ! -x "$ORIGINAL_BIN/bin/symphony" ]; then
    echo "Upstream Symphony binary is missing; building it first..."
    build_original
  fi

  echo "Running upstream Symphony from: $ORIGINAL_BIN"
  echo "Workflow: $workflow_path"
  (cd "$ORIGINAL_BIN" && mise exec -- ./bin/symphony "$workflow_path" "$@")
}

case "${1:-}" in
  build)
    [ "$#" -eq 1 ] || { usage; exit 1; }
    build_original
    ;;
  install)
    [ "$#" -eq 1 ] || { usage; exit 1; }
    install_launcher
    ;;
  version|--version)
    [ "$#" -eq 1 ] || { usage; exit 1; }
    echo "Symphony OpenAI launcher v$VERSION"
    echo "Upstream checkout: $ORIGINAL_BIN"
    ;;
  help|--help)
    usage
    ;;
  *)
    run_original "$@"
    ;;
esac
