# Symphony Runner

Small shell wrapper for creating project-specific Symphony workflows from your existing Symphony installation and launching them against Linear-backed projects.

## What It Does

`symphony.sh`:

- stores project mappings in `~/.symphony/projects.conf`
- copies your base Symphony workflow from `$SYMPHONY_BIN/WORKFLOW.md`
- patches the copied workflow with a project slug, repo URL, and workspace path
- starts Symphony with the generated workflow

This wrapper does not define the full workflow itself. It assumes your Symphony checkout already contains a working base `WORKFLOW.md`.

## Prerequisites

You need:

- Symphony installed locally
- `mise`
- `git`
- a valid `LINEAR_API_KEY`

Optional:

- `SYMPHONY_BIN` if your Symphony checkout is not at the default path

Default Symphony path:

```bash
$HOME/symphony/elixir
```

Override it if needed:

```bash
export SYMPHONY_BIN=/path/to/symphony/elixir
```

Export your Linear API key before running the script:

```bash
export LINEAR_API_KEY=your_linear_api_key
```

Make the script executable:

```bash
chmod +x symphony.sh
```

## How It Works

When you run `add`, the script:

1. checks that `$SYMPHONY_BIN/WORKFLOW.md` exists
2. copies it to `~/.symphony/workflows/WORKFLOW_<name>.md`
3. updates:
   - `tracker.project_slug`
   - the `git clone` line
   - the workspace root under `~/code/symphony-workspaces/<name>`
4. stores the project in `~/.symphony/projects.conf`

When you run `start`, the script launches:

```bash
mise exec -- ./bin/symphony <workflow-file> --i-understand-that-this-will-be-running-without-the-usual-guardrails
```

## Usage

Add a project:

```bash
./symphony.sh add <name> <linear-project-slug> <git-repo-url>
```

Example:

```bash
./symphony.sh add rizz-ai symphony-6d2ee11f7e5e git@github.com:philipdaquin/rizz-ai.git
```

List configured projects:

```bash
./symphony.sh list
```

Start a project:

```bash
./symphony.sh start <name>
```

Example:

```bash
./symphony.sh start rizz-ai
```

## Files Used

- `symphony.sh`: wrapper script
- `~/.symphony/projects.conf`: stored project mappings
- `~/.symphony/workflows/WORKFLOW_<name>.md`: generated per-project workflows
- `$SYMPHONY_BIN/WORKFLOW.md`: base workflow template copied and patched by this script

## Important Notes

- `LINEAR_API_KEY` is required or the script exits immediately.
- The script depends on the structure of your existing Symphony `WORKFLOW.md`.
- Any agent configuration, including OpenAI Codex integration, comes from the base workflow in your Symphony checkout.
- The in-place `sed -i ''` commands are written for macOS/BSD `sed`.
