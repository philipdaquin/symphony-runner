#!/bin/bash

set -e

SYMPHONY_DIR="$HOME/.symphony"
WORKFLOWS_DIR="$SYMPHONY_DIR/workflows"
CONFIG_FILE="$SYMPHONY_DIR/projects.conf"
SYMPHONY_BIN="${SYMPHONY_BIN:-$HOME/symphony/elixir}"
BASE_WORKFLOW="$SYMPHONY_BIN/WORKFLOW.md"

mkdir -p "$WORKFLOWS_DIR"
touch "$CONFIG_FILE"

if [ -z "$LINEAR_API_KEY" ]; then
  echo "Error: LINEAR_API_KEY not set"
  echo "Run: export LINEAR_API_KEY=your_key_here"
  exit 1
fi

cmd_add() {
  local name="$1"
  local slug="$2"
  local repo="$3"

  if [ -z "$name" ] || [ -z "$slug" ] || [ -z "$repo" ]; then
    echo "Usage: symphony add <name> <project-slug> <git-repo-url>"
    echo "Example: symphony add rizz-ai symphony-6d2ee11f7e5e git@github.com:philipdaquin/rizz-ai.git"
    exit 1
  fi

  if [ ! -f "$BASE_WORKFLOW" ]; then
    echo "Error: base WORKFLOW.md not found at $BASE_WORKFLOW"
    exit 1
  fi

  local workflow_file="$WORKFLOWS_DIR/WORKFLOW_${name}.md"

  cp "$BASE_WORKFLOW" "$workflow_file"

  sed -i '' "s|project_slug:.*|project_slug: \"${slug}\"|" "$workflow_file"
  sed -i '' "s|git clone.*|git clone --depth 1 ${repo} .|" "$workflow_file"
  sed -i '' "s|root:.*workspaces.*|root: ~/code/symphony-workspaces/${name}|" "$workflow_file"

  grep -v "^${name}|" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  echo "${name}|${slug}|${repo}|${workflow_file}" >> "$CONFIG_FILE"

  echo "Added project: $name"
  echo "Workflow: $workflow_file"
}

cmd_start() {
  local name="$1"

  if [ -z "$name" ]; then
    echo "Usage: symphony start <name>"
    exit 1
  fi

  local project_line
  project_line=$(grep "^${name}|" "$CONFIG_FILE" 2>/dev/null || true)

  if [ -z "$project_line" ]; then
    echo "Error: project '$name' not found"
    echo "Run 'symphony list' to see configured projects"
    exit 1
  fi

  local workflow_file="${WORKFLOWS_DIR}/WORKFLOW_${name}.md"

  if [ ! -f "$workflow_file" ]; then
    echo "Error: workflow file not found: $workflow_file"
    echo "Try running 'symphony add' again"
    exit 1
  fi

  echo "Starting Symphony for: $name"
  echo "Workflow: $workflow_file"
  echo ""

  cd "$SYMPHONY_BIN"
  mise exec -- ./bin/symphony "$workflow_file" --i-understand-that-this-will-be-running-without-the-usual-guardrails
}

cmd_list() {
  if [ ! -s "$CONFIG_FILE" ]; then
    echo "No projects configured. Use 'symphony add' to add one."
    exit 0
  fi

  echo "Configured projects:"
  echo ""
  while IFS='|' read -r name slug repo workflow_file; do
    echo "  $name"
    echo "    slug: $slug"
    echo "    repo: $repo"
    echo ""
  done < "$CONFIG_FILE"
}

case "${1:-}" in
  add)   cmd_add "$2" "$3" "$4" ;;
  start) cmd_start "$2" ;;
  list)  cmd_list ;;
  *)
    echo "Symphony CLI"
    echo ""
    echo "Commands:"
    echo "  symphony add <name> <project-slug> <git-repo-url>"
    echo "  symphony start <name>"
    echo "  symphony list"
    echo ""
    echo "Examples:"
    echo "  symphony add rizz-ai symphony-6d2ee11f7e5e git@github.com:philipdaquin/rizz-ai.git"
    echo "  symphony start rizz-ai"
    ;;
esac
