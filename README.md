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

---

### `get_all_testplaninstances_formatted.sh`

Fetches all testplan instances from the Weebl API and prints a formatted report grouped by product, filtered to November 2025 onwards.

#### Requirements

Requires `curl`, `jq`, and `python3`.

#### Environment variables

Set these in a `.env` file or in your environment:

| Variable | Description |
|---|---|
| `WEEBL_API_BASE` | Base URL for the Weebl API |
| `WEEBL_TOKEN` | API authentication token |

#### Usage

```
./get_all_testplaninstances_formatted.sh [--from YYYY-MM-DD] [--to YYYY-MM-DD]
```

| Flag | Description |
|---|---|
| `--from DATE` | Filter from this date (inclusive). If omitted, defaults to the nearest past Nov 1 or May 1. |
| `--to DATE` | Filter up to this date (inclusive). Requires `--from`. If omitted with `--from`, defaults to today. |

#### Output

Results are grouped by product (e.g. MAAS, Juju, Dataplatforms, Canonical k8s, Microstack) and sorted by date within each group. Each row shows:

```
<date>  <status>      <testplan name>  <version>
```

Version info is extracted from the product name and formatted per product type:
- **Microstack** — `<version> rev <revision> <channel>` (e.g. `2024.1 rev 991 beta`)
- **Database charms** (postgresql, mysql) — `<db version> rev <revision>`
- **k8s charms** — `<k8s version> rev <revision>`
- **Deb packages** — extracted version string
- **Snaps/others** — extracted version or revision number
