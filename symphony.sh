#!/bin/bash

set -e

LINEAR_API_KEY="${LINEAR_API_KEY}"
SYMPHONY_DIR="$HOME/.symphony"
WORKFLOWS_DIR="$SYMPHONY_DIR/workflows"
CONFIG_FILE="$SYMPHONY_DIR/projects.conf"
SYMPHONY_BIN="${SYMPHONY_BIN:-$HOME/symphony/elixir}"

mkdir -p "$WORKFLOWS_DIR"

if [ -z "$LINEAR_API_KEY" ]; then
  echo "Error: LINEAR_API_KEY not set"
  echo "Run: export LINEAR_API_KEY=your_key_here"
  exit 1
fi

generate_workflow() {
  local name="$1"
  local slug="$2"
  local repo="$3"
  local workflow_file="$WORKFLOWS_DIR/WORKFLOW_${name}.md"

  cat > "$workflow_file" <<EOF
---
tracker:
  kind: linear
  project_slug: "${slug}"
workspace:
  root: ~/code/symphony-workspaces/${name}
hooks:
  after_create: |
    git clone --depth 1 ${repo} .
agent:
  max_concurrent_agents: 5
  max_turns: 20
codex:
  command: codex app-server
---

You are working on a Linear issue {{ issue.identifier }}.

Title: {{ issue.title }}
Body: {{ issue.description }}
EOF

  echo "$workflow_file"
}

add_project() {
  local name="$1"
  local slug="$2"
  local repo="$3"

  if [ -z "$name" ] || [ -z "$slug" ] || [ -z "$repo" ]; then
    echo "Usage: symphony add <name> <project-slug> <git-repo-url>"
    echo "Example: symphony add rizz-ai symphony-6d2ee11f7e5e git@github.com:philipdaquin/rizz-ai.git"
    exit 1
  fi

  local workflow_file
  workflow_file=$(generate_workflow "$name" "$slug" "$repo")

  touch "$CONFIG_FILE"

  if grep -q "^${name}|" "$CONFIG_FILE"; then
    grep -v "^${name}|" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "Updated project: $name"
  else
    echo "Added project: $name"
  fi

  echo "${name}|${slug}|${repo}|${workflow_file}" >> "$CONFIG_FILE"
  echo "Workflow created: $workflow_file"
}

start_project() {
  local name="$1"

  if [ -z "$name" ]; then
    echo "Usage: symphony start <name>"
    echo "Example: symphony start rizz-ai"
    exit 1
  fi

  local project_line
  project_line=$(grep "^${name}|" "$CONFIG_FILE" 2>/dev/null)

  if [ -z "$project_line" ]; then
    echo "Error: project '$name' not found"
    echo "Run 'symphony list' to see configured projects"
    exit 1
  fi

  local workflow_file
  workflow_file=$(echo "$project_line" | cut -d'|' -f4)

  if [ ! -f "$workflow_file" ]; then
    echo "Error: workflow file not found: $workflow_file"
    echo "Try running 'symphony add' again to regenerate it"
    exit 1
  fi

  echo "Starting Symphony for: $name"
  echo "Workflow: $workflow_file"
  echo ""

  cd "$SYMPHONY_BIN"
  mise exec -- ./bin/symphony "$workflow_file" --i-understand-that-this-will-be-running-without-the-usual-guardrails
}

list_projects() {
  if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
    echo "No projects configured. Use 'symphony add' to add one."
    exit 0
  fi

  echo "Configured projects:"
  echo ""
  while IFS='|' read -r name slug repo workflow_file; do
    echo "  $name"
    echo "    slug:     $slug"
    echo "    repo:     $repo"
    echo "    workflow: $workflow_file"
    echo ""
  done < "$CONFIG_FILE"
}

case "${1:-}" in
  add)
    add_project "$2" "$3" "$4"
    ;;
  start)
    start_project "$2"
    ;;
  list)
    list_projects
    ;;
  *)
    echo "Symphony CLI"
    echo ""
    echo "Commands:"
    echo "  symphony add <name> <project-slug> <git-repo-url>   Add a project"
    echo "  symphony start <name>                                Start Symphony for a project"
    echo "  symphony list                                        List configured projects"
    echo ""
    echo "Examples:"
    echo "  symphony add rizz-ai symphony-6d2ee11f7e5e git@github.com:philipdaquin/rizz-ai.git"
    echo "  symphony start rizz-ai"
    ;;
esac
