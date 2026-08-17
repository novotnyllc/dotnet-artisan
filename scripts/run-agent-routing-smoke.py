#!/usr/bin/env python3
"""Cross-provider agent-routing smoke test orchestrator.

Runs offline (no CLI invocations) structural verification for each
provider to confirm the flat skill layout is discoverable.  For live
CLI tests, use test.sh which delegates to check-skills.cs.

This script validates:
  - Claude Code: plugin.json skill paths resolve, expected skill count
  - Codex:       plugin manifest + marketplace are consistent, with optional legacy openai.yaml compatibility
  - Copilot:     plugin.json paths resolve, SKILL.md frontmatter + license valid

The expected skill count is derived from plugin.json at runtime to avoid
hard-coded constants that drift when skills are consolidated or added.

Exit codes:
    0 - All structural checks pass
    1 - One or more checks failed
    2 - Usage error

Usage:
    python scripts/run-agent-routing-smoke.py
    python scripts/run-agent-routing-smoke.py --provider claude
    python scripts/run-agent-routing-smoke.py --provider codex
    python scripts/run-agent-routing-smoke.py --provider copilot
    python scripts/run-agent-routing-smoke.py --provider claude,codex,copilot
"""

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PLUGIN_ROOT = REPO_ROOT / "plugins" / "dotnet-artisan"
SKILLS_DIR = PLUGIN_ROOT / "skills"
PLUGIN_JSON = PLUGIN_ROOT / ".claude-plugin" / "plugin.json"
CODEX_MANIFEST = PLUGIN_ROOT / ".codex-plugin" / "plugin.json"
CODEX_MARKETPLACE = REPO_ROOT / ".agents" / "plugins" / "marketplace.json"
OPENAI_YAML = PLUGIN_ROOT / ".agents" / "openai.yaml"


def get_expected_skill_count() -> int:
    """Derive expected skill count from plugin.json to avoid hard-coded drift.

    Falls back to counting skill directories if plugin.json is missing.
    """
    if PLUGIN_JSON.exists():
        with open(PLUGIN_JSON) as f:
            plugin = json.load(f)
        return len(plugin.get("skills", []))
    # Fallback: count skill directories directly
    if SKILLS_DIR.is_dir():
        return len([d for d in SKILLS_DIR.iterdir() if d.is_dir() and (d / "SKILL.md").exists()])
    return 0

# Frontmatter required fields for every SKILL.md (per repo policy in AGENTS.md)
REQUIRED_FRONTMATTER = {"name", "description", "license", "user-invocable"}

# Codex per-skill metadata expectations.
SKILL_OPENAI_RELATIVE = Path("agents") / "openai.yaml"


def load_plugin_json() -> dict:
    with open(PLUGIN_JSON) as f:
        return json.load(f)


def discover_skill_dirs() -> list[Path]:
    """Find all skill directories (flat layout: skills/<name>/SKILL.md)."""
    if not SKILLS_DIR.is_dir():
        return []
    dirs = []
    for child in sorted(SKILLS_DIR.iterdir()):
        if child.is_dir() and (child / "SKILL.md").exists():
            dirs.append(child)
    return dirs


def parse_frontmatter(skill_md_path: Path) -> dict | None:
    """Parse YAML frontmatter from a SKILL.md file (simple key: value parser).

    Normalizes CRLF to LF before parsing to handle Windows-edited files.
    """
    content = skill_md_path.read_text(encoding="utf-8")
    # Normalize CRLF -> LF (pitfall: Windows line endings break exact string matching)
    content = content.replace("\r\n", "\n").replace("\r", "\n")
    # Frontmatter is between --- delimiters
    match = re.match(r"^---\s*\n(.*?)\n---", content, re.DOTALL)
    if not match:
        return None
    fm = {}
    for line in match.group(1).splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" in line:
            key, _, value = line.partition(":")
            fm[key.strip()] = value.strip().strip("'\"")
    return fm


