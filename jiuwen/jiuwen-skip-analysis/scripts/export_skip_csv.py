# -*- coding: utf-8 -*-
"""Discover skipped Jiuwen Java tests; export skeleton CSV for LLM code review.

Scripts MUST NOT assign final root_cause. Agent reads Java + Python + SDK each run.
"""
import argparse
import csv
import json
import re
from collections import Counter
from pathlib import Path

from io_paths import CSV_FIELDS, WORKSPACE, ensure_output_dir, resolve_csv_path

SCRIPTS_DIR = Path(__file__).resolve().parent
JAVA_CASES_ROOT = (
    WORKSPACE / "JiuwenTest_3820" / "src" / "test" / "java" / "com" / "openjiuwen" / "test" / "cases"
)
PYTHON_CASES_ROOT = WORKSPACE / "JiuwenTest" / "cases"
MODULES_PATH = SCRIPTS_DIR / "modules.json"

DISABLED_RE = re.compile(r'@(?:org\.junit\.jupiter\.api\.)?Disabled\s*\(\s*"([^"]*)"')
ASSUME_RE = re.compile(r'Assumptions\.(assumeTrue|assumeFalse)')
FLOW_INVOKE_RE = re.compile(r'\b(flow|mainWorkflow|subWorkflow|sub|workflow|agent)\.(invoke|stream|run)\s*\(')
WORKFLOW_BASIC_RE = re.compile(r'invokeWorkflow|workflowBasic\.|runAgent|Agent\.')
EXEC_SINGLE_RE = re.compile(r'executeSingleComponent|ComponentExecutionHelper')
ASSERT_PYTHON_RE = re.compile(r'assertPython(Source|Case)|assertExpectedContract')
EXPECTED_STATIC_RE = re.compile(
    r'(ExpectedOutput|ExpectedFrames|expectedTraceContract|case\d+Expected|topLevelCase\d+Expected|'
    r'streamingOutput\d+Expected|EndTemplateTestSupport\.scenario|frames\(|completedState\(\)|endNodeStreamFrame)'
)
SUBWF_MAIN_RE = re.compile(r'SubWorkflowComponent\s*\(|mainWorkflow\.(invoke|stream)')
CLASS_RE = re.compile(r'^\s*(?:public\s+|private\s+|protected\s+)?class\s+(\w+)', re.MULTILINE)
PY_CASE_RE = re.compile(
    r'对齐 Python [`\'"](test_[\w/]+\.py)[`\'"]|@CaseID:\s*(test_[\w]+)|[`\'"](test_[\w]+)[`\'"]'
)

PARTIAL_TRANSLATION_CLASSES = frozenset({
    "SubWorkflowComponent007Test",
    "SubWorkflowComponent019Test",
    "SubWorkflowComponentSubFlowStreamingOutput006Test",
    "SubWorkflowComponentSubFlowEndTemplate015Test",
    "SubWorkflowComponentSubFlowEndNoTemplate003Test",
})


def load_modules():
    with MODULES_PATH.open(encoding="utf-8") as f:
        return json.load(f)


def extract_class_name(text, fallback):
    matches = CLASS_RE.findall(text)
    test_classes = [m for m in matches if m.endswith("Test") or m.startswith("Test")]
    if test_classes:
        return test_classes[-1]
    return matches[-1] if matches else fallback


def guess_python_case(text, cls_name):
    for pat in PY_CASE_RE.finditer(text):
        for g in pat.groups():
            if not g:
                continue
            val = g.replace("/", "_").replace(".py", "")
            if val.startswith("test_"):
                return val
    return re.sub(r"(?<!^)(?=[A-Z])", "_", cls_name).lower()


def should_skip_support_class(cls):
    return cls.endswith("Support") or cls.endswith("Aw") or "Mock" in cls


