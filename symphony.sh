#!/bin/bash
echo "Running Symphony CLI helper script v1.1.0..."
set -e

SYMPHONY_DIR="$HOME/.symphony"
WORKFLOWS_DIR="$SYMPHONY_DIR/workflows"
CONFIG_FILE="$SYMPHONY_DIR/projects.conf"
SYMPHONY_BIN="${SYMPHONY_BIN:-$HOME/symphony/elixir}"
BASE_WORKFLOW="$SYMPHONY_BIN/WORKFLOW.md"

mkdir -p "$WORKFLOWS_DIR"
touch "$CONFIG_FILE"

ensure_symphony_built() {
  local bin_path="$SYMPHONY_BIN/bin/symphony"

  if [ ! -x "$bin_path" ] || [ "$SYMPHONY_BIN/mix.exs" -nt "$bin_path" ]; then
    echo "Building Symphony escript..."
    (cd "$SYMPHONY_BIN" && mise exec -- mix escript.build)
    return
  fi

  local newer_source
  newer_source=$(find "$SYMPHONY_BIN/lib" -type f \( -name "*.ex" -o -name "*.exs" \) -newer "$bin_path" -print -quit 2>/dev/null || true)

  if [ -n "$newer_source" ]; then
    echo "Rebuilding Symphony escript because source changed..."
    (cd "$SYMPHONY_BIN" && mise exec -- mix escript.build)
  fi
}

if [ -z "$LINEAR_API_KEY" ]; then
  echo "Error: LINEAR_API_KEY not set"
  echo "Run: export LINEAR_API_KEY=your_key_here"
  exit 1
fi

# ---------------------------------------------------------------------------
# Patch agent block in workflow file
# ---------------------------------------------------------------------------
patch_agent() {
  local workflow_file="$1"
  local adapter="$2"  # "claude" or "codex"

  awk -v adapter="$adapter" '
    /^agent:/ {
      print "agent:"
      print "  adapter: " adapter
      print "  max_concurrent_agents: 10"
      print "  max_turns: 20"
      in_agent=1
      next
    }
    in_agent && /^[^ ]/ { in_agent=0 }
    in_agent { next }
    { print }
  ' "$workflow_file" > "${workflow_file}.tmp" && mv "${workflow_file}.tmp" "$workflow_file"
}

# ---------------------------------------------------------------------------
# Export MiniMax env vars for Claude adapter
# ---------------------------------------------------------------------------
export_minimax_env() {
  if [ -z "$MINIMAX_API_KEY" ]; then
    echo "Error: MINIMAX_API_KEY not set"
    echo "Run: export MINIMAX_API_KEY=your_key_here"
    exit 1
  fi

  export ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic"
  export ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY"
  export API_TIMEOUT_MS="3000000"
  export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
  export ANTHROPIC_MODEL="MiniMax-M2.7"
  export ANTHROPIC_SMALL_FAST_MODEL="MiniMax-M2.7"
  export ANTHROPIC_DEFAULT_SONNET_MODEL="MiniMax-M2.7"
  export ANTHROPIC_DEFAULT_OPUS_MODEL="MiniMax-M2.7"
  export ANTHROPIC_DEFAULT_HAIKU_MODEL="MiniMax-M2.7"

  echo "MiniMax env vars set."
}

# ---------------------------------------------------------------------------
# add
# ---------------------------------------------------------------------------
cmd_add() {
  local name="" slug="" repo="" adapter="codex" use_minimax=false

  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --claude)   adapter="claude"; shift ;;
      --codex)    adapter="codex"; shift ;;
      --minimax)  adapter="claude"; use_minimax=true; shift ;;
      *) positional+=("$1"); shift ;;
    esac
  done

  name="${positional[0]:-}"
  slug="${positional[1]:-}"
  repo="${positional[2]:-}"

  if [ -z "$name" ] || [ -z "$slug" ] || [ -z "$repo" ]; then
    echo "Usage: symphony add <n> <project-slug> <git-repo-url> [--codex|--claude|--minimax]"
    echo ""
    echo "Examples:"
    echo "  symphony add rizz-ai slug-abc git@github.com:org/rizz-ai.git"
    echo "  symphony add rizz-ai slug-abc git@github.com:org/rizz-ai.git --claude"
    echo "  symphony add rizz-ai slug-abc git@github.com:org/rizz-ai.git --minimax"
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

  patch_agent "$workflow_file" "$adapter"

  echo "Adapter: $adapter"
  [ "$use_minimax" = true ] && echo "Provider: MiniMax M2.7 (via Claude adapter)"

  grep -v "^${name}|" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  echo "${name}|${slug}|${repo}|${adapter}|${use_minimax}" >> "$CONFIG_FILE"

  echo "Added project: $name"
  echo "Workflow: $workflow_file"
}

