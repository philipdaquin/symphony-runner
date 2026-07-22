#!/bin/bash
set -e

VERSION="1.1.0"
DEFAULT_ORIGINAL_BIN="/Users/philipdaquin/Documents/symphony/symphony/elixir"
ORIGINAL_BIN="${SYMPHONY_ORIGINAL_BIN:-$DEFAULT_ORIGINAL_BIN}"

SYMPHONY_DIR="${SYMPHONY_OPENAI_DIR:-$HOME/.symphony-openai}"
WORKFLOWS_DIR="$SYMPHONY_DIR/workflows"
CONFIG_FILE="$SYMPHONY_DIR/projects.conf"
WORKSPACE_ROOT="${SYMPHONY_OPENAI_WORKSPACE_ROOT:-$HOME/code/symphony-openai-workspaces}"
BASE_WORKFLOW="$ORIGINAL_BIN/WORKFLOW.md"

usage() {
  cat <<'EOF'
Usage:
  symphony-openai add <name> <project-slug> <git-repo-url> [--model <name>] [--reasoning-effort <effort>]
  symphony-openai edit <name> --slug <project-slug>
  symphony-openai start <name> [--model <name>] [--reasoning-effort <effort>]
  symphony-openai list
  symphony-openai build
  symphony-openai install
  symphony-openai version

This CLI runs the original OpenAI Symphony checkout with Codex only.

Environment:
  SYMPHONY_ORIGINAL_BIN       Upstream Symphony elixir directory
  SYMPHONY_OPENAI_DIR         State directory (default: ~/.symphony-openai)
  SYMPHONY_OPENAI_WORKSPACE_ROOT
                              Workspace root (default: ~/code/symphony-openai-workspaces)

Examples:
  symphony-openai add kozu kozu-ai-assisted-canvas-40caa03f7837 git@github.com:org/kozu.git --model gpt-5.4
  symphony-openai start kozu --model gpt-5.5 --reasoning-effort high
  symphony-openai edit kozu --slug another-linear-project-slug
EOF
}

ensure_state() {
  mkdir -p "$WORKFLOWS_DIR"
  touch "$CONFIG_FILE"
}

require_original_checkout() {
  if [ ! -d "$ORIGINAL_BIN" ]; then
    echo "Error: upstream Symphony checkout not found: $ORIGINAL_BIN" >&2
    echo "Set SYMPHONY_ORIGINAL_BIN to the upstream elixir directory." >&2
    exit 1
  fi
}

ensure_base_workflow() {
  require_original_checkout
  if [ ! -f "$BASE_WORKFLOW" ]; then
    echo "Error: upstream WORKFLOW.md not found at $BASE_WORKFLOW" >&2
    exit 1
  fi
}

ensure_symphony_built() {
  local bin_path="$ORIGINAL_BIN/bin/symphony"
  ensure_base_workflow

  if [ ! -x "$bin_path" ] || [ "$ORIGINAL_BIN/mix.exs" -nt "$bin_path" ]; then
    echo "Building upstream Symphony escript..."
    (cd "$ORIGINAL_BIN" && mise exec -- mix escript.build)
    return
  fi

  local newer_source
  newer_source=$(find "$ORIGINAL_BIN/lib" -type f \( -name "*.ex" -o -name "*.exs" \) -newer "$bin_path" -print -quit 2>/dev/null || true)
  if [ -n "$newer_source" ]; then
    echo "Rebuilding upstream Symphony escript because source changed..."
    (cd "$ORIGINAL_BIN" && mise exec -- mix escript.build)
  fi
}

shell_quote() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\"\'\"\'}"
}

build_codex_command() {
  local model="$1"
  local reasoning_effort="$2"
  local command="codex --config shell_environment_policy.inherit=all"

  if [ -n "$model" ]; then
    command+=" --config $(shell_quote "model=\"$model\"")"
  fi
  if [ -n "$reasoning_effort" ]; then
    command+=" --config $(shell_quote "model_reasoning_effort=\"$reasoning_effort\"")"
  fi
  command+=" app-server"
  printf '%s' "$command"
}

patch_codex_command() {
  local workflow_file="$1"
  local model="$2"
  local reasoning_effort="$3"

  if [ -z "$model" ] && [ -z "$reasoning_effort" ]; then
    return 0
  fi

  local command
  command=$(build_codex_command "$model" "$reasoning_effort")
  awk -v command="$command" '
    /^codex:/ { print; in_codex=1; next }
    in_codex && /^[^ ]/ { in_codex=0 }
    in_codex && /^  command:/ { print "  command: " command; next }
    { print }
  ' "$workflow_file" > "${workflow_file}.tmp" && mv "${workflow_file}.tmp" "$workflow_file"
}

write_workflow() {
  local name="$1"
  local slug="$2"
  local repo="$3"
  local model="$4"
  local reasoning_effort="$5"
  local workflow_file="$WORKFLOWS_DIR/WORKFLOW_${name}.md"

  ensure_base_workflow
  cp "$BASE_WORKFLOW" "$workflow_file"
  sed -i '' "s|project_slug:.*|project_slug: \"${slug}\"|" "$workflow_file"
  sed -i '' "s|git clone.*|git clone --depth 1 ${repo} .|" "$workflow_file"
  sed -i '' "s|root:.*workspaces.*|root: ${WORKSPACE_ROOT}/${name}|" "$workflow_file"
  patch_codex_command "$workflow_file" "$model" "$reasoning_effort"
  printf '%s' "$workflow_file"
}

project_line() {
  grep "^$1|" "$CONFIG_FILE" 2>/dev/null || true
}

