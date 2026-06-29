# -*- coding: utf-8 -*-
"""Merge Agent/LLM code-review conclusions into skip analysis CSV."""
import argparse
import csv
import json
from pathlib import Path

from io_paths import (
    CSV_FIELDS,
    REVIEW_FIELDS,
    ensure_output_dir,
    migrate_row_keys,
    normalize_review_entry,
    resolve_csv_path,
)

SCRIPTS_DIR = Path(__file__).resolve().parent
MODULES_PATH = SCRIPTS_DIR / "modules.json"

ROOT_CAUSE_SDK_GAP = "功能缺失"
ROOT_CAUSE_NOT_TRANSLATED = "测试用例未翻译"
ROOT_CAUSE_ENV = "环境依赖"


def load_modules():
    with MODULES_PATH.open(encoding="utf-8") as f:
        return json.load(f)


def load_reviews(paths):
    merged = {}
    for path in paths:
        with Path(path).open(encoding="utf-8") as f:
            data = json.load(f)
        for cls, entry in data.items():
            merged[cls] = normalize_review_entry(entry)
    return merged


def ensure_csv_schema(fieldnames):
    out = list(fieldnames)
    for col in CSV_FIELDS:
        if col not in out:
            out.append(col)
    return out


def validate_row(row):
    issues = []
    root = row.get("根因", "")
    sdk_evidence = (row.get("SDK实现证据") or "").strip()
    gap_detail = (row.get("功能缺失明细") or "").strip()

    if root == ROOT_CAUSE_NOT_TRANSLATED and not sdk_evidence:
        issues.append("测试用例未翻译 但缺少 SDK实现证据")
    if root == ROOT_CAUSE_ENV and not sdk_evidence:
        issues.append("环境依赖 但缺少 SDK实现证据（应证明 Java 能力/测试逻辑已对齐）")
    if root == ROOT_CAUSE_SDK_GAP and not gap_detail:
        issues.append("功能缺失 但缺少 功能缺失明细")
    if root == ROOT_CAUSE_SDK_GAP and sdk_evidence:
        issues.append("功能缺失 时不应填写 SDK实现证据（应写在 功能缺失明细）")
    if root == ROOT_CAUSE_NOT_TRANSLATED and gap_detail:
        issues.append("测试用例未翻译 时不应填写 功能缺失明细")
    return issues


def merge_csv(csv_path, reviews):
    with csv_path.open(encoding="utf-8-sig", newline="") as f:
        raw_rows = list(csv.DictReader(f))
    if not raw_rows:
        raise SystemExit(f"Empty CSV: {csv_path}")

    rows = [migrate_row_keys(r) for r in raw_rows]
    fieldnames = ensure_csv_schema(list(rows[0].keys()))
    updated = 0
    missing = []

    for cls, entry in reviews.items():
        matched = [r for r in rows if r.get("类名") == cls]
        if not matched:
            missing.append(cls)
            continue
        for row in matched:
            for key in REVIEW_FIELDS:
                if key in entry:
                    row[key] = entry[key] or ""
            root = row.get("根因", "")
            if root == ROOT_CAUSE_SDK_GAP:
                row["SDK实现证据"] = ""
            elif root in (ROOT_CAUSE_NOT_TRANSLATED, ROOT_CAUSE_ENV):
                row["功能缺失明细"] = ""
            for col in fieldnames:
                row.setdefault(col, "")
            updated += 1

    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)

    pending = sum(1 for r in rows if r.get("根因") == "待检视")
    all_issues = []
    for row in rows:
        if row.get("根因") != "待检视":
            all_issues.extend(f"{row.get('类名', '?')}: {msg}" for msg in validate_row(row))
    return updated, pending, missing, all_issues


def main():
    modules = load_modules()
    parser = argparse.ArgumentParser(description="Merge LLM review JSON into skip analysis CSV")
    parser.add_argument("--module", required=True, help="Suite key from modules.json")
    parser.add_argument(
        "--reviews",
        action="append",
        required=True,
        help="JSON: {类名: {根因, 优先级, SDK实现证据, ...}}",
    )
    parser.add_argument("--csv", type=Path, help="Override CSV path")
    args = parser.parse_args()

    if args.module not in modules:
        parser.error(f"Unknown module {args.module!r}")

    ensure_output_dir()
    csv_path = resolve_csv_path(modules[args.module]["output_csv"], args.csv)
    if not csv_path.is_file():
        parser.error(f"CSV not found: {csv_path}. Run export_skip_csv.py first.")

    reviews = load_reviews(args.reviews)
    updated, pending, missing, issues = merge_csv(csv_path, reviews)
    print(f"Merged {updated} row(s) from {len(reviews)} class(es) -> {csv_path}")
    print(f"  still 待检视: {pending}")
    if missing:
        print(f"  not found in CSV: {', '.join(missing)}")
    if issues:
        print(f"  validation warnings: {len(issues)}")
        for msg in issues[:10]:
            print(f"    - {msg}")
        if len(issues) > 10:
            print(f"    ... and {len(issues) - 10} more")


if __name__ == "__main__":
    main()
