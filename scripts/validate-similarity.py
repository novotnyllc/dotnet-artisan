#!/usr/bin/env python3
"""Semantic similarity overlap detection for dotnet-artisan skill and agent descriptions.

Computes pairwise semantic similarity using a multi-signal composite score:
  composite = 0.5 * set_jaccard + 0.5 * seqmatcher

Signals:
  1. Set Jaccard (0.5 weight): tokenize -> lowercase -> strip domain stopwords -> set ->
     |A & B| / |A | B|
  2. SequenceMatcher ratio (0.5 weight): difflib.SequenceMatcher on raw descriptions

Exit codes:
  0: No unsuppressed ERRORs AND no new WARNs vs baseline
  1: Unsuppressed ERROR pairs exist, OR new WARN+ pairs not in baseline/suppressions
  2: Script error (bad args, missing files)

Task: fn-53-skill-routing-language-hardening.13, fn-56-copilot-structural-compatibility.3
"""

import argparse
import difflib
import json
import re
import sys
from pathlib import Path

# ---- Domain stopwords (stripped before set Jaccard only) ----
DOMAIN_STOPWORDS = {
    "dotnet", "net", "apps", "building", "designing", "using", "writing",
    "implementing", "adding", "creating", "configuring", "managing",
    "choosing", "analyzing", "working", "patterns", "for",
}

# ---- Thresholds ----
DEFAULT_WARN_THRESHOLD = 0.55
DEFAULT_ERROR_THRESHOLD = 0.75
INFO_THRESHOLD = 0.40

# ---- Tokenisation ----
_TOKEN_RE = re.compile(r"[a-zA-Z0-9]+")


def tokenize(text: str) -> list[str]:
    """Tokenize text into lowercase alphanumeric tokens."""
    return [t.lower() for t in _TOKEN_RE.findall(text)]


def strip_stopwords(tokens: list[str]) -> set[str]:
    """Return set of tokens with domain stopwords removed."""
    result = {t for t in tokens if t not in DOMAIN_STOPWORDS}
    return result


# ---- Similarity signals ----

def set_jaccard(tokens_a: set[str], tokens_b: set[str]) -> float:
    """Compute Jaccard index over two token sets."""
    if not tokens_a and not tokens_b:
        return 0.0
    intersection = tokens_a & tokens_b
    union = tokens_a | tokens_b
    if not union:
        return 0.0
    return len(intersection) / len(union)


def seqmatcher_ratio(desc_a: str, desc_b: str) -> float:
    """Compute SequenceMatcher ratio on raw descriptions."""
    if not desc_a and not desc_b:
        return 0.0
    return difflib.SequenceMatcher(a=desc_a, b=desc_b).ratio()


def composite_score(jaccard: float, seqmatch: float) -> float:
    """Compute composite similarity score.

    After the flat layout migration (fn-56), the same-category boost was
    removed because all skills share the same parent directory (skills/).
    Weights are now 0.5/0.5 for the two remaining signals.
    """
    return 0.5 * jaccard + 0.5 * seqmatch


# ---- Description collection ----

def collect_skill_descriptions(repo_root: Path) -> list[dict]:
    """Collect skill ID and description from all SKILL.md files.

    Uses ``*/SKILL.md`` glob (flat layout -- one level deep under skills/).
    """
    skills_dir = repo_root / "skills"
    if not skills_dir.is_dir():
        print(f"ERROR: skills directory not found: {skills_dir}", file=sys.stderr)
        sys.exit(2)

    items = []
    for skill_md in sorted(skills_dir.glob("*/SKILL.md")):
        skill_id = skill_md.parent.name
        description = _parse_skill_description(skill_md) or ""
        items.append({
            "id": skill_id,
            "description": description,
        })
    return items


