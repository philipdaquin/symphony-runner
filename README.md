# Symphony Runner

Small shell wrapper for running [Symphony](https://github.com/gitwithflash/symphony) workflows against a Linear project while using the OpenAI Codex app server as the coding agent.

## What This Does

`symphony.sh` helps you:

- register a project name, Linear project slug, and Git repo URL
- generate a Symphony workflow file in `~/.symphony/workflows`
- launch Symphony with `codex app-server` configured as the agent command

The generated workflow uses:

- `tracker.kind: linear`
- `codex.command: codex app-server`
- `hooks.after_create: git clone --depth 1 <repo> .`

## Prerequisites

Make sure these are installed and working:

- Symphony
- `codex` CLI with `codex app-server` available
- `mise`
- `git`
- a valid `LINEAR_API_KEY`

By default this script expects Symphony here:

```bash
$HOME/symphony/elixir
```

If your Symphony checkout is elsewhere, set:

```bash
export SYMPHONY_BIN=/path/to/symphony/elixir
```

## Setup

Make the script executable:

```bash
chmod +x symphony.sh
```

Export your Linear API key:

```bash
export LINEAR_API_KEY=your_linear_api_key
```

Optional: add a convenient alias:

```bash
alias symphony="$PWD/symphony.sh"
```

## How To Use With Symphony + OpenAI Codex

### 1. Add a project

```bash
./symphony.sh add <name> <linear-project-slug> <git-repo-url>
```

Example:

```bash
./symphony.sh add rizz-ai symphony-6d2ee11f7e5e git@github.com:philipdaquin/rizz-ai.git
```

This creates:

- a workflow file at `~/.symphony/workflows/WORKFLOW_<name>.md`
- a project entry in `~/.symphony/projects.conf`

### 2. List configured projects

```bash
./symphony.sh list
```

### 3. Start Symphony for a project

```bash
./symphony.sh start <name>
```

Example:

```bash
./symphony.sh start rizz-ai
```

When started, the script:

1. looks up the project in `~/.symphony/projects.conf`
2. loads the generated workflow
3. changes into your Symphony checkout
4. runs:

```bash
mise exec -- ./bin/symphony <workflow-file> --i-understand-that-this-will-be-running-without-the-usual-guardrails
```

## Generated Workflow Example

For a project named `rizz-ai`, the script generates a workflow like this:

```yaml
---
tracker:
  kind: linear
  project_slug: "symphony-6d2ee11f7e5e"
workspace:
  root: ~/code/symphony-workspaces/rizz-ai
hooks:
  after_create: |
    git clone --depth 1 git@github.com:philipdaquin/rizz-ai.git .
agent:
  max_concurrent_agents: 5
  max_turns: 20
codex:
  command: codex app-server
---
```

This is the key OpenAI integration point: Symphony will use `codex app-server` for agent execution.

## Files Used

- `~/.symphony/projects.conf`: flat config storing project mappings
- `~/.symphony/workflows/`: generated Symphony workflow files
- `symphony.sh`: the wrapper script in this repo

## Notes

- `LINEAR_API_KEY` is required even for basic script usage.
- If a project name already exists, the script replaces that entry in `projects.conf` and regenerates the workflow.
- The script currently assumes a Linear-backed Symphony workflow.