cmd_add() {
  ensure_state
  local name="" slug="" repo="" model="" reasoning_effort=""
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --model) model="${2:-}"; shift 2 ;;
      --reasoning-effort) reasoning_effort="${2:-}"; shift 2 ;;
      *) positional+=("$1"); shift ;;
    esac
  done

  name="${positional[0]:-}"
  slug="${positional[1]:-}"
  repo="${positional[2]:-}"
  if [ -z "$name" ] || [ -z "$slug" ] || [ -z "$repo" ]; then
    usage
    exit 1
  fi

  local workflow_file
  workflow_file=$(write_workflow "$name" "$slug" "$repo" "$model" "$reasoning_effort")
  grep -v "^${name}|" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" || true
  mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  echo "${name}|${slug}|${repo}|${model}|${reasoning_effort}" >> "$CONFIG_FILE"
  echo "Added project: $name"
  echo "Workflow: $workflow_file"
}

cmd_edit() {
  ensure_state
  local name="" new_slug=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --slug|--project-slug) new_slug="${2:-}"; shift 2 ;;
      *) [ -z "$name" ] && name="$1"; shift ;;
    esac
  done
  if [ -z "$name" ] || [ -z "$new_slug" ]; then
    echo "Usage: symphony-openai edit <name> --slug <project-slug>"
    exit 1
  fi

  local line
  line=$(project_line "$name")
  if [ -z "$line" ]; then
    echo "Error: project '$name' not found" >&2
    exit 1
  fi

  local saved_name saved_slug saved_repo saved_model saved_reasoning_effort
  IFS='|' read -r saved_name saved_slug saved_repo saved_model saved_reasoning_effort <<< "$line"
  local workflow_file
  workflow_file=$(write_workflow "$saved_name" "$new_slug" "$saved_repo" "$saved_model" "$saved_reasoning_effort")
  grep -v "^${name}|" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" || true
  mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  echo "${saved_name}|${new_slug}|${saved_repo}|${saved_model}|${saved_reasoning_effort}" >> "$CONFIG_FILE"
  echo "Updated project: $name"
  echo "Linear slug: $new_slug"
  echo "Workflow: $workflow_file"
}

cmd_start() {
  ensure_state
  local name="" model="" reasoning_effort="" model_set=false effort_set=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --model) model="${2:-}"; model_set=true; shift 2 ;;
      --reasoning-effort) reasoning_effort="${2:-}"; effort_set=true; shift 2 ;;
      *) [ -z "$name" ] && name="$1"; shift ;;
    esac
  done
  if [ -z "$name" ]; then
    echo "Usage: symphony-openai start <name> [--model <name>] [--reasoning-effort <effort>]"
    exit 1
  fi

  local line
  line=$(project_line "$name")
  if [ -z "$line" ]; then
    echo "Error: project '$name' not found" >&2
    exit 1
  fi

  local saved_name saved_slug saved_repo saved_model saved_reasoning_effort
  IFS='|' read -r saved_name saved_slug saved_repo saved_model saved_reasoning_effort <<< "$line"
  [ "$model_set" = false ] && model="$saved_model"
  [ "$effort_set" = false ] && reasoning_effort="$saved_reasoning_effort"

  local workflow_file
  workflow_file=$(write_workflow "$saved_name" "$saved_slug" "$saved_repo" "$model" "$reasoning_effort")
  grep -v "^${name}|" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" || true
  mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  echo "${saved_name}|${saved_slug}|${saved_repo}|${model}|${reasoning_effort}" >> "$CONFIG_FILE"

  echo "Agent runtime: codex${model:+ · $model}"
  echo "Starting upstream Symphony for: $name"
  echo "Workflow: $workflow_file"
  ensure_symphony_built
  (cd "$ORIGINAL_BIN" && mise exec -- ./bin/symphony --logs-root "$SYMPHONY_DIR" "$workflow_file" --i-understand-that-this-will-be-running-without-the-usual-guardrails)
}

cmd_list() {
  ensure_state
  if [ ! -s "$CONFIG_FILE" ]; then
    echo "No projects configured. Use 'symphony-openai add' to add one."
    return
  fi
  echo "Configured upstream Symphony projects:"
  echo ""
  while IFS='|' read -r name slug repo model reasoning_effort; do
    echo "  $name"
    echo "    slug:   $slug"
    echo "    repo:   $repo"
    [ -n "$model" ] && echo "    model:  $model"
    [ -n "$reasoning_effort" ] && echo "    effort: $reasoning_effort"
    echo ""
  done < "$CONFIG_FILE"
}

cmd_install() {
  local install_dir="$HOME/.local/bin"
  mkdir -p "$install_dir"
  cp "$0" "$install_dir/symphony-openai"
  chmod +x "$install_dir/symphony-openai"
  echo "Installed upstream-only CLI to: $install_dir/symphony-openai"
}

cmd_version() {
  echo "Symphony OpenAI CLI v$VERSION"
  echo "Upstream checkout: $ORIGINAL_BIN"
}

case "${1:-}" in
  add) cmd_add "${@:2}" ;;
  edit) cmd_edit "${@:2}" ;;
  start) cmd_start "${@:2}" ;;
  list) [ "$#" -eq 1 ] || { usage; exit 1; }; cmd_list ;;
  build) [ "$#" -eq 1 ] || { usage; exit 1; }; ensure_symphony_built ;;
  install) [ "$#" -eq 1 ] || { usage; exit 1; }; cmd_install ;;
  version|--version) [ "$#" -eq 1 ] || { usage; exit 1; }; cmd_version ;;
  help|--help) usage ;;
  *) usage; exit 1 ;;
esac
