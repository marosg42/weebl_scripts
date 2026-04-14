#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "requests",
#   "python-dotenv",
# ]
# ///
"""
Show pipeline triage status grouped by:
    1. In progress jobs
    2. Finished jobs with a triager assigned
    3. Finished jobs without a triager, grouped by addon name

No human brain cell was harmed - all AI generated.
"""

import argparse
import os
import requests
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from dotenv import load_dotenv

load_dotenv()

API_BASE = os.environ["WEEBL_API_BASE"]
TESTRUNS_BASE = os.environ["WEEBL_TESTRUNS_BASE"]
TOKEN = os.environ["WEEBL_TOKEN"]


def load_token():
    return TOKEN


def fetch_all(session, url, params, page_size=100):
    """Fetch all pages from a paginated endpoint."""
    results = []
    params = dict(params, limit=page_size, offset=0)
    while True:
        resp = session.get(url, params=params)
        resp.raise_for_status()
        data = resp.json()
        results.extend(data["results"])
        total = data.get("count", "?")
        print(f"\r  fetching: {len(results)}/{total}", end="", file=sys.stderr, flush=True)
        if not data.get("next"):
            break
        params["offset"] += params["limit"]
    print(file=sys.stderr)
    return results


def addon_name(pipeline):
    job = pipeline.get("job")
    if not job:
        return "(no job)"
    addon = job.get("addon_id")
    if not addon:
        return "(no addon)"
    return addon.get("name") or "(unnamed addon)"


def sku_name(pipeline):
    sku = pipeline.get("sku")
    if isinstance(sku, dict):
        return sku.get("name", "?")
    return str(sku) if sku else "?"


def triager_name(pipeline):
    tb = pipeline.get("triaged_by")
    if isinstance(tb, dict):
        return tb.get("username", "?")
    return str(tb) if tb else None


def fmt_time(ts):
    if not ts:
        return "?"
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        now = datetime.now(timezone.utc)
        delta = now - dt
        hours, rem = divmod(int(delta.total_seconds()), 3600)
        mins = rem // 60
        if hours >= 24:
            return dt.strftime("%Y-%m-%d %H:%M UTC")
        if hours:
            return f"{hours}h {mins}m ago"
        return f"{mins}m ago"
    except Exception:
        return ts


def pipeline_url(p):
    uuid = p.get("uuid", "?")
    return f"{TESTRUNS_BASE}/{uuid}"


def silo_name(pipeline):
    silo = pipeline.get("silo")
    if isinstance(silo, dict):
        return silo.get("name", "?")
    return str(silo) if silo else "?"


def fmt_bugs(p):
    bugs = p.get("bugs") or []
    if not bugs:
        return ""
    parts = []
    for b in bugs:
        num = b.get("bug_number")
        summary = b.get("summary", "")
        url = b.get("bug_url", "")
        parts.append(
            f"bug#{num} {url} ({summary})" if url else f"bug#{num} ({summary})"
        )
    return "  bugs: " + ", ".join(parts)


def print_pipeline(p, extra=""):
    print(f"  [{sku_name(p)}]  {addon_name(p)}  silo: {silo_name(p)}{extra}")
    print(f"    {pipeline_url(p)}{fmt_bugs(p)}")


def main():
    parser = argparse.ArgumentParser(description="Show pipeline triage status.")
    parser.add_argument(
        "--days",
        type=int,
        default=None,
        help="Limit to pipelines from the last N days (default: no limit)",
    )
    parser.add_argument(
        "--ignore_triagers",
        action="store_true",
        help="Group all finished jobs by addon, ignoring triager assignment",
    )
    args = parser.parse_args()

    token = load_token()
    session = requests.Session()
    session.headers["Authorization"] = f"Token {token}"

    since = None
    if args.days is not None:
        since = (datetime.now(timezone.utc) - timedelta(days=args.days)).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )
        print(f"Fetching pipelines (last {args.days} days)...", file=sys.stderr)
    else:
        print("Fetching pipelines...", file=sys.stderr)

    finished_params = {
        "triaged": "false",
        "completed": "true",
        "failed": "true",
        "ordering": "-completed_at",
    }
    if since:
        finished_params["completed_at_from"] = since

    finished = fetch_all(session, f"{API_BASE}/pipelines/", finished_params)
    if since:
        # Filter client-side because the API ignores the completed_at_from param
        since_dt = datetime.fromisoformat(since.replace("Z", "+00:00"))
        finished = [
            p for p in finished
            if p.get("completed_at") and
            datetime.fromisoformat(p["completed_at"].replace("Z", "+00:00")) >= since_dt
        ]

    # Split finished into triaged (with triager) vs untriaged
    if args.ignore_triagers:
        with_triager = []
        without_triager = finished
    else:
        with_triager = [p for p in finished if triager_name(p)]
        without_triager = [p for p in finished if not triager_name(p)]

    # Group untriaged by addon name
    by_addon = defaultdict(list)
    for p in without_triager:
        by_addon[addon_name(p)].append(p)

    # ── Finished — triager assigned ──────────────────────────────────────────
    if not args.ignore_triagers:
        print(f"\n{'=' * 60}")
        print(f"  FINISHED — triager assigned  ({len(with_triager)} jobs)")
        print(f"{'=' * 60}")
        if not with_triager:
            print("  (none)")
        with_triager.sort(
            key=lambda p: (triager_name(p) or "", p.get("completed_at") or "")
        )
        for p in with_triager:
            completed = fmt_time(p.get("completed_at"))
            print_pipeline(
                p, extra=f"  completed {completed}  triager: {triager_name(p)}"
            )

    # ── Finished — grouped by addon ──────────────────────────────────────────
    section_title = (
        "FINISHED — by addon" if args.ignore_triagers else "FINISHED — no triager"
    )
    print(f"\n{'=' * 60}")
    print(f"  {section_title}  ({len(without_triager)} jobs, {len(by_addon)} addons)")
    print(f"{'=' * 60}")
    if not without_triager:
        print("  (none)")
    for addon, pipelines in sorted(by_addon.items()):
        print(f"\n  [{addon}]  ({len(pipelines)} jobs)")
        for p in pipelines:
            completed = fmt_time(p.get("completed_at"))
            triager = triager_name(p)
            triager_str = f"  triager: {triager}" if triager else ""
            print(
                f"    {sku_name(p)}  silo: {silo_name(p)}  completed {completed}{triager_str}"
            )
            print(f"      {pipeline_url(p)}{fmt_bugs(p)}")

    print()


if __name__ == "__main__":
    main()
