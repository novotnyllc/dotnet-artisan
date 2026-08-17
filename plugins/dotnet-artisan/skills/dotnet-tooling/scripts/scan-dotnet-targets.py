#!/usr/bin/env python3
"""Scan a repository for current .NET targeting signals."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

TARGET_FRAMEWORK_RE = re.compile(
    r"<TargetFramework>\s*([^<]+?)\s*</TargetFramework>", re.IGNORECASE
)
TARGET_FRAMEWORKS_RE = re.compile(
    r"<TargetFrameworks>\s*([^<]+?)\s*</TargetFrameworks>", re.IGNORECASE
)
TARGET_FRAMEWORK_VERSION_RE = re.compile(
    r"<TargetFrameworkVersion>\s*([^<]+?)\s*</TargetFrameworkVersion>", re.IGNORECASE
)
FILE_BASED_TFM_RE = re.compile(
    r"^\s*#:\s*property\s+TargetFramework\s*=\s*([^\s]+)", re.IGNORECASE | re.MULTILINE
)
DOTNET_VERSION_RE = re.compile(
    r"dotnet-version\s*:\s*['\"]?([^'\"\n#]+)", re.IGNORECASE
)
NET_TFM_VERSION_RE = re.compile(r"^net(\d+)\.(\d+)")
SDK_VERSION_RE = re.compile(r"^(\d+)(?:\.(\d+))?")


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None


def rel_path(path: Path, root: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def add_evidence(
    store: dict[str, set[str]], value: str, file_path: Path, root: Path
) -> None:
    normalized = value.strip()
    if not normalized:
        return
    store.setdefault(normalized, set()).add(rel_path(file_path, root))


def split_tfms(raw: str) -> list[str]:
    return [item.strip() for item in raw.split(";") if item.strip()]


def collect_project_tfms(root: Path) -> dict[str, set[str]]:
    evidence: dict[str, set[str]] = {}
    patterns = [
        "**/*.csproj",
        "**/*.fsproj",
        "**/*.vbproj",
        "**/Directory.Build.props",
        "**/Directory.Build.targets",
    ]

    files: set[Path] = set()
    for pattern in patterns:
        files.update(root.glob(pattern))

    for file_path in sorted(files):
        text = read_text(file_path)
        if text is None:
            continue

        for raw in TARGET_FRAMEWORK_RE.findall(text):
            for tfm in split_tfms(raw):
                add_evidence(evidence, tfm, file_path, root)

        for raw in TARGET_FRAMEWORKS_RE.findall(text):
            for tfm in split_tfms(raw):
                add_evidence(evidence, tfm, file_path, root)

        for raw in TARGET_FRAMEWORK_VERSION_RE.findall(text):
            add_evidence(evidence, raw, file_path, root)

    return evidence


def collect_file_based_tfms(root: Path) -> dict[str, set[str]]:
    evidence: dict[str, set[str]] = {}
    for file_path in sorted(root.glob("**/*.cs")):
        text = read_text(file_path)
        if text is None:
            continue
        for match in FILE_BASED_TFM_RE.findall(text):
            add_evidence(evidence, match, file_path, root)
    return evidence


def collect_workflow_dotnet_versions(root: Path) -> dict[str, set[str]]:
    evidence: dict[str, set[str]] = {}
    workflows_dir = root / ".github" / "workflows"
    if not workflows_dir.is_dir():
        return evidence

    files = list(workflows_dir.glob("*.yml")) + list(workflows_dir.glob("*.yaml"))
    for file_path in sorted(files):
        text = read_text(file_path)
        if text is None:
            continue
        for match in DOTNET_VERSION_RE.findall(text):
            add_evidence(evidence, match, file_path, root)
    return evidence


def read_global_json_sdk(root: Path) -> tuple[str | None, str | None]:
    file_path = root / "global.json"
    if not file_path.is_file():
        return None, None

    text = read_text(file_path)
    if text is None:
        return None, rel_path(file_path, root)

    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return None, rel_path(file_path, root)

    sdk = data.get("sdk")
    if isinstance(sdk, dict):
        version = sdk.get("version")
        if isinstance(version, str) and version.strip():
            return version.strip(), rel_path(file_path, root)

    return None, rel_path(file_path, root)


def tfm_sort_key(tfm: str) -> tuple[int, int, str]:
    match = NET_TFM_VERSION_RE.match(tfm.lower())
    if match:
        return int(match.group(1)), int(match.group(2)), tfm
    return -1, -1, tfm


def sdk_to_tfm(sdk_version: str) -> str | None:
    match = SDK_VERSION_RE.match(sdk_version.strip())
    if not match:
        return None
    major = match.group(1)
    minor = match.group(2) or "0"
    return f"net{major}.{minor}"


def infer_current_target(
    project_tfms: dict[str, set[str]],
    file_tfms: dict[str, set[str]],
    global_sdk_version: str | None,
    workflow_versions: dict[str, set[str]],
) -> tuple[str | None, str]:
    explicit = sorted({*project_tfms.keys(), *file_tfms.keys()}, key=tfm_sort_key)
    explicit = [tfm for tfm in explicit if NET_TFM_VERSION_RE.match(tfm.lower())]
    if explicit:
        return explicit[-1], "explicit_target_framework"

    if global_sdk_version:
        inferred = sdk_to_tfm(global_sdk_version)
        if inferred:
            return inferred, "global_json_sdk"

    inferred_from_workflow = sorted(
        {
            tfm
            for version in workflow_versions.keys()
            for tfm in [sdk_to_tfm(version)]
            if tfm is not None
        },
        key=tfm_sort_key,
    )
    if inferred_from_workflow:
        return inferred_from_workflow[-1], "workflow_dotnet_version"

    return None, "none"


def to_serializable_map(values: dict[str, set[str]]) -> dict[str, list[str]]:
    return {key: sorted(paths) for key, paths in sorted(values.items(), key=lambda x: x[0])}


def print_map(title: str, values: dict[str, set[str]]) -> None:
    print(f"{title}:")
    if not values:
        print("  (none)")
        return
    for item in sorted(values.keys(), key=tfm_sort_key):
        print(f"  - {item}")
        for path in sorted(values[item]):
            print(f"      {path}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Scan the repository for current .NET target framework and SDK signals."
    )
    parser.add_argument(
        "--root",
        default=".",
        help="Repository root to scan (default: current directory).",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit JSON output instead of a human-readable report.",
    )
    args = parser.parse_args()

    root = Path(args.root).resolve()
    if not root.is_dir():
        print(f"ERROR: Not a directory: {root}", file=sys.stderr)
        return 2

    project_tfms = collect_project_tfms(root)
    file_based_tfms = collect_file_based_tfms(root)
    workflow_versions = collect_workflow_dotnet_versions(root)
    global_sdk_version, global_json_path = read_global_json_sdk(root)
    inferred_target, inference_source = infer_current_target(
        project_tfms, file_based_tfms, global_sdk_version, workflow_versions
    )

    report = {
        "repo_root": str(root),
        "project_target_frameworks": to_serializable_map(project_tfms),
        "file_based_target_frameworks": to_serializable_map(file_based_tfms),
        "global_json": {
            "path": global_json_path,
            "sdk_version": global_sdk_version,
        },
        "workflow_dotnet_versions": to_serializable_map(workflow_versions),
        "inferred_current_target": inferred_target,
        "inference_source": inference_source,
    }

    if args.json:
        print(json.dumps(report, indent=2))
        return 0

    print(f"Repository: {root}")
    print_map("Project target frameworks", project_tfms)
    print_map("File-based target frameworks", file_based_tfms)
    if global_json_path:
        if global_sdk_version:
            print(f"global.json SDK: {global_sdk_version} ({global_json_path})")
        else:
            print(f"global.json SDK: (not found/parseable) ({global_json_path})")
    else:
        print("global.json SDK: (none)")
    print_map("Workflow dotnet-version values", workflow_versions)
    if inferred_target:
        print(f"Inferred current target: {inferred_target} ({inference_source})")
    else:
        print("Inferred current target: (none)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