def _parse_skill_description(skill_md: Path) -> str | None:
    """Extract description from SKILL.md frontmatter."""
    try:
        text = skill_md.read_text(encoding="utf-8")
    except Exception:
        return None

    text = text.replace("\r\n", "\n").replace("\r", "\n")
    lines = text.split("\n")

    if not lines or lines[0].strip() != "---":
        return None

    for _, line in enumerate(lines[1:], 1):
        if line.strip() == "---":
            break
        # Require column-0 match (no leading whitespace) for top-level only
        if line != line.lstrip():
            continue
        m = re.match(r'^description\s*:\s*(.*)', line)
        if m:
            val = m.group(1).strip()
            # Strip surrounding quotes
            if len(val) >= 2 and val[0] == val[-1] and val[0] in ('"', "'"):
                val = val[1:-1]
            return val if val else None

    return None


def collect_agent_descriptions(repo_root: Path) -> list[dict]:
    """Collect agent ID and description from all agent .md files.

    Uses the shared _agent_frontmatter.py module (T3). Falls back to
    skills-only mode with stderr warning if the module is not available.
    """
    agents_dir = repo_root / "agents"
    if not agents_dir.is_dir():
        return []

    # Import shared parser
    try:
        scripts_dir = Path(__file__).resolve().parent
        if str(scripts_dir) not in sys.path:
            sys.path.insert(0, str(scripts_dir))
        from _agent_frontmatter import parse_agent_frontmatter
    except ImportError:
        print(
            "_agent_frontmatter.py not found -- running in skills-only mode, "
            "agent descriptions excluded",
            file=sys.stderr,
        )
        return []

    items = []
    for agent_md in sorted(agents_dir.glob("*.md")):
        agent_id = agent_md.stem
        parsed = parse_agent_frontmatter(str(agent_md))
        description = parsed.get("description") or ""
        items.append({
            "id": agent_id,
            "description": description,
        })
    return items


# ---- Suppression handling ----

def load_suppressions(path: Path | None) -> set[tuple[str, str]]:
    """Load suppression list and return set of canonical pairs."""
    if path is None:
        return set()
    if not path.is_file():
        print(f"ERROR: Suppressions file not found: {path}", file=sys.stderr)
        sys.exit(2)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"ERROR: Failed to parse suppressions file: {e}", file=sys.stderr)
        sys.exit(2)

    if not isinstance(data, list):
        print("ERROR: Suppressions file must be a JSON array", file=sys.stderr)
        sys.exit(2)

    pairs = set()
    for idx, entry in enumerate(data):
        if not isinstance(entry, dict):
            print(
                f"ERROR: Suppression entry {idx} must be a JSON object",
                file=sys.stderr,
            )
            sys.exit(2)
        id_a = entry.get("id_a", None)
        id_b = entry.get("id_b", None)
        if not isinstance(id_a, str) or not isinstance(id_b, str):
            print(
                f"ERROR: Suppression entry {idx} id_a/id_b must be strings",
                file=sys.stderr,
            )
            sys.exit(2)
        id_a = id_a.strip()
        id_b = id_b.strip()
        if not id_a or not id_b:
            print(
                f"ERROR: Suppression entry {idx} has empty id_a or id_b",
                file=sys.stderr,
            )
            sys.exit(2)
        if id_a == id_b:
            print(
                f"ERROR: Suppression entry {idx} has identical id_a and id_b: {id_a}",
                file=sys.stderr,
            )
            sys.exit(2)
        canonical = (min(id_a, id_b), max(id_a, id_b))
        pairs.add(canonical)
    return pairs


