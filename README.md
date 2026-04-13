# weebl_scripts

Helper scripts for working with the Weebl CI/CD triage system.

## Scripts

### `triage_status.py`

Shows pipeline triage status grouped by:

1. **In progress** — jobs currently running
2. **Finished — triager assigned** — completed jobs with a triager
3. **Finished — no triager** — completed failed jobs grouped by addon name

#### Requirements

Uses `uv` for dependency management. Dependencies are declared inline and resolved automatically on first run.

#### Environment variables

Set these in a `.env` file or in your environment:

| Variable | Description |
|---|---|
| `WEEBL_API_BASE` | Base URL for the Weebl API |
| `WEEBL_TESTRUNS_BASE` | Base URL for the test runs UI (used to generate clickable links in output) |
| `WEEBL_TOKEN` | API authentication token |

#### Usage

```
uv run triage_status.py [--days N] [--ignore_triagers]
```

| Flag | Description |
|---|---|
| `--days N` | Limit results to pipelines from the last N days (default: no limit) |
| `--ignore_triagers` | Group all finished jobs by addon, ignoring triager assignment |
