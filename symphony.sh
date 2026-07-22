#!/bin/bash
set -e

VERSION="1.3.0"
REPO_URL="https://raw.githubusercontent.com/philipdaquin/symphony-runner/main/symphony.sh"

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
# Shell quoting helpers
# ---------------------------------------------------------------------------
shell_quote() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\"\'\"\'}"
}

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
# Patch codex command in workflow file
# ---------------------------------------------------------------------------
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
    /^codex:/ {
      print
      in_codex=1
      next
    }
    in_codex && /^[^ ]/ { in_codex=0 }
    in_codex && /^  command:/ {
      print "  command: " command
      next
    }
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
  local name="" slug="" repo="" adapter="codex" use_minimax=false model="" reasoning_effort=""

  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --claude)   adapter="claude"; shift ;;
      --codex)    adapter="codex"; shift ;;
      --minimax)  adapter="claude"; use_minimax=true; shift ;;
      --model)
        model="${2:-}"
        shift 2
        ;;
      --reasoning-effort)
        reasoning_effort="${2:-}"
        shift 2
        ;;
      *) positional+=("$1"); shift ;;
    esac
  done

  name="${positional[0]:-}"
  slug="${positional[1]:-}"
  repo="${positional[2]:-}"

  if [ -z "$model" ] && [ "$adapter" = "codex" ] && [ -n "${positional[3]:-}" ]; then
    model="${positional[3]}"
  fi

  if [ -z "$name" ] || [ -z "$slug" ] || [ -z "$repo" ]; then
    echo "Usage: symphony add <n> <project-slug> <git-repo-url> [--codex|--claude|--minimax] [--model <name>] [--reasoning-effort <effort>]"
    echo ""
    echo "Examples:"
    echo "  symphony add rizz-ai slug-abc git@github.com:org/rizz-ai.git"
    echo "  symphony add rizz-ai slug-abc git@github.com:org/rizz-ai.git --claude"
    echo "  symphony add rizz-ai slug-abc git@github.com:org/rizz-ai.git --minimax"
    echo "  symphony add rizz-ai slug-abc git@github.com:org/rizz-ai.git --codex --model gpt-5.3-codex"
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
  patch_codex_command "$workflow_file" "$model" "$reasoning_effort"

  echo "Adapter: $adapter"
  [ "$use_minimax" = true ] && echo "Provider: MiniMax M2.7 (via Claude adapter)"

  grep -v "^${name}|" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" || true
  mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  echo "${name}|${slug}|${repo}|${adapter}|${use_minimax}|${model}|${reasoning_effort}" >> "$CONFIG_FILE"

  echo "Added project: $name"
  echo "Workflow: $workflow_file"
}

# ---------------------------------------------------------------------------
# start
# ---------------------------------------------------------------------------
cmd_start() {
  local name="" adapter="" use_minimax=false adapter_set=false model="" model_set=false reasoning_effort="" reasoning_effort_set=false

  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --claude)   adapter="claude"; adapter_set=true; shift ;;
      --codex)    adapter="codex";  adapter_set=true; shift ;;
      --minimax)  adapter="claude"; use_minimax=true; adapter_set=true; shift ;;
      --model)
        model="${2:-}"
        model_set=true
        shift 2
        ;;
      --reasoning-effort)
        reasoning_effort="${2:-}"
        reasoning_effort_set=true
        shift 2
        ;;
      *) positional+=("$1"); shift ;;
    esac
  done

  name="${positional[0]:-}"

  if [ -z "$model" ] && [ "$adapter" = "codex" ] && [ -n "${positional[1]:-}" ]; then
    model="${positional[1]}"
    model_set=true
  fi

  if [ -z "$name" ]; then
    echo "Usage: symphony start <n> [--codex|--claude|--minimax] [--model <name>] [--reasoning-effort <effort>]"
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

  local saved_name="" saved_slug="" saved_repo="" saved_adapter="" saved_minimax="" saved_model="" saved_reasoning_effort=""
  IFS='|' read -r saved_name saved_slug saved_repo saved_adapter saved_minimax saved_model saved_reasoning_effort <<< "$project_line"

  if [ "$adapter_set" = false ] || [ -z "$adapter" ]; then
    adapter="$saved_adapter"
  fi

  if [ "$model_set" = false ]; then
    model="$saved_model"
  fi

  if [ "$reasoning_effort_set" = false ]; then
    reasoning_effort="$saved_reasoning_effort"
  fi

  [ "$saved_minimax" = "true" ] && use_minimax=true

  if [ "$adapter_set" = true ] || [ "$model_set" = true ] || [ "$reasoning_effort_set" = true ]; then
    grep -v "^${name}|" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" || true
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "${saved_name}|${saved_slug}|${saved_repo}|${adapter}|${use_minimax}|${model}|${reasoning_effort}" >> "$CONFIG_FILE"
  fi

  patch_agent "$workflow_file" "$adapter"
  patch_codex_command "$workflow_file" "$model" "$reasoning_effort"

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
  while IFS='|' read -r name slug repo adapter use_minimax model reasoning_effort; do
    local agent_info="$adapter"
    [ "$use_minimax" = "true" ] && agent_info="$adapter (MiniMax M2.7)"
    echo "  $name"
    echo "    slug:    $slug"
    echo "    repo:    $repo"
    echo "    adapter: $agent_info"
    [ -n "$model" ] && echo "    model:   $model"
    [ -n "$reasoning_effort" ] && echo "    effort:  $reasoning_effort"
    echo ""
  done < "$CONFIG_FILE"
}