def load_baseline(path: Path | None) -> set[tuple[str, str]] | None:
    """Load baseline file. Returns None if no baseline provided."""
    if path is None:
        return None
    if not path.is_file():
        print(f"ERROR: Baseline file not found: {path}", file=sys.stderr)
        sys.exit(2)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"ERROR: Failed to parse baseline file: {e}", file=sys.stderr)
        sys.exit(2)

    if not isinstance(data, dict):
        print("ERROR: Baseline file must be a JSON object", file=sys.stderr)
        sys.exit(2)

    if data.get("version") != 1:
        print(
            f"ERROR: Unsupported baseline version: {data.get('version')}",
            file=sys.stderr,
        )
        sys.exit(2)

    pairs_raw = data.get("pairs", [])
    if not isinstance(pairs_raw, list):
        print("ERROR: Baseline 'pairs' must be a JSON array", file=sys.stderr)
        sys.exit(2)

    pairs = set()
    for idx, pair in enumerate(pairs_raw):
        if not isinstance(pair, list) or len(pair) != 2:
            print(
                f"ERROR: Baseline entry {idx} is not a 2-element array",
                file=sys.stderr,
            )
            sys.exit(2)
        a, b = pair[0], pair[1]
        if not isinstance(a, str) or not isinstance(b, str):
            print(
                f"ERROR: Baseline entry {idx} IDs must be strings: {pair}",
                file=sys.stderr,
            )
            sys.exit(2)
        a = a.strip()
        b = b.strip()
        if not a or not b:
            print(
                f"ERROR: Baseline entry {idx} has empty ID(s): {pair}",
                file=sys.stderr,
            )
            sys.exit(2)
        if a == b:
            print(
                f"ERROR: Baseline entry {idx} has identical IDs: {a}",
                file=sys.stderr,
            )
            sys.exit(2)
        pairs.add((min(a, b), max(a, b)))
    return pairs


# ---- Main computation ----

def compute_all_pairs(
    items: list[dict],
    suppressions: set[tuple[str, str]],
    warn_threshold: float,
    error_threshold: float,
) -> list[dict]:
    """Compute composite similarity for all pairs above INFO threshold.

    Suppressed pairs are always included regardless of score (emitted as INFO).
    Returns list of pair records sorted by composite descending.
    """
    results = []
    n = len(items)

    # Pre-compute tokenised sets for Jaccard
    token_sets = []
    for item in items:
        tokens = tokenize(item["description"])
        stripped = strip_stopwords(tokens)
        token_sets.append(stripped)

    for i in range(n):
        for j in range(i + 1, n):
            a = items[i]
            b = items[j]

            # Canonical ordering
            if a["id"] <= b["id"]:
                id_a, id_b = a["id"], b["id"]
                idx_a, idx_b = i, j
            else:
                id_a, id_b = b["id"], a["id"]
                idx_a, idx_b = j, i

            # Compute signals
            jaccard = set_jaccard(token_sets[idx_a], token_sets[idx_b])
            seqmatch = seqmatcher_ratio(
                items[idx_a]["description"], items[idx_b]["description"]
            )
            comp = composite_score(jaccard, seqmatch)

            canonical_pair = (id_a, id_b)
            is_suppressed = canonical_pair in suppressions

            # Suppressed pairs always emitted as INFO regardless of score;
            # unsuppressed pairs must meet INFO threshold
            if comp < INFO_THRESHOLD and not is_suppressed:
                continue

            # Determine level
            if is_suppressed:
                level = "INFO"
            elif comp >= error_threshold:
                level = "ERROR"
            elif comp >= warn_threshold:
                level = "WARN"
            else:
                level = "INFO"

            results.append({
                "id_a": id_a,
                "id_b": id_b,
                "composite": round(comp, 6),
                "jaccard": round(jaccard, 6),
                "seqmatcher": round(seqmatch, 6),
                "level": level,
            })

    # Sort by composite descending, then by id_a, id_b for stability
    results.sort(key=lambda r: (-r["composite"], r["id_a"], r["id_b"]))
    return results


