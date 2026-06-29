#!/usr/bin/env python3
"""
convert_example.py — agent-core-java 示例双向转换工具

支持两种转换方向:
  1. standalone → inline :  agent-core-java-examples/<name>  →  agent-core-java/examples/<name>
  2. inline → standalone :  agent-core-java/examples/<name>   →  agent-core-java-examples/<name>

用法:
  python convert_example.py <example_name> [--direction standalone-to-inline|inline-to-standalone] [--repo-root <path>] [--dry-run] [--verify]

示例:
  python convert_example.py sandbox --direction standalone-to-inline --verify
  python convert_example.py sandbox --direction inline-to-standalone --dry-run
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import textwrap
from pathlib import Path

REPO_ROOT_DEFAULT = Path(__file__).resolve().parent.parent.parent.parent.parent

STANDALONE_ROOT = "agent-core-java-examples"
INLINE_ROOT = "agent-core-java/examples"


def find_repo_root(explicit: str | None) -> Path:
    if explicit:
        p = Path(explicit).resolve()
        assert p.exists(), f"指定的 repo-root 不存在: {p}"
        return p
    r = REPO_ROOT_DEFAULT
    if (r / STANDALONE_ROOT).exists() and (r / INLINE_ROOT).exists():
        return r
    cwd = Path.cwd()
    for candidate in [cwd, *cwd.parents]:
        if (candidate / STANDALONE_ROOT).exists() and (candidate / INLINE_ROOT).exists():
            return candidate
    print(f"ERROR: 无法定位仓库根目录 (需包含 {STANDALONE_ROOT} 和 {INLINE_ROOT})")
    sys.exit(1)


def collect_standalone_files(name: str, repo_root: Path) -> dict:
    src_dir = repo_root / STANDALONE_ROOT / name
    assert src_dir.exists(), f"standalone 示例目录不存在: {src_dir}"

    files = {}

    java_dir = src_dir / "src" / "main" / "java"
    if java_dir.exists():
        for f in java_dir.rglob("*.java"):
            files[str(f.relative_to(src_dir))] = f

    resources_dir = src_dir / "src" / "main" / "resources"
    if resources_dir.exists():
        for f in resources_dir.rglob("*"):
            if f.is_file():
                files[str(f.relative_to(src_dir))] = f

    examples_dir = src_dir / "examples"
    if examples_dir.exists():
        for f in examples_dir.rglob("*"):
            if f.is_file():
                files[str(f.relative_to(src_dir))] = f

    for f in src_dir.rglob("*.md"):
        if f.is_file() and f.parent.name != "target":
            files[str(f.relative_to(src_dir))] = f

    pom = src_dir / "pom.xml"
    if pom.exists():
        files["pom.xml"] = pom

    return files


def collect_inline_files(name: str, repo_root: Path) -> dict:
    src_dir = repo_root / INLINE_ROOT / name
    assert src_dir.exists(), f"inline 示例目录不存在: {src_dir}"

    files = {}

    for f in src_dir.rglob("*.java"):
        if f.is_file() and f.parent.name not in ("build", "args"):
            files[str(f.relative_to(src_dir))] = f

    for f in src_dir.rglob("*.md"):
        if f.is_file() and f.parent.name not in ("build", "logs", "args"):
            files[str(f.relative_to(src_dir))] = f

    for f in src_dir.rglob("*.ps1"):
        if f.is_file():
            files[str(f.relative_to(src_dir))] = f

    skills_dir = src_dir / "skills"
    if skills_dir.exists():
        for f in skills_dir.rglob("*"):
            if f.is_file():
                files[str(f.relative_to(src_dir))] = f

    data_dir = src_dir / "data"
    if data_dir.exists():
        for f in data_dir.rglob("*"):
            if f.is_file():
                files[str(f.relative_to(src_dir))] = f

    return files


def _find_method_block(content: str, method_sig: str) -> tuple[int, int] | None:
    idx = content.find(method_sig)
    if idx == -1:
        return None
    depth = 0
    start = idx
    i = content.find("{", idx)
    if i == -1:
        return None
    depth = 1
    i += 1
    while i < len(content) and depth > 0:
        if content[i] == "{":
            depth += 1
        elif content[i] == "}":
            depth -= 1
        i += 1
    return start, i


def transform_java_standalone_to_inline(content: str, name: str) -> str:
    result = content

    result = re.sub(
        r'private static final String SANDBOX_URL = "http://127\.0\.0\.1:8321";',
        'private static final String SANDBOX_URL = resolveStringConfig("SANDBOX_URL", "http://127.0.0.1:8321");',
        result,
    )

    sig = "private static Path resolveModuleDir() {"
    block = _find_method_block(result, sig)
    if block:
        start, end = block
        original_block = result[start:end]
        lines = original_block.split("\n")
        has_agent_core_java_examples = any("agent-core-java-examples" in l for l in lines)
        if has_agent_core_java_examples:
            new_block = """\
    private static Path resolveModuleDir() {
        Path cwd = Path.of("").toAbsolutePath();
        if (Files.exists(cwd.resolve("pom.xml"))) {
            return cwd;
        }
        Path parent = cwd.getParent();
        if (parent != null && Files.exists(parent.resolve("pom.xml"))) {
            return parent;
        }
        Path grandparent = (parent != null) ? parent.getParent() : null;
        if (grandparent != null && Files.exists(grandparent.resolve("pom.xml"))) {
            return grandparent;
        }
        return cwd;
    }"""
            result = result[:start] + new_block + result[end:]

    return result


def transform_java_inline_to_standalone(content: str, name: str) -> str:
    result = content

    result = re.sub(
        r'private static final String SANDBOX_URL = resolveStringConfig\("SANDBOX_URL", "http://127\.0\.0\.1:8321"\);',
        'private static final String SANDBOX_URL = "http://127.0.0.1:8321";',
        result,
    )

    sig = "private static Path resolveModuleDir() {"
    block = _find_method_block(result, sig)
    if block:
        start, end = block
        original_block = result[start:end]
        lines = original_block.split("\n")
        has_parent_grandparent = any("parent" in l for l in lines)
        if has_parent_grandparent:
            new_block = f"""\
    private static Path resolveModuleDir() {{
        Path cwd = Path.of("").toAbsolutePath();
        if (Files.exists(cwd.resolve("pom.xml"))) {{
            return cwd;
        }}
        Path moduleDir = cwd.resolve("agent-core-java-examples").resolve("{name}");
        if (Files.exists(moduleDir.resolve("pom.xml"))) {{
            return moduleDir;
        }}
        return cwd;
    }}"""
            result = result[:start] + new_block + result[end:]

    return result


def generate_run_ps1(name: str, package: str, class_name: str) -> str:
    return textwrap.dedent(f'''\
        # {class_name} 编译运行脚本
        # 所有产物放在当前示例目录或子目录下

        $ErrorActionPreference = "Continue"

        # 修复中文乱码：保持系统默认编码（中文 Windows 为 GBK/CP936）
        # 不要使用 chcp 65001，PowerShell 5 中会导致双重编码产生"锟斤拷"乱码
        # javac/java/mvn 在中文 Windows 上默认输出 GBK，与控制台编码一致

        $EXAMPLE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
        if (-not $EXAMPLE_DIR) {{ $EXAMPLE_DIR = $PWD.Path }}
        $PROJECT_ROOT = (Resolve-Path (Join-Path $EXAMPLE_DIR "..\\..")).Path
        $BUILD_DIR = Join-Path $EXAMPLE_DIR "build"
        $LOG_DIR = Join-Path $EXAMPLE_DIR "logs"
        $ARG_DIR = Join-Path $EXAMPLE_DIR "args"

        # 1. 编译主项目（获取依赖 jar）
        Write-Host "[1/4] Compiling agent-core-java project..." -ForegroundColor Cyan
        Push-Location $PROJECT_ROOT
        try {{
            mvn compile -DskipTests 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {{
                Write-Host "ERROR: Maven compile failed. Run 'mvn compile -DskipTests' manually." -ForegroundColor Red
                exit 1
            }}
        }} finally {{
            Pop-Location
        }}

        # 2. 构建编译 classpath
        Write-Host "[2/4] Building classpath..." -ForegroundColor Cyan
        $DEP_DIR = Join-Path $PROJECT_ROOT "target\\dependency"

        if (-not (Test-Path $DEP_DIR)) {{
            Push-Location $PROJECT_ROOT
            mvn dependency:copy-dependencies -DoutputDirectory=target/dependency -DskipTests -q 2>&1 | Out-Null
            Pop-Location
        }}

        $CLASSES_DIR = Join-Path $PROJECT_ROOT "target\\classes"
        $DEP_JARS = (Get-ChildItem -Path $DEP_DIR -Filter "*.jar").FullName
        $CP_COMPILE = @($CLASSES_DIR) + $DEP_JARS -join ";"

        New-Item -ItemType Directory -Path $BUILD_DIR -Force | Out-Null
        New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
        New-Item -ItemType Directory -Path $ARG_DIR -Force | Out-Null

        # 3. 编译示例（用 @argfile 避免命令行过长）
        Write-Host "[3/4] Compiling {class_name}..." -ForegroundColor Cyan
        $EXAMPLE_SRC = Join-Path $EXAMPLE_DIR "{class_name}.java"
        $UTILS_SRC = Join-Path $PROJECT_ROOT "examples\\utils\\SharedExampleApiConfigLoader.java"
        $COMPILE_ARG = Join-Path $ARG_DIR "compile.args"

        @(
            "-source 17",
            "-target 17",
            "-encoding UTF-8",
            "-cp",
            $CP_COMPILE,
            "-d",
            $BUILD_DIR,
            "-proc:none",
            $EXAMPLE_SRC,
            $UTILS_SRC
        ) | Set-Content $COMPILE_ARG

        javac "@$COMPILE_ARG" 2>&1 | Tee-Object -FilePath (Join-Path $LOG_DIR "compile.log")

        if ($LASTEXITCODE -ne 0) {{
            Write-Host "ERROR: Example compilation failed. Check logs/compile.log" -ForegroundColor Red
            exit 1
        }}
        Write-Host "  Compilation successful." -ForegroundColor Green

        # 4. 运行示例（用 @argfile 避免命令行过长）
        Write-Host "[4/4] Running {class_name}..." -ForegroundColor Cyan
        $CP_RUNTIME = @($BUILD_DIR) + @($CLASSES_DIR) + $DEP_JARS -join ";"
        $RUN_ARG = Join-Path $ARG_DIR "run.args"

        @(
            "-cp",
            $CP_RUNTIME,
            "{package}.{class_name}"
        ) | Set-Content $RUN_ARG

        $API_CONFIG = Join-Path $EXAMPLE_DIR "..\\apiconfig.json"
        $env:OPENJIUWEN_API_CONFIG = (Resolve-Path $API_CONFIG).Path

        Push-Location $EXAMPLE_DIR
        try {{
            java "@$RUN_ARG" 2>&1 | Tee-Object -FilePath (Join-Path $LOG_DIR "run.log")
            if ($LASTEXITCODE -ne 0) {{
                Write-Host "ERROR: Example run failed. Check logs/run.log" -ForegroundColor Red
                exit 1
            }}
        }} finally {{
            Pop-Location
            Remove-Item Env:OPENJIUWEN_API_CONFIG
        }}

        Write-Host ""
        Write-Host "=== Run Complete ===" -ForegroundColor Green
        Write-Host "  Build output: $BUILD_DIR"
        Write-Host "  Logs:         $LOG_DIR"
    ''')


def generate_pom_xml(name: str, main_class: str) -> str:
    package_path = main_class.replace(".java", "").replace("/", ".")
    package_name = package_path.rsplit(".", 1)[0] if "." in package_path else package_path
    return textwrap.dedent(f'''\
        <?xml version="1.0" encoding="UTF-8"?>
        <project xmlns="http://maven.apache.org/POM/4.0.0"
                 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                 xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
                 http://maven.apache.org/xsd/maven-4.0.0.xsd">
            <modelVersion>4.0.0</modelVersion>

            <parent>
                <groupId>com.openjiuwen</groupId>
                <artifactId>agent-core-java-examples</artifactId>
                <version>0.1.12</version>
            </parent>

            <groupId>com.openjiuwen</groupId>
            <artifactId>example-{name}</artifactId>
            <version>0.1.12</version>

            <name>example-{name}</name>
            <description>{name} example module</description>

            <dependencies>
                <dependency>
                    <groupId>com.openjiuwen</groupId>
                    <artifactId>agent-core-java</artifactId>
                </dependency>
                <dependency>
                    <groupId>com.openjiuwen</groupId>
                    <artifactId>example-utils</artifactId>
                </dependency>
                <dependency>
                    <groupId>com.fasterxml.jackson.core</groupId>
                    <artifactId>jackson-databind</artifactId>
                </dependency>
                <dependency>
                    <groupId>ch.qos.logback</groupId>
                    <artifactId>logback-classic</artifactId>
                </dependency>
            </dependencies>
        </project>
    ''')


def find_main_java(files: dict) -> str | None:
    for relpath in files:
        if relpath.startswith("src/main/java/") and relpath.endswith(".java"):
            return relpath
    for relpath in files:
        if relpath.endswith(".java") and "Support" not in relpath and "Utils" not in relpath:
            return relpath
    return None


def extract_package_and_class(main_java_relpath: str) -> tuple[str, str]:
    normalized = main_java_relpath.replace("\\", "/")
    java_path = normalized.replace("src/main/java/", "")
    parts = java_path.replace(".java", "").split("/")
    class_name = parts[-1]
    package = ".".join(parts[:-1])
    return package, class_name


def do_standalone_to_inline(name: str, repo_root: Path, dry_run: bool) -> list[str]:
    src_dir = repo_root / STANDALONE_ROOT / name
    dst_dir = repo_root / INLINE_ROOT / name

    files = collect_standalone_files(name, repo_root)
    created = []

    main_java = find_main_java(files)
    if not main_java:
        print(f"ERROR: 未找到主 Java 文件 in {src_dir}")
        sys.exit(1)

    package, class_name = extract_package_and_class(main_java)

    if dry_run:
        print(f"[DRY-RUN] standalone → inline: {name}")
        print(f"  源: {src_dir}")
        print(f"  目标: {dst_dir}")
        print(f"  主类: {package}.{class_name}")
        print(f"  文件数: {len(files)}")
        return []

    os.makedirs(dst_dir, exist_ok=True)

    java_src = files[main_java]
    java_content = java_src.read_text(encoding="utf-8")
    java_content = transform_java_standalone_to_inline(java_content, name)
    dst_java = dst_dir / f"{class_name}.java"
    dst_java.write_text(java_content, encoding="utf-8")
    created.append(str(dst_java))

    examples_dir = src_dir / "examples"
    if examples_dir.exists():
        dst_skills = dst_dir / "skills"
        for skill_md in examples_dir.rglob("SKILL.md"):
            skill_parent = skill_md.parent
            for candidate in skill_parent.parents:
                if candidate.name == "skills":
                    skill_name = skill_parent.relative_to(candidate)
                    break
            else:
                skill_name = skill_parent.relative_to(examples_dir)
            target_dir = dst_skills / skill_name
            os.makedirs(target_dir, exist_ok=True)
            shutil.copy2(skill_md, target_dir / "SKILL.md")
            created.append(str(target_dir / "SKILL.md"))

    resources_dir = src_dir / "src" / "main" / "resources"
    if resources_dir.exists():
        for f in resources_dir.rglob("*"):
            if f.is_file() and f.name not in ("apiconfig.json", "apiconfig_example.json"):
                target = dst_dir / "data" / f.relative_to(resources_dir)
                os.makedirs(target.parent, exist_ok=True)
                shutil.copy2(f, target)
                created.append(str(target))

    run_ps1_content = generate_run_ps1(name, package, class_name)
    dst_run = dst_dir / "run.ps1"
    dst_run.write_text(run_ps1_content, encoding="utf-8")
    created.append(str(dst_run))

    print(f"standalone → inline 完成: {name}")
    print(f"  目标: {dst_dir}")
    print(f"  创建文件: {len(created)}")
    for f in created:
        print(f"    {f}")

    return created


def do_inline_to_standalone(name: str, repo_root: Path, dry_run: bool) -> list[str]:
    src_dir = repo_root / INLINE_ROOT / name
    dst_dir = repo_root / STANDALONE_ROOT / name

    files = collect_inline_files(name, repo_root)
    created = []

    main_java_relpath = None
    for relpath in files:
        if relpath.endswith(".java") and "Support" not in relpath and "Utils" not in Path(relpath).stem:
            main_java_relpath = relpath
            break

    if not main_java_relpath:
        print(f"ERROR: 未找到主 Java 文件 in {src_dir}")
        sys.exit(1)

    class_name = Path(main_java_relpath).stem
    package = f"examples.{name}"

    if dry_run:
        print(f"[DRY-RUN] inline → standalone: {name}")
        print(f"  源: {src_dir}")
        print(f"  目标: {dst_dir}")
        print(f"  主类: {package}.{class_name}")
        print(f"  文件数: {len(files)}")
        return []

    java_dst_dir = dst_dir / "src" / "main" / "java" / "examples" / name.replace("-", "_")
    os.makedirs(java_dst_dir, exist_ok=True)

    java_src = files[main_java_relpath]
    java_content = java_src.read_text(encoding="utf-8")
    java_content = transform_java_inline_to_standalone(java_content, name.replace("-", "_"))
    dst_java = java_dst_dir / f"{class_name}.java"
    dst_java.write_text(java_content, encoding="utf-8")
    created.append(str(dst_java))

    src_skills = src_dir / "skills"
    if src_skills.exists():
        dst_examples = dst_dir / "examples" / name.replace("-", "_") / "skills"
        for skill_md in src_skills.rglob("SKILL.md"):
            skill_parent = skill_md.parent
            relative = skill_parent.relative_to(src_skills)
            target_dir = dst_examples / relative
            os.makedirs(target_dir, exist_ok=True)
            shutil.copy2(skill_md, target_dir / "SKILL.md")
            created.append(str(target_dir / "SKILL.md"))

    src_data = src_dir / "data"
    if src_data.exists():
        dst_resources = dst_dir / "src" / "main" / "resources" / "data"
        os.makedirs(dst_resources, exist_ok=True)
        for f in src_data.rglob("*"):
            if f.is_file():
                shutil.copy2(f, dst_resources / f.name)
                created.append(str(dst_resources / f.name))

    pom_content = generate_pom_xml(name.replace("-", "_"), f"examples/{name.replace('-', '_')}/{class_name}.java")
    dst_pom = dst_dir / "pom.xml"
    dst_pom.write_text(pom_content, encoding="utf-8")
    created.append(str(dst_pom))

    print(f"inline → standalone 完成: {name}")
    print(f"  目标: {dst_dir}")
    print(f"  创建文件: {len(created)}")
    for f in created:
        print(f"    {f}")

    return created


def verify_inline(name: str, repo_root: Path) -> bool:
    dst_dir = repo_root / INLINE_ROOT / name
    run_ps1 = dst_dir / "run.ps1"
    if not run_ps1.exists():
        print(f"ERROR: run.ps1 不存在: {run_ps1}")
        return False

    print(f"验证 inline 示例: {name}")
    print(f"  运行 run.ps1 ...")

    result = subprocess.run(
        ["powershell", "-ExecutionPolicy", "Bypass", "-File", str(run_ps1)],
        cwd=str(repo_root),
        capture_output=True,
        text=True,
        timeout=300,
    )

    compile_log = dst_dir / "logs" / "compile.log"
    if compile_log.exists():
        compile_content = compile_log.read_text(encoding="utf-8", errors="replace")
        if "error" in compile_content.lower():
            print(f"  编译有错误，详见: {compile_log}")
            print(compile_content[:500])
            return False

    if result.returncode == 0:
        print(f"  ✅ 验证成功 (exit code=0)")
        return True
    else:
        run_log = dst_dir / "logs" / "run.log"
        print(f"  ❌ 运行失败 (exit code={result.returncode})")
        if run_log.exists():
            print(f"  详见: {run_log}")
        return False


def verify_standalone(name: str, repo_root: Path) -> bool:
    dst_dir = repo_root / STANDALONE_ROOT / name
    pom = dst_dir / "pom.xml"
    if not pom.exists():
        print(f"ERROR: pom.xml 不存在: {pom}")
        return False

    print(f"验证 standalone 示例: {name}")
    print(f"  mvn compile ...")

    result = subprocess.run(
        ["mvn", "compile", "-DskipTests", "-f", str(pom)],
        cwd=str(repo_root),
        capture_output=True,
        text=True,
        timeout=120,
    )

    if result.returncode == 0:
        print(f"  ✅ Maven 编译成功 (exit code=0)")
        return True
    else:
        print(f"  ❌ Maven 编译失败 (exit code={result.returncode})")
        print(result.stdout[-500:] if result.stdout else "")
        print(result.stderr[-500:] if result.stderr else "")
        return False


def main():
    parser = argparse.ArgumentParser(description="agent-core-java 示例双向转换工具")
    parser.add_argument("name", help="示例名称 (如 sandbox, skill_hot_reload)")
    parser.add_argument(
        "--direction",
        choices=["standalone-to-inline", "inline-to-standalone"],
        default="standalone-to-inline",
        help="转换方向",
    )
    parser.add_argument("--repo-root", default=None, help="仓库根目录 (自动检测)")
    parser.add_argument("--dry-run", action="store_true", help="只显示计划，不执行")
    parser.add_argument("--verify", action="store_true", help="转换后验证 (编译+运行)")
    parser.add_argument("--verify-only", action="store_true", help="只验证已有示例，不执行转换")

    args = parser.parse_args()
    repo_root = find_repo_root(args.repo_root)

    if args.verify_only:
        if args.direction == "standalone-to-inline":
            ok = verify_inline(args.name, repo_root)
        else:
            ok = verify_standalone(args.name, repo_root)
        sys.exit(0 if ok else 1)

    if args.direction == "standalone-to-inline":
        created = do_standalone_to_inline(args.name, repo_root, args.dry_run)
        if args.verify and created:
            ok = verify_inline(args.name, repo_root)
            if not ok:
                sys.exit(1)
    else:
        created = do_inline_to_standalone(args.name, repo_root, args.dry_run)
        if args.verify and created:
            ok = verify_standalone(args.name, repo_root)
            if not ok:
                sys.exit(1)


if __name__ == "__main__":
    main()