# ---------------------------------------------------------------------------
# start
# ---------------------------------------------------------------------------
cmd_start() {
  local name="" adapter="" use_minimax=false flag_set=false

  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --claude)   adapter="claude"; flag_set=true; shift ;;
      --codex)    adapter="codex";  flag_set=true; shift ;;
      --minimax)  adapter="claude"; use_minimax=true; flag_set=true; shift ;;
      *) positional+=("$1"); shift ;;
    esac
  done

  name="${positional[0]:-}"

  if [ -z "$name" ]; then
    echo "Usage: symphony start <n> [--codex|--claude|--minimax]"
    exit 1
  fi

  local project_line
  project_line=$(grep "^${name}|" "$CONFIG_FILE" 2>/dev/null || true)

  if [ -z "$project_line" ]; then
    echo "Error: project '$name' not found"
    echo "Run 'symphony list' to see configured projects"
    exit 1
  fi

  local workflow_file="$WORKFLOWS_DIR/WORKFLOW_${name}.md"

  if [ ! -f "$workflow_file" ]; then
    echo "Error: workflow file not found: $workflow_file"
    echo "Try running 'symphony add' again"
    exit 1
  fi

  # Fall back to saved preference if no flag passed
  if [ "$flag_set" = false ]; then
    adapter=$(echo "$project_line" | cut -d'|' -f4)
    local saved_minimax
    saved_minimax=$(echo "$project_line" | cut -d'|' -f5)
    [ "$saved_minimax" = "true" ] && use_minimax=true
  fi

  patch_agent "$workflow_file" "$adapter"

  if [ "$use_minimax" = true ]; then
    export_minimax_env
  fi

  echo "Adapter: $adapter"
  [ "$use_minimax" = true ] && echo "Provider: MiniMax M2.7"
  echo "Starting Symphony for: $name"
  echo "Workflow: $workflow_file"
  echo ""

  ensure_symphony_built

  cd "$SYMPHONY_BIN"
  mise exec -- ./bin/symphony --logs-root "$SYMPHONY_DIR" "$workflow_file" --i-understand-that-this-will-be-running-without-the-usual-guardrails
}

# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------
cmd_list() {
  if [ ! -s "$CONFIG_FILE" ]; then
    echo "No projects configured. Use 'symphony add' to add one."
    exit 0
  fi

  echo "Configured projects:"
  echo ""
  while IFS='|' read -r name slug repo adapter use_minimax; do
    local agent_info="$adapter"
    [ "$use_minimax" = "true" ] && agent_info="$adapter (MiniMax M2.7)"
    echo "  $name"
    echo "    slug:    $slug"
    echo "    repo:    $repo"
    echo "    adapter: $agent_info"
    echo ""
  done < "$CONFIG_FILE"
}

# ---------------------------------------------------------------------------
# update
# ---------------------------------------------------------------------------
cmd_update() {
  local installed_path=""

  if [ -f "$HOME/bin/symphony" ] && [ -x "$HOME/bin/symphony" ]; then
    installed_path="$HOME/bin/symphony"
  elif [ -f "$HOME/.local/bin/symphony" ] && [ -x "$HOME/.local/bin/symphony" ]; then
    installed_path="$HOME/.local/bin/symphony"
  elif command -v symphony >/dev/null 2>&1; then
    installed_path=$(command -v symphony)
  fi

  if [ -z "$installed_path" ]; then
    echo "Symphony is not installed in your bin."
    echo "Run 'symphony install' to install it, or manually copy symphony.sh to your bin."
    exit 1
  fi

  local current_script
  current_script=$(readlink -f "$0" 2>/dev/null || echo "$0")
  current_script=$(realpath "$current_script" 2>/dev/null || echo "$current_script")

  local installed_real
  installed_real=$(readlink -f "$installed_path" 2>/dev/null || echo "$installed_path")
  installed_real=$(realpath "$installed_real" 2>/dev/null || echo "$installed_real")

  if [ "$current_script" = "$installed_real" ]; then
    echo "Symphony is already up to date (installed at $installed_path)"
    return 0
  fi

  echo "Updating Symphony from $current_script to $installed_path..."
  cp "$current_script" "$installed_path"
  chmod +x "$installed_path"
  echo "Symphony updated successfully."
}

# ---------------------------------------------------------------------------
# install
# ---------------------------------------------------------------------------
cmd_install() {
  local install_dir=""
  local target_path=""

  if [ -d "$HOME/bin" ] && [ -w "$HOME/bin" ]; then
    install_dir="$HOME/bin"
  elif [ -d "$HOME/.local/bin" ] && [ -w "$HOME/.local/bin" ]; then
    install_dir="$HOME/.local/bin"
  else
    install_dir="$HOME/bin"
    mkdir -p "$install_dir"
  fi

  target_path="$install_dir/symphony"

  local current_script
  current_script=$(readlink -f "$0" 2>/dev/null || echo "$0")
  current_script=$(realpath "$current_script" 2>/dev/null || echo "$current_script")

  echo "Installing Symphony to $target_path..."
  cp "$current_script" "$target_path"
  chmod +x "$target_path"
  echo "Symphony installed successfully."
  echo "Add $install_dir to your PATH if needed."
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "${1:-}" in
  add)    cmd_add "${@:2}" ;;
  start)  cmd_start "${@:2}" ;;
  list)   cmd_list ;;
  update) cmd_update ;;
  install) cmd_install ;;
  *)
    echo "Symphony CLI"
    echo ""
    echo "Commands:"
    echo "  symphony add <n> <project-slug> <git-repo-url> [--codex|--claude|--minimax]"
    echo "  symphony start <n> [--codex|--claude|--minimax]"
    echo "  symphony list"
    echo "  symphony update    Update the installed symphony script"
    echo "  symphony install   Install symphony to your bin"
    echo ""
    echo "  --codex    Use Codex adapter (default)"
    echo "  --claude   Use Claude adapter"
    echo "  --minimax  Use Claude adapter routed through MiniMax M2.7"
    echo ""
    echo "Examples:"
    echo "  symphony add rizz-ai slug-abc git@github.com:org/rizz-ai.git"
    echo "  symphony add rizz-ai slug-abc git@github.com:org/rizz-ai.git --claude"
    echo "  symphony add rizz-ai slug-abc git@github.com:org/rizz-ai.git --minimax"
    echo "  symphony start rizz-ai"
    echo "  symphony start rizz-ai --minimax"
    echo "  symphony update"
    ;;
esac