def build_summary(
    pairs: list[dict],
    total_items: int,
    total_pairs: int,
    suppressions: set[tuple[str, str]],
    baseline: set[tuple[str, str]] | None,
) -> dict:
    """Build summary statistics from computed pairs."""
    max_score = max((p["composite"] for p in pairs), default=0.0)
    max_unsuppressed_score = max(
        (p["composite"] for p in pairs
         if (p["id_a"], p["id_b"]) not in suppressions),
        default=0.0,
    )
    pairs_above_warn = sum(
        1 for p in pairs if p["level"] in ("WARN", "ERROR")
    )
    pairs_above_error = sum(1 for p in pairs if p["level"] == "ERROR")
    suppressed_count = sum(
        1 for p in pairs
        if (p["id_a"], p["id_b"]) in suppressions
    )
    unsuppressed_errors = pairs_above_error  # ERROR level already excludes suppressed

    # Compute new warns vs baseline
    new_warns = 0
    if baseline is not None:
        for p in pairs:
            if p["level"] in ("WARN", "ERROR"):
                canonical = (p["id_a"], p["id_b"])
                if canonical not in baseline and canonical not in suppressions:
                    new_warns += 1

    return {
        "total_items": total_items,
        "total_pairs": total_pairs,
        "max_score": round(max_score, 6),
        "max_unsuppressed_score": round(max_unsuppressed_score, 6),
        "pairs_above_warn": pairs_above_warn,
        "pairs_above_error": pairs_above_error,
        "suppressed_count": suppressed_count,
        "unsuppressed_errors": unsuppressed_errors,
        "new_warns_vs_baseline": new_warns if baseline is not None else None,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Detect semantic similarity overlap between skill/agent descriptions"
    )
    parser.add_argument(
        "--repo-root", required=True, type=Path,
        help="Path to repository root"
    )
    parser.add_argument(
        "--suppressions", type=Path, default=None,
        help="Path to similarity-suppressions.json"
    )
    parser.add_argument(
        "--baseline", type=Path, default=None,
        help="Path to similarity-baseline.json"
    )
    parser.add_argument(
        "--warn-threshold", type=float, default=DEFAULT_WARN_THRESHOLD,
        help=f"WARN threshold (default: {DEFAULT_WARN_THRESHOLD})"
    )
    parser.add_argument(
        "--error-threshold", type=float, default=DEFAULT_ERROR_THRESHOLD,
        help=f"ERROR threshold (default: {DEFAULT_ERROR_THRESHOLD})"
    )

    try:
        args = parser.parse_args()
    except SystemExit as e:
        return 2 if e.code != 0 else 0

    repo_root = args.repo_root.resolve()
    if not repo_root.is_dir():
        print(f"ERROR: repo-root is not a directory: {repo_root}", file=sys.stderr)
        return 2

    # Collect all items
    skill_items = collect_skill_descriptions(repo_root)
    agent_items = collect_agent_descriptions(repo_root)
    all_items = skill_items + agent_items

    # Detect duplicate IDs (skill dir name colliding with agent file stem)
    seen_ids: dict[str, str] = {}
    for idx, item in enumerate(all_items):
        item_id = item["id"]
        source = "skill" if idx < len(skill_items) else "agent"
        if item_id in seen_ids:
            print(
                f"ERROR: ID collision between {seen_ids[item_id]} and {source}: "
                f"{item_id}. Rename one to avoid ambiguity.",
                file=sys.stderr,
            )
            return 2
        seen_ids[item_id] = source

    total_items = len(all_items)
    total_pairs = total_items * (total_items - 1) // 2

    if total_items < 2:
        print("ERROR: Need at least 2 items for similarity check", file=sys.stderr)
        return 2

    # Load suppressions and baseline
    suppressions = load_suppressions(args.suppressions)
    baseline = load_baseline(args.baseline)

    # Compute all pairs
    pairs = compute_all_pairs(
        all_items, suppressions, args.warn_threshold, args.error_threshold
    )

    # Build summary
    summary = build_summary(
        pairs, total_items, total_pairs, suppressions, baseline,
    )

    # Output JSON report to stdout
    report = {"pairs": pairs, "summary": summary}
    print(json.dumps(report, indent=2))

    # Stable CI output keys to stderr
    print(f"MAX_SIMILARITY_SCORE={summary['max_score']}", file=sys.stderr)
    print(f"PAIRS_ABOVE_WARN={summary['pairs_above_warn']}", file=sys.stderr)
    print(f"PAIRS_ABOVE_ERROR={summary['pairs_above_error']}", file=sys.stderr)

    # Determine exit code
    has_unsuppressed_errors = summary["unsuppressed_errors"] > 0
    has_new_warns = (
        baseline is not None and summary["new_warns_vs_baseline"] is not None
        and summary["new_warns_vs_baseline"] > 0
    )

    if has_unsuppressed_errors or has_new_warns:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