def parse_openai_yaml_field(yaml_text: str, field_name: str) -> str | None:
    """Extract a scalar field value from openai.yaml by key name.

    This parser is intentionally minimal and dependency-free. It supports
    quoted and unquoted scalar values on a single line.
    """
    match = re.search(
        rf"(?m)^[ \t]*{re.escape(field_name)}[ \t]*:[ \t]*(.+?)[ \t]*$",
        yaml_text,
    )
    if not match:
        return None

    raw = match.group(1).strip()
    if raw.startswith('"') and raw.endswith('"') and len(raw) >= 2:
        return raw[1:-1]
    if raw.startswith("'") and raw.endswith("'") and len(raw) >= 2:
        return raw[1:-1]
    return raw


def resolve_skill_path(skill_path_str: str) -> Path | None:
    """Resolve a skill path from plugin.json, rejecting unsafe values.

    Rejects absolute paths and traversal (.. segments).
    Returns the resolved full path under PLUGIN_ROOT, or None if invalid.
    """
    p = Path(skill_path_str)

    if p.is_absolute():
        return None

    if ".." in p.parts:
        return None

    full = (PLUGIN_ROOT / p).resolve(strict=False)

    # Ensure it stays under the plugin root
    try:
        full.relative_to(PLUGIN_ROOT.resolve())
    except ValueError:
        return None

    return full


def resolve_repo_path(path_str: str) -> Path | None:
    """Resolve a marketplace path from repository root, rejecting unsafe values."""
    p = Path(path_str)

    if p.is_absolute():
        return None

    if ".." in p.parts:
        return None

    full = (REPO_ROOT / p).resolve(strict=False)

    try:
        full.relative_to(REPO_ROOT.resolve())
    except ValueError:
        return None

    return full


def extract_skill_path(entry: str | dict) -> str | None:
    """Extract skill path string from a plugin.json entry.

    Returns None for unrecognized types or missing/empty paths.
    """
    if isinstance(entry, str):
        return entry if entry.strip() else None
    if isinstance(entry, dict):
        path = entry.get("path", "")
        return path if path and path.strip() else None
    return None


def validate_plugin_paths(plugin: dict, errors: list[str]) -> None:
    """Validate that all plugin.json skill paths resolve to existing skill directories.

    Checks: path validity, existence, is_dir, contains SKILL.md, and uniqueness.
    """
    skills_list = plugin.get("skills", [])
    if not skills_list:
        errors.append("plugin.json has empty 'skills' array")
        return

    missing_paths = []
    bad_paths = []
    not_dirs = []
    no_skill_md = []
    seen_paths: set[str] = set()
    duplicates = []

    for entry in skills_list:
        skill_path = extract_skill_path(entry)
        if skill_path is None:
            bad_paths.append(repr(entry))
            continue

        # Uniqueness check (normalize to canonical form)
        canonical = str(Path(skill_path))
        if canonical in seen_paths:
            duplicates.append(skill_path)
            continue
        seen_paths.add(canonical)

        full = resolve_skill_path(skill_path)
        if full is None:
            bad_paths.append(skill_path)
        elif not full.exists():
            missing_paths.append(skill_path)
        elif not full.is_dir():
            not_dirs.append(skill_path)
        elif not (full / "SKILL.md").is_file():
            no_skill_md.append(skill_path)

    if bad_paths:
        errors.append(
            f"{len(bad_paths)} plugin.json skill entry/path(s) are invalid "
            f"(missing, empty, absolute, or traversal): {bad_paths[:5]}{'...' if len(bad_paths) > 5 else ''}"
        )

    if duplicates:
        errors.append(
            f"{len(duplicates)} duplicate plugin.json skill path(s): "
            f"{duplicates[:5]}{'...' if len(duplicates) > 5 else ''}"
        )

    if missing_paths:
        errors.append(
            f"{len(missing_paths)} plugin.json skill path(s) do not resolve: "
            f"{missing_paths[:5]}{'...' if len(missing_paths) > 5 else ''}"
        )

    if not_dirs:
        errors.append(
            f"{len(not_dirs)} plugin.json skill path(s) are not directories: "
            f"{not_dirs[:5]}{'...' if len(not_dirs) > 5 else ''}"
        )

    if no_skill_md:
        errors.append(
            f"{len(no_skill_md)} plugin.json skill path(s) missing SKILL.md: "
            f"{no_skill_md[:5]}{'...' if len(no_skill_md) > 5 else ''}"
        )


