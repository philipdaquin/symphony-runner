# Symphony Runner with claude/codex/minimax integration

Shell wrapper for creating project-specific Symphony workflows and launching them against Linear-backed projects with support for multiple AI adapters.

Refer to my forked version of symphony for Claude/Codex/MiniMax integration:
https://github.com/philipdaquin/symphony

Choose between claude/codex integration
`git clone https://github.com/philipdaquin/symphony.git`

or the original codex only integration
`git clone https://github.com/openai/symphony.git`


## What It Does

`symphony.sh`:

- stores project mappings in `~/.symphony/projects.conf`
- copies your base Symphony workflow from `$SYMPHONY_BIN/WORKFLOW.md`
- patches the copied workflow with project slug, repo URL, workspace path, and agent config
- auto-builds the Symphony escript when source files change
- starts Symphony with the generated workflow

## Prerequisites

- Symphony installed locally
- `mise`
- `git`
- a valid `LINEAR_API_KEY`

Optional:

- `MINIMAX_API_KEY` for MiniMax routing
- `SYMPHONY_BIN` if your Symphony checkout is not at the default path

Default Symphony path: `$HOME/symphony/elixir`

Override it if needed:

```bash
export SYMPHONY_BIN=/path/to/symphony/elixir
```

## Setup

Export your API keys before running the script:

```bash
export LINEAR_API_KEY=your_linear_api_key
export MINIMAX_API_KEY=your_minimax_api_key  # optional, for MiniMax routing
```

Make the script executable:

```bash
chmod +x symphony.sh
```

## Adapters

The script supports three adapter modes:

| Flag | Adapter | Description |
|------|---------|-------------|
| `--codex` | Codex | Uses OpenAI Codex agent (default) |
| `--claude` | Claude | Uses Anthropic Claude adapter |
| `--minimax` | Claude + MiniMax | Routes Claude through MiniMax M2.7 |

When using `--minimax`, the script exports these env vars:

```bash
ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic"
ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY"
API_TIMEOUT_MS="3000000"
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
ANTHROPIC_MODEL="MiniMax-M2.7"
ANTHROPIC_DEFAULT_SONNET_MODEL="MiniMax-M2.7"
ANTHROPIC_DEFAULT_OPUS_MODEL="MiniMax-M2.7"
ANTHROPIC_DEFAULT_HAIKU_MODEL="MiniMax-M2.7"
```

## Usage

### Add a project

```bash
./symphony.sh add <name> <linear-project-slug> <git-repo-url> [--codex|--claude|--minimax]
```

Examples:

```bash
./symphony.sh add rizz-ai symphony-abc git@github.com:org/repo.git
./symphony.sh add rizz-ai symphony-abc git@github.com:org/repo.git --claude
./symphony.sh add rizz-ai symphony-abc git@github.com:org/repo.git --minimax
```

The adapter preference is saved in `projects.conf` and reused on `start` unless overridden.

### List configured projects

```bash
./symphony.sh list
```

### Start a project

```bash
./symphony.sh start <name> [--codex|--claude|--minimax]
```

Examples:

```bash
./symphony.sh start rizz-ai
./symphony.sh start rizz-ai --minimax
```

Starting a project:

1. Loads adapter preference from `projects.conf` (if no flag passed)
2. Patches the workflow file with the agent config (`adapter`, `max_concurrent_agents: 10`, `max_turns: 20`)
3. Exports MiniMax env vars if `--minimax` was used
4. Builds the Symphony escript if needed (rebuilds if source files are newer)
5. Launches Symphony with the workflow

### Install or Update

```bash
./symphony.sh install   # Install symphony to ~/bin/symphony (or ~/.local/bin/symphony)
./symphony.sh update    # Update an existing installation
```

Examples:

```bash
./symphony.sh install   # First-time installation
./symphony.sh update    # Update to the latest version
```

The `update` command detects where Symphony is already installed (`~/bin/symphony`, `~/.local/bin/symphony`, or anywhere in PATH) and replaces it with the current script.

## How It Works

When you run `add`, the script:

1. checks that `$SYMPHONY_BIN/WORKFLOW.md` exists
2. copies it to `~/.symphony/workflows/WORKFLOW_<name>.md`
3. updates:
   - `project_slug`
   - the `git clone` line
   - the workspace root under `~/code/symphony-workspaces/<name>`
4. patches the agent block with adapter and concurrency settings
5. stores the project in `~/.symphony/projects.conf`

When you run `start`, the script:

1. loads saved project config
2. patches the workflow with current adapter settings
3. exports MiniMax env vars if needed
4. checks if the escript needs rebuilding (rebuilds if sources are newer)
5. launches Symphony with `--logs-root` set to `~/.symphony`

## Files Used

- `symphony.sh`: wrapper script
- `~/.symphony/projects.conf`: stored project mappings (format: `name|slug|repo|adapter|use_minimax`)
- `~/.symphony/workflows/WORKFLOW_<name>.md`: generated per-project workflows
- `$SYMPHONY_BIN/WORKFLOW.md`: base workflow template
- `$SYMPHONY_BIN/bin/symphony`: built escript (auto-built on demand)

## Important Notes

- `LINEAR_API_KEY` is required or the script exits immediately.
- `MINIMAX_API_KEY` is required when using `--minimax`.
- The in-place `sed -i ''` commands are written for macOS/BSD `sed`.