# ---------------------------------------------------------------------------
# check_for_update
# ---------------------------------------------------------------------------
check_for_update() {
  local remote_version
  remote_version=$(curl -s --max-time 5 "$REPO_URL" 2>/dev/null | grep '^VERSION="' | cut -d'"' -f2 || true)

  if [ -z "$remote_version" ]; then
    echo "Could not fetch remote version (network error or repo unavailable)"
    return 1
  fi

  if [ "$remote_version" = "$VERSION" ]; then
    echo "You have the latest version: v$VERSION"
    return 1
  fi

  echo "Update available: v$VERSION -> v$remote_version"
  return 0
}

# ---------------------------------------------------------------------------
# update
# ---------------------------------------------------------------------------
cmd_update() {
  local check_only=false force_update=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) check_only=true; shift ;;
      --force) force_update=true; shift ;;
      *) shift ;;
    esac
  done

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

  if [ "$check_only" = true ]; then
    check_for_update && return 0
    return 1
  fi

  local remote_script
  remote_script=$(curl -s --max-time 10 "$REPO_URL" 2>/dev/null || true)

  if [ -z "$remote_script" ]; then
    echo "Failed to fetch remote script. Check your network connection."
    exit 1
  fi

  local remote_version
  remote_version=$(echo "$remote_script" | grep '^VERSION="' | cut -d'"' -f2)

  if [ "$remote_version" = "$VERSION" ] && [ "$force_update" = false ]; then
    echo "Symphony is already up to date: v$VERSION"
    return 0
  fi

  echo "Updating Symphony from v$VERSION to v${remote_version:-unknown}..."
  echo "$remote_script" > "$installed_path"
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
# version
# ---------------------------------------------------------------------------
cmd_version() {
  echo "Symphony CLI v$VERSION"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "${1:-}" in
  add)     cmd_add "${@:2}" ;;
  start)   cmd_start "${@:2}" ;;
  list)    cmd_list ;;
  update)  cmd_update "${@:2}" ;;
  install) cmd_install ;;
  version) cmd_version ;;
  --version) cmd_version ;;
  *)
    echo "Symphony CLI v$VERSION"
    echo ""
    echo "Commands:"
    echo "  symphony add <n> <project-slug> <git-repo-url> [--codex|--claude|--minimax] [--model <name>] [--reasoning-effort <effort>]"
    echo "  symphony start <n> [--codex|--claude|--minimax] [--model <name>] [--reasoning-effort <effort>]"
    echo "  symphony list"
    echo "  symphony update    Update the installed symphony script (auto-checks GitHub)"
    echo "  symphony update --check   Check if update available without installing"
    echo "  symphony update --force    Force update even if same version"
    echo "  symphony install   Install symphony to your bin"
    echo "  symphony version   Show version"
    echo ""
    echo "  --codex    Use Codex adapter (default)"
    echo "  --claude   Use Claude adapter"
    echo "  --minimax  Use Claude adapter routed through MiniMax M2.7"
    echo "  --model    Set the Codex model for this project"
    echo "  --reasoning-effort  Set the Codex reasoning effort for this project"
    echo ""
    echo "Examples:"
    echo "  symphony add rizz-ai slug-abc git@github.com:org/rizz-ai.git"
    echo "  symphony add rizz-ai slug-abc git@github.com:org/rizz-ai.git --claude"
    echo "  symphony add rizz-ai slug-abc git@github.com:org/rizz-ai.git --minimax"
    echo "  symphony add rizz-ai slug-abc git@github.com:org/rizz-ai.git --codex --model gpt-5.3-codex"
    echo "  symphony start rizz-ai"
    echo "  symphony start rizz-ai --minimax"
    echo "  symphony start rizz-ai --codex --model codex-mini-latest --reasoning-effort medium"
    echo "  symphony update"
    echo "  symphony update --check"
    ;;
esac