def check_claude(skill_dirs: list[Path]) -> list[str]:
    """Verify Claude Code structural requirements.

    - plugin.json exists and lists skill paths
    - All listed paths resolve to existing directories
    - Skill count in plugin.json matches discovered skill directories
    Note: [skill:name] cross-ref validation is handled by validate-skills.sh.
    """
    errors: list[str] = []

    if not PLUGIN_JSON.exists():
        errors.append(f"plugin.json not found at {PLUGIN_JSON}")
        return errors

    plugin = load_plugin_json()
    skills_list = plugin.get("skills", [])

    # Verify plugin.json skill count matches discovered directories
    if len(skills_list) != len(skill_dirs):
        errors.append(
            f"plugin.json lists {len(skills_list)} skills but {len(skill_dirs)} "
            f"skill directories found on disk"
        )

    # Verify paths resolve (shared validation)
    validate_plugin_paths(plugin, errors)

    return errors


def check_codex(skill_dirs: list[Path]) -> list[str]:
    """Verify Codex structural requirements.

    - Flat layout: skill dirs at skills/<name>/ (depth 1, not depth 2)
    - Each has SKILL.md
    - .codex-plugin/plugin.json exists and matches core Claude manifest metadata
    - legacy .agents/plugins/marketplace.json, if present, resolves to a Codex plugin root
    - Legacy .agents/openai.yaml metadata is only validated when present
    - Skill directory count matches plugin.json
    """
    errors: list[str] = []

    if not SKILLS_DIR.is_dir():
        errors.append(f"skills/ directory not found at {SKILLS_DIR}")
        return errors

    # Skill count verification: directories must match plugin.json
    expected = get_expected_skill_count()
    if expected > 0 and len(skill_dirs) != expected:
        errors.append(
            f"Found {len(skill_dirs)} skill directories, expected {expected} "
            f"(derived from plugin.json)"
        )

    # Verify flat layout (no category subdirectories with skills)
    for child in sorted(SKILLS_DIR.iterdir()):
        if child.is_dir() and not (child / "SKILL.md").exists():
            # Check if it has subdirectories with SKILL.md (nested layout remnant)
            nested = list(child.glob("*/SKILL.md"))
            if nested:
                errors.append(
                    f"Nested skill layout detected under {child.name}/: "
                    f"{[p.parent.name for p in nested[:3]]}"
                )

    if not CODEX_MANIFEST.exists():
        errors.append(f"Codex manifest not found at {CODEX_MANIFEST}")
        codex_manifest = None
    else:
        try:
            codex_manifest = json.loads(CODEX_MANIFEST.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errors.append(f"Codex manifest is not valid JSON: {exc}")
            codex_manifest = None

    claude_manifest = load_plugin_json() if PLUGIN_JSON.exists() else {}

    if codex_manifest is not None:
        for field in ("name", "version", "description"):
            value = codex_manifest.get(field)
            if not isinstance(value, str) or not value.strip():
                errors.append(f".codex-plugin/plugin.json missing non-empty '{field}'")

        interface = codex_manifest.get("interface", {})
        if not isinstance(interface, dict):
            errors.append(".codex-plugin/plugin.json.interface must be an object")
        else:
            display_name = interface.get("displayName")
            if not isinstance(display_name, str) or not display_name.strip():
                errors.append(
                    ".codex-plugin/plugin.json.interface.displayName must be a non-empty string"
                )

            capabilities = interface.get("capabilities")
            if not (
                isinstance(capabilities, list)
                and capabilities
                and all(isinstance(item, str) and item.strip() for item in capabilities)
            ):
                errors.append(
                    ".codex-plugin/plugin.json.interface.capabilities must be a non-empty array of strings"
                )

            default_prompt = interface.get("defaultPrompt")
            if default_prompt is not None and not (
                isinstance(default_prompt, list)
                and len(default_prompt) <= 3
                and all(isinstance(item, str) and item.strip() for item in default_prompt)
            ):
                errors.append(
                    ".codex-plugin/plugin.json.interface.defaultPrompt must be an array of up to 3 non-empty strings"
                )

        codex_skills_path = codex_manifest.get("skills")
        if not isinstance(codex_skills_path, str) or not codex_skills_path.strip():
            errors.append(".codex-plugin/plugin.json.skills must be a non-empty string path")
        else:
            resolved_skills = resolve_skill_path(codex_skills_path)
            if resolved_skills is None:
                errors.append(
                    f".codex-plugin/plugin.json.skills is invalid: {codex_skills_path!r}"
                )
            elif resolved_skills != SKILLS_DIR:
                errors.append(
                    f".codex-plugin/plugin.json.skills resolves to {resolved_skills}, expected {SKILLS_DIR}"
                )

        for optional_path_field in ("hooks", "mcpServers"):
            optional_path = codex_manifest.get(optional_path_field)
            if optional_path is None:
                continue
            if not isinstance(optional_path, str) or not optional_path.strip():
                errors.append(
                    f".codex-plugin/plugin.json.{optional_path_field} must be a non-empty string path when present"
                )
                continue
            resolved_optional = resolve_skill_path(optional_path)
            if resolved_optional is None:
                errors.append(
                    f".codex-plugin/plugin.json.{optional_path_field} is invalid: {optional_path!r}"
                )
            elif not resolved_optional.exists():
                errors.append(
                    f".codex-plugin/plugin.json.{optional_path_field} does not exist: {optional_path!r}"
                )

        for field in ("name", "version", "description", "homepage", "repository", "license"):
            claude_value = claude_manifest.get(field)
            codex_value = codex_manifest.get(field)
            if isinstance(claude_value, str) and claude_value and isinstance(codex_value, str) and codex_value:
                if claude_value != codex_value:
                    errors.append(
                        f"Codex manifest field '{field}' ({codex_value!r}) does not match Claude manifest ({claude_value!r})"
                    )

    if CODEX_MARKETPLACE.exists():
        try:
            codex_marketplace = json.loads(CODEX_MARKETPLACE.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errors.append(f"Codex marketplace is not valid JSON: {exc}")
            codex_marketplace = None

        if codex_marketplace is not None:
            name = codex_marketplace.get("name")
            if not isinstance(name, str) or not name.strip():
                errors.append(".agents/plugins/marketplace.json missing non-empty 'name'")

            interface = codex_marketplace.get("interface")
            if not isinstance(interface, dict):
                errors.append(".agents/plugins/marketplace.json.interface must be an object")
            elif not isinstance(interface.get("displayName"), str) or not interface["displayName"].strip():
                errors.append(
                    ".agents/plugins/marketplace.json.interface.displayName must be a non-empty string"
                )

            plugins = codex_marketplace.get("plugins")
            if not isinstance(plugins, list) or not plugins:
                errors.append(".agents/plugins/marketplace.json.plugins must be a non-empty array")
            else:
                allowed_installation = {"NOT_AVAILABLE", "AVAILABLE", "INSTALLED_BY_DEFAULT"}
                allowed_authentication = {"ON_INSTALL", "ON_USE"}

                for index, plugin_entry in enumerate(plugins):
                    if not isinstance(plugin_entry, dict):
                        errors.append(f"Codex marketplace plugin entry {index} must be an object")
                        continue

                    entry_name = plugin_entry.get("name")
                    if not isinstance(entry_name, str) or not entry_name.strip():
                        errors.append(f"Codex marketplace plugins[{index}].name must be non-empty")

                    source = plugin_entry.get("source")
                    if not isinstance(source, dict):
                        errors.append(f"Codex marketplace plugins[{index}].source must be an object")
                    else:
                        if source.get("source") != "local":
                            errors.append(
                                f"Codex marketplace plugins[{index}].source.source must be 'local'"
                            )
                        source_path = source.get("path")
                        if not isinstance(source_path, str) or not source_path.strip():
                            errors.append(
                                f"Codex marketplace plugins[{index}].source.path must be non-empty"
                            )
                        else:
                            resolved_source = resolve_repo_path(source_path)
                            if resolved_source is None:
                                errors.append(
                                    f"Codex marketplace plugins[{index}].source.path is invalid: {source_path!r}"
                                )
                            elif not (resolved_source / ".codex-plugin" / "plugin.json").is_file():
                                errors.append(
                                    f"Codex marketplace plugins[{index}].source.path does not resolve to a Codex plugin root: {source_path!r}"
                                )

                    policy = plugin_entry.get("policy")
                    if not isinstance(policy, dict):
                        errors.append(f"Codex marketplace plugins[{index}].policy must be an object")
                    else:
                        installation = policy.get("installation")
                        if installation not in allowed_installation:
                            errors.append(
                                f"Codex marketplace plugins[{index}].policy.installation must be one of {sorted(allowed_installation)}"
                            )
                        authentication = policy.get("authentication")
                        if authentication not in allowed_authentication:
                            errors.append(
                                f"Codex marketplace plugins[{index}].policy.authentication must be one of {sorted(allowed_authentication)}"
                            )
                        products = policy.get("products")
                        if products is not None and not (
                            isinstance(products, list)
                            and all(isinstance(item, str) and item.strip() for item in products)
                        ):
                            errors.append(
                                f"Codex marketplace plugins[{index}].policy.products must be an array of non-empty strings when present"
                            )

                    category = plugin_entry.get("category")
                    if not isinstance(category, str) or not category.strip():
                        errors.append(
                            f"Codex marketplace plugins[{index}].category must be a non-empty string"
                        )

    # Validate legacy skill-installer metadata only when present.
    if OPENAI_YAML.exists():
        yaml_content = OPENAI_YAML.read_text(encoding="utf-8")
        if not re.search(r"skills/\S+/", yaml_content):
            errors.append(
                ".agents/openai.yaml does not reference skills/<name>/ layout pattern"
            )

        root_implicit = parse_openai_yaml_field(yaml_content, "allow_implicit_invocation")
        if root_implicit is None:
            errors.append(".agents/openai.yaml missing policy.allow_implicit_invocation")
        elif root_implicit not in {"true", "false"}:
            errors.append(
                ".agents/openai.yaml has non-boolean allow_implicit_invocation "
                f"value: {root_implicit!r}"
            )

        # Verify each skill has legacy per-skill metadata with expected policy.
        for skill_dir in skill_dirs:
            skill_name = skill_dir.name
            skill_openai = skill_dir / SKILL_OPENAI_RELATIVE

            if not skill_openai.exists():
                errors.append(
                    f"Legacy Codex metadata missing for skill '{skill_name}': "
                    f"{skill_openai.relative_to(REPO_ROOT)}"
                )
                continue

            yaml_content = skill_openai.read_text(encoding="utf-8")
            display_name = parse_openai_yaml_field(yaml_content, "display_name")
            allow_implicit = parse_openai_yaml_field(yaml_content, "allow_implicit_invocation")

            if not display_name:
                errors.append(
                    f"{skill_openai.relative_to(REPO_ROOT)} missing interface.display_name"
                )
            elif display_name != skill_name:
                errors.append(
                    f"{skill_openai.relative_to(REPO_ROOT)} display_name '{display_name}' "
                    f"does not match skill directory '{skill_name}'"
                )

            if allow_implicit is None:
                errors.append(
                    f"{skill_openai.relative_to(REPO_ROOT)} missing policy.allow_implicit_invocation"
                )
                continue

            if allow_implicit not in {"true", "false"}:
                errors.append(
                    f"{skill_openai.relative_to(REPO_ROOT)} has non-boolean "
                    f"allow_implicit_invocation value: {allow_implicit!r}"
                )
                continue

            expected_implicit = "true"
            if allow_implicit != expected_implicit:
                errors.append(
                    f"{skill_openai.relative_to(REPO_ROOT)} allow_implicit_invocation={allow_implicit} "
                    f"(expected {expected_implicit} for skill '{skill_name}')"
                )

    return errors


def check_copilot(skill_dirs: list[Path]) -> list[str]:
    """Verify Copilot structural requirements.

    - plugin.json paths resolve to existing directories
    - Each SKILL.md has required frontmatter fields
    - Flat layout allows Copilot to discover skills via SKILL.md glob
    """
    errors: list[str] = []

    if not PLUGIN_JSON.exists():
        errors.append(f"plugin.json not found at {PLUGIN_JSON}")
        return errors

    # Validate plugin.json paths resolve (shared with Claude)
    plugin = load_plugin_json()
    validate_plugin_paths(plugin, errors)

    # Verify each skill has required frontmatter (per repo policy in AGENTS.md)
    missing_frontmatter = []
    bad_license = []
    for skill_dir in skill_dirs:
        skill_md = skill_dir / "SKILL.md"
        fm = parse_frontmatter(skill_md)
        if fm is None:
            missing_frontmatter.append(f"{skill_dir.name}: no frontmatter")
            continue
        missing_fields = REQUIRED_FRONTMATTER - set(fm.keys())
        if missing_fields:
            missing_frontmatter.append(
                f"{skill_dir.name}: missing {missing_fields}"
            )
        # Validate license == MIT (required by Copilot CLI per AGENTS.md)
        if fm.get("license", "") != "MIT":
            bad_license.append(f"{skill_dir.name}: license={fm.get('license', '<missing>')}")

    if missing_frontmatter:
        errors.append(
            f"{len(missing_frontmatter)} skill(s) have frontmatter issues: "
            f"{missing_frontmatter[:5]}{'...' if len(missing_frontmatter) > 5 else ''}"
        )

    if bad_license:
        errors.append(
            f"{len(bad_license)} skill(s) have non-MIT license: "
            f"{bad_license[:5]}{'...' if len(bad_license) > 5 else ''}"
        )

    # Verify skill paths are under skills/ (Copilot discovery pattern)
    skills_list = plugin.get("skills", [])
    for entry in skills_list:
        skill_path = extract_skill_path(entry)
        if skill_path is None:
            continue
        # Use Path parsing instead of string stripping
        normalized = Path(skill_path)
        if normalized.parts and normalized.parts[0] != "skills":
            errors.append(f"Skill path not under skills/: {skill_path}")

    return errors


def run_checks(providers: list[str]) -> dict | None:
    """Run structural checks for specified providers.

    Returns None if skills/ directory is missing (fatal precondition).
    """
    if not SKILLS_DIR.is_dir():
        print(f"ERROR: skills/ directory not found at {SKILLS_DIR}", file=sys.stderr)
        return None

    skill_dirs = discover_skill_dirs()
    results = {}

    check_map = {
        "claude": check_claude,
        "codex": check_codex,
        "copilot": check_copilot,
    }

    for provider in providers:
        if provider not in check_map:
            print(f"WARNING: Unknown provider '{provider}', skipping.", file=sys.stderr)
            continue
        errors = check_map[provider](skill_dirs)
        results[provider] = {
            "status": "pass" if not errors else "fail",
            "errors": errors,
            "skill_count": len(skill_dirs),
        }

    return results


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Cross-provider agent-routing structural smoke test"
    )
    parser.add_argument(
        "--provider",
        type=str,
        default="claude,codex,copilot",
        help="Comma-separated list of providers to check (default: claude,codex,copilot)",
    )
    parser.add_argument(
        "--output",
        type=str,
        default=None,
        help="Write results JSON to this path",
    )

    args = parser.parse_args()
    providers = [p.strip().lower() for p in args.provider.split(",") if p.strip()]

    if not providers:
        print("ERROR: No providers specified.", file=sys.stderr)
        return 2

    results = run_checks(providers)

    # Fatal: skills/ directory missing
    if results is None:
        return 1

    # If no recognized providers produced results, treat as usage error
    if not results:
        print("ERROR: No recognized providers found.", file=sys.stderr)
        return 2

    # Print results
    all_pass = True
    for provider, result in sorted(results.items()):
        status = result["status"].upper()
        print(f"[{provider}] {status} (skills: {result['skill_count']})")
        if result["errors"]:
            all_pass = False
            for err in result["errors"]:
                print(f"  ERROR: {err}")

    # Write output if requested
    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w") as f:
            json.dump(results, f, indent=2)
        print(f"\nResults written to: {output_path}", file=sys.stderr)

    if all_pass:
        print(f"\nAll {len(results)} provider(s) passed structural checks.")
        return 0
    else:
        failed = [p for p, r in results.items() if r["status"] == "fail"]
        print(f"\nFAILED: {len(failed)} provider(s) have errors: {failed}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
