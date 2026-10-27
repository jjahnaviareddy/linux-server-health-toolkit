#!/usr/bin/env python3
"""
generate_report.py

Reads the JSON-lines result files produced by the bash health-check
scripts (disk, memory, service) and produces a single human-readable
Markdown report summarizing that day's server health.

Usage:
    python3 generate_report.py --data-dir ./logs/data --report-dir ./reports --date 2026-07-19

If --date is omitted, today's date is used.
Exits with code 1 if any CRITICAL results were found (useful for chaining
alerts in cron), 0 otherwise.
"""

import argparse
import json
import os
import sys
from datetime import datetime


def parse_args():
    parser = argparse.ArgumentParser(description="Generate a daily server health report.")
    parser.add_argument("--data-dir", required=True, help="Directory containing *_results.jsonl files")
    parser.add_argument("--report-dir", required=True, help="Directory to write the report into")
    parser.add_argument(
        "--date",
        default=datetime.now().strftime("%Y-%m-%d"),
        help="Date (YYYY-MM-DD) to filter results for. Defaults to today.",
    )
    return parser.parse_args()


def load_jsonl(path):
    """Load a JSON-lines file, skipping any malformed lines."""
    records = []
    if not os.path.isfile(path):
        return records
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return records


def filter_by_date(records, date_str):
    return [r for r in records if r.get("timestamp", "").startswith(date_str)]


def status_emoji(status):
    return {"OK": "\u2705", "WARNING": "\u26a0\ufe0f", "CRITICAL": "\U0001F534", "active": "\u2705"}.get(
        status, "\u2753"
    )


def build_disk_section(records):
    lines = [
        "## Disk Usage",
        "",
        "| Mount | Filesystem | Used | Available | % Used | Status |",
        "|---|---|---|---|---|---|",
    ]
    counts = {"warn": 0, "crit": 0}
    if not records:
        lines.append("_No disk data recorded for this date._")
        return lines, counts
    latest_per_disk = {}
    for record in records:
        key = (record.get("host"), record.get("filesystem"), record.get("mount"))
        latest_per_disk[key] = record

    for r in latest_per_disk.values():
        status = r.get("status", "?")
        if status == "WARNING":
            counts["warn"] += 1
        elif status == "CRITICAL":
            counts["crit"] += 1
        lines.append(
            f"| {r.get('mount', '?')} | {r.get('filesystem', '?')} | {r.get('used', '?')} | "
            f"{r.get('available', '?')} | {r.get('percent', '?')}% | {status_emoji(status)} {status} |"
        )
    return lines, counts


def build_memory_section(records):
    lines = ["## Memory & Swap", ""]
    counts = {"warn": 0, "crit": 0}
    if not records:
        lines.append("_No memory data recorded for this date._")
        return lines, counts

    latest = records[-1]
    for key in ("mem_status", "swap_status"):
        st = latest.get(key, "?")
        if st == "WARNING":
            counts["warn"] += 1
        elif st == "CRITICAL":
            counts["crit"] += 1

    lines.append(
        f"- **RAM used:** {latest.get('used_mb', '?')} MB / {latest.get('total_mb', '?')} MB "
        f"({latest.get('mem_percent', '?')}%) \u2014 "
        f"{status_emoji(latest.get('mem_status', '?'))} {latest.get('mem_status', '?')}"
    )
    lines.append(
        f"- **Swap used:** {latest.get('swap_used_mb', '?')} MB / {latest.get('swap_total_mb', '?')} MB "
        f"({latest.get('swap_percent', '?')}%) \u2014 "
        f"{status_emoji(latest.get('swap_status', '?'))} {latest.get('swap_status', '?')}"
    )
    lines.append("")
    return lines, counts


def build_service_section(records):
    lines = ["## Services", "", "| Service | State | Status |", "|---|---|---|"]
    counts = {"warn": 0, "crit": 0}
    if not records:
        lines.append("_No service data recorded for this date._")
        return lines, counts

    latest_per_service = {}
    for r in records:
        latest_per_service[r.get("service", "?")] = r  # keep the latest run per service

    for svc, r in latest_per_service.items():
        state = r.get("state", "?")
        status = "OK" if state == "active" else "CRITICAL"
        if status == "CRITICAL":
            counts["crit"] += 1
        lines.append(f"| {svc} | {state} | {status_emoji(status)} {status} |")
    return lines, counts


def main():
    args = parse_args()
    os.makedirs(args.report_dir, exist_ok=True)

    disk_records = filter_by_date(load_jsonl(os.path.join(args.data_dir, "disk_results.jsonl")), args.date)
    mem_records = filter_by_date(load_jsonl(os.path.join(args.data_dir, "memory_results.jsonl")), args.date)
    svc_records = filter_by_date(load_jsonl(os.path.join(args.data_dir, "service_results.jsonl")), args.date)

    disk_lines, disk_counts = build_disk_section(disk_records)
    mem_lines, mem_counts = build_memory_section(mem_records)
    svc_lines, svc_counts = build_service_section(svc_records)

    cpu_records = filter_by_date(
        load_jsonl(os.path.join(args.data_dir, "cpu_results.jsonl")), args.date
    )
    cpu_lines = ["## CPU Usage", ""]
    cpu_warn = cpu_crit = 0
    if cpu_records:
        cpu = cpu_records[-1]
        status = cpu.get("status", "?")
        cpu_lines.append(
            f"- **CPU used:** {cpu.get('percent', '?')}% — {status_emoji(status)} {status}"
        )
        cpu_warn = int(status == "WARNING")
        cpu_crit = int(status == "CRITICAL")
    else:
        cpu_lines.append("_No CPU data recorded for this date._")
    cpu_lines.append("")

    total_warn = cpu_warn + disk_counts["warn"] + mem_counts["warn"] + svc_counts["warn"]
    total_crit = cpu_crit + disk_counts["crit"] + mem_counts["crit"] + svc_counts["crit"]

    if total_crit > 0:
        overall = "\U0001F534 CRITICAL"
    elif total_warn > 0:
        overall = "\u26a0\ufe0f WARNING"
    else:
        overall = "\u2705 HEALTHY"

    host = "unknown-host"
    for rec_list in (disk_records, mem_records, svc_records):
        if rec_list:
            host = rec_list[0].get("host", host)
            break

    report_lines = [
        f"# Server Health Report \u2014 {args.date}",
        "",
        f"**Host:** {host}  ",
        f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}  ",
        f"**Overall Status:** {overall}",
        "",
        "| Warnings | Critical |",
        "|---|---|",
        f"| {total_warn} | {total_crit} |",
        "",
        *cpu_lines,
        *disk_lines,
        "",
        *mem_lines,
        *svc_lines,
        "",
        "---",
        "_Generated automatically by the Linux Server Health Check Toolkit._",
    ]

    report_path = os.path.join(args.report_dir, f"report-{args.date}.md")
    with open(report_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(report_lines) + "\n")

    print(f"Report written to {report_path}")
    print(f"Overall status: {overall} (warnings={total_warn}, critical={total_crit})")

    sys.exit(1 if total_crit > 0 else 0)


if __name__ == "__main__":
    main()