def detect_skip_kind(text, cls, suite_key):
    disabled = DISABLED_RE.search(text)
    has_assume = bool(ASSUME_RE.search(text))
    has_flow = bool(FLOW_INVOKE_RE.search(text) or WORKFLOW_BASIC_RE.search(text))
    has_subwf_main = bool(SUBWF_MAIN_RE.search(text))
    has_placeholder = bool(
        ASSERT_PYTHON_RE.search(text)
        or (EXPECTED_STATIC_RE.search(text) and not has_flow)
        or re.search(r'streamingOutput\d+ExpectedFrames\(\)', text)
    )

    if disabled:
        return "@Disabled", disabled.group(1)
    if has_assume:
        m = re.search(r'Assumptions\.assumeTrue\s*\(\s*[^,]+,\s*"([^"]+)"', text)
        reason = m.group(1) if m else "运行时环境变量/条件不满足"
        return "AssumptionSkip", reason

    if suite_key == "component":
        if cls in PARTIAL_TRANSLATION_CLASSES:
            return "部分翻译", "已执行 subWorkflow 但未覆盖 Python 主流程 SubWorkflowComponent 路径"
        if has_flow and not has_subwf_main and re.search(r'\bsubWorkflow\.(invoke|stream)|\bsub\.(invoke|stream)', text):
            return "部分翻译", "已执行裸 subWorkflow 但未通过 SubWorkflowComponent/main_workflow 验证"

    if has_placeholder and not has_flow and not EXEC_SINGLE_RE.search(text):
        return "占位伪通过", "仅静态契约/mock 断言，未验证真实执行行为"

    return None, ""


def discover_rows(suite_key, module_cfg):
    java_dir = JAVA_CASES_ROOT / module_cfg["java_dir"]
    if not java_dir.is_dir():
        return []

    rows = []
    for path in sorted(java_dir.rglob("*.java")):
        text = path.read_text(encoding="utf-8", errors="replace")
        cls = extract_class_name(text, path.stem)
        if should_skip_support_class(cls):
            continue

        skip_kind, reason = detect_skip_kind(text, cls, suite_key)
        if not skip_kind:
            continue

        sub_module = "/".join(path.relative_to(java_dir).parts[:-1])
        rel = str(path.as_posix()).split("JiuwenTest_3820/")[-1]
        rows.append({
            "Java文件": rel,
            "类名": cls,
            "模块": suite_key,
            "子模块": sub_module,
            "Python用例": guess_python_case(text, cls),
            "跳过类型": skip_kind,
            "跳过原因": reason,
            "优先级": "",
            "根因": "待检视",
            "测试待补项": "",
            "SDK实现证据": "",
            "分析说明": "",
            "功能缺失明细": "",
        })
    return rows


def export_module(suite_key, module_cfg, output_path=None):
    rows = discover_rows(suite_key, module_cfg)
    out = resolve_csv_path(module_cfg["output_csv"], output_path)
    with out.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        w.writeheader()
        w.writerows(rows)
    return out, rows


def main():
    modules = load_modules()
    parser = argparse.ArgumentParser(
        description="Discover skipped tests and export skeleton CSV (root_cause=待检视)"
    )
    parser.add_argument(
        "--module",
        default="component",
        help="Suite key from modules.json, or 'all'",
    )
    parser.add_argument("--output", type=Path, help="Override CSV output path (single module only)")
    parser.add_argument("--discover-only", action="store_true", help="Print candidate stats, do not write CSV")
    parser.add_argument("--list-modules", action="store_true", help="List configured suite keys")
    args = parser.parse_args()

    if args.list_modules:
        ensure_output_dir()
        for key, cfg in sorted(modules.items()):
            java_dir = JAVA_CASES_ROOT / cfg["java_dir"]
            py_dir = PYTHON_CASES_ROOT / cfg["python_dir"]
            print(f"{key:24} {cfg['label']:22} java={'Y' if java_dir.is_dir() else 'N'} python={'Y' if py_dir.is_dir() else 'N'} -> {cfg['output_csv']}")
        return

    targets = list(modules.items()) if args.module == "all" else [(args.module, modules[args.module])]
    if args.module != "all" and args.module not in modules:
        parser.error(f"Unknown module {args.module!r}. Use --list-modules.")

    ensure_output_dir()
    total = 0
    for suite_key, cfg in targets:
        if args.discover_only:
            rows = discover_rows(suite_key, cfg)
            print(f"[{suite_key}] candidates: {len(rows)} 跳过类型={dict(Counter(r['跳过类型'] for r in rows))}")
            total += len(rows)
            continue

        out, rows = export_module(suite_key, cfg, args.output if len(targets) == 1 else None)
        pending = sum(1 for r in rows if r["根因"] == "待检视")
        print(f"[{suite_key}] Wrote {len(rows)} skeleton rows -> {out}")
        print(f"  根因=待检视: {pending} (Agent 须代码检视后 merge_reviews.py 写入结论)")
        total += len(rows)

    if args.discover_only:
        print(f"Total candidates: {total}")


if __name__ == "__main__":
    main()
