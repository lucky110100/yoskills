# -*- coding: utf-8 -*-
"""Shared workspace/output path helpers for jiuwen-skip-analysis scripts."""
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
WORKSPACE = Path(r"D:\jiuwen\main")
OUTPUT_DIR = WORKSPACE / "localoutput"

# CSV 列头（全中文，固定顺序）
CSV_FIELDS = [
    "Java文件",
    "类名",
    "模块",
    "子模块",
    "Python用例",
    "跳过类型",
    "优先级",
    "根因",
    "测试待补项",
    "SDK实现证据",
    "分析说明",
    "跳过原因",
    "功能缺失明细",
]

# merge_reviews JSON 可写字段（与 CSV 列名一致）
REVIEW_FIELDS = (
    "优先级",
    "根因",
    "测试待补项",
    "SDK实现证据",
    "分析说明",
    "功能缺失明细",
)

# 旧版英文列头 → 中文（读取旧 CSV 时迁移）
LEGACY_HEADER_MAP = {
    "java_file": "Java文件",
    "class_name": "类名",
    "python_case": "Python用例",
    "skip_kind": "跳过类型",
    "priority": "优先级",
    "root_cause": "根因",
    "missing_feature": "测试待补项",
    "analysis": "分析说明",
    "disabled_reason": "跳过原因",
}

# merge JSON 旧英文字段 → 中文字段
LEGACY_REVIEW_KEY_MAP = {
    "priority": "优先级",
    "root_cause": "根因",
    "missing_feature": "测试待补项",
    "analysis": "分析说明",
    "功能缺失明细": "功能缺失明细",
    "SDK实现证据": "SDK实现证据",
}


def migrate_row_keys(row: dict) -> dict:
    """Migrate legacy English CSV column keys to Chinese."""
    if not any(k in row for k in LEGACY_HEADER_MAP):
        return row
    out = {}
    for k, v in row.items():
        out[LEGACY_HEADER_MAP.get(k, k)] = v
    return out


def normalize_review_entry(entry: dict) -> dict:
    """Accept merge JSON with English or Chinese field names."""
    out = {}
    for k, v in entry.items():
        cn = LEGACY_REVIEW_KEY_MAP.get(k, k)
        out[cn] = v
    return out


def ensure_output_dir() -> Path:
    """Create localoutput under workspace if missing."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    return OUTPUT_DIR


def resolve_csv_path(relative_csv: str, override: Path | None = None) -> Path:
    """Resolve CSV path and ensure parent directory exists."""
    ensure_output_dir()
    if override is not None:
        path = override.expanduser()
        if not path.is_absolute():
            path = WORKSPACE / path
    else:
        path = WORKSPACE / relative_csv
    path.parent.mkdir(parents=True, exist_ok=True)
    return path
