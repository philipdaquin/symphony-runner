# Symphony Runner v1.3.0

Shell wrapper for creating project-specific Symphony workflows and launching them against Linear-backed projects with support for multiple AI adapters. Supports claude/codex/minimax integration.

Use `symphony update` to update the installed command.

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
- can persist a per-project Codex model and reasoning effort
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

Install it so you can run `symphony` from anywhere:

```bash
./symphony.sh install
```

## Adapters

The script supports three adapter modes:

| Flag | Adapter | Description |
|------|---------|-------------|
| `--codex` | Codex | Uses OpenAI Codex agent (default) |
| `--claude` | Claude | Uses Anthropic Claude adapter |
| `--minimax` | Claude + MiniMax | Routes Claude through MiniMax M2.7 |

Codex runs also accept:

| Flag | Description |
|------|-------------|
| `--model <name>` | Sets the Codex model, for example `gpt-5.3-codex` or `codex-mini-latest` |
| `--reasoning-effort <effort>` | Sets `model_reasoning_effort`, for example `low`, `medium`, `high`, or `xhigh` |

You can also use the shorthand form `--codex <model>` on `start` to set the model directly.

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
symphony add <name> <linear-project-slug> <git-repo-url> [--codex|--claude|--minimax] [--model <name>] [--reasoning-effort <effort>]
```

Examples:

```bash
symphony add rizz-ai symphony-abc git@github.com:org/repo.git
symphony add rizz-ai symphony-abc git@github.com:org/repo.git --claude
symphony add rizz-ai symphony-abc git@github.com:org/repo.git --minimax
symphony add rizz-ai symphony-abc git@github.com:org/repo.git --codex --model gpt-5.3-codex
```

The adapter preference is saved in `projects.conf` and reused on `start` unless overridden.
If you pass `--model` or `--reasoning-effort` to `add`, those values are also saved and reused.

### Edit a project slug

Update the Linear slug for an existing project without re-adding it:

```bash
symphony edit kozu --slug kozu-ai-assisted-canvas-40caa03f7837
```

This updates both the saved project config and its generated workflow.

### List configured projects

```bash
symphony list
```

### Start a project

```bash
symphony start <name> [--codex|--claude|--minimax] [--model <name>] [--reasoning-effort <effort>]
```

Examples:

```bash
symphony start rizz-ai
symphony start rizz-ai --minimax
symphony start rizz-ai --codex gpt-5.4-mini
symphony start rizz-ai --codex --model codex-mini-latest --reasoning-effort medium
```

Start a configured project:

1. Loads adapter preference from `projects.conf` if no adapter flag is passed
2. Loads saved `model` and `reasoning_effort` values from `projects.conf` unless overridden
3. Patches the workflow file with the agent config (`adapter`, `max_concurrent_agents: 10`, `max_turns: 20`)
4. Rewrites `codex.command` when a Codex model or reasoning effort is set
5. Saves any overrides back into `projects.conf`
6. Exports MiniMax env vars if `--minimax` was used
7. Builds the Symphony escript if needed, then launches Symphony with the workflow

If you have not installed the wrapper yet, run the same commands as `./symphony.sh <command>` from this repository.

### Install or Update

```bash
./symphony.sh install   # Install symphony to ~/bin/symphony (or ~/.local/bin/symphony)
symphony update    # Update the installed command from GitHub
symphony update --check   # Check if update available without installing
symphony version   # Show current version
```

Examples:

```bash
./symphony.sh install   # First-time installation
symphony update    # Update the installed command
symphony update --check   # Check for updates
```

The `update` command fetches from GitHub main branch and auto-updates if a newer version is available.

## Run Upstream Symphony Directly

Use `symphony-openai.sh` when you want to run the original OpenAI checkout without the fork-based
project runner:

```bash
./symphony-openai.sh
```

By default it uses:

```text
/Users/philipdaquin/Documents/symphony/symphony/elixir
```

Override that location with `SYMPHONY_ORIGINAL_BIN`:

```bash
SYMPHONY_ORIGINAL_BIN=/path/to/symphony/elixir ./symphony-openai.sh /path/to/WORKFLOW.md
```

Install the launcher as `symphony-openai`:

```bash
./symphony-openai.sh install
```

The launcher passes Symphony options through unchanged, so this works too:

```bash
symphony-openai ./WORKFLOW.md --port 4000
```

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

1. loads saved project config, including model defaults
2. patches the workflow with current adapter settings
3. rewrites the Codex command for the selected overrides
4. exports MiniMax env vars if needed
5. checks if the escript needs rebuilding (rebuilds if sources are newer)
6. launches Symphony with `--logs-root` set to `~/.symphony`

## Files Used

- `symphony.sh`: wrapper script
- `~/.symphony/projects.conf`: stored project mappings (format: `name|slug|repo|adapter|use_minimax|model|reasoning_effort`)
- `~/.symphony/workflows/WORKFLOW_<name>.md`: generated per-project workflows
- `$SYMPHONY_BIN/WORKFLOW.md`: base workflow template
- `$SYMPHONY_BIN/bin/symphony`: built escript (auto-built on demand)

## Important Notes

- `LINEAR_API_KEY` is required or the script exits immediately.
- `MINIMAX_API_KEY` is required when using `--minimax`.
- The in-place `sed -i ''` commands are written for macOS/BSD `sed`.
- Codex model names are passed straight through to the `codex` CLI, so the exact accepted values depend on your installed Codex version.
