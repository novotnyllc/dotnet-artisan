# GitHub Releases

GitHub Releases for .NET projects: release creation via `gh release create` CLI and GitHub API, asset attachment patterns (NuGet packages, binaries, SBOMs, checksums), `softprops/action-gh-release` GitHub Actions usage, release notes generation strategies (GitHub auto-generated, changelog-based, conventional commits), pre-release management (draft releases, pre-release flag, promoting pre-release to stable), and tag-triggered vs release-triggered workflow concepts.

**Version assumptions:** GitHub CLI (`gh`) 2.x+. `softprops/action-gh-release@v2`. GitHub REST API v3 / GraphQL API v4. .NET 8.0+ baseline.

## Release Creation with GitHub CLI

### Basic Release from Tag

```bash
# Create a release from an existing tag
gh release create v1.2.3 \
  --title "v1.2.3" \
  --notes "Bug fixes and performance improvements."

# Create a release and tag simultaneously
gh release create v1.2.3 \
  --title "v1.2.3" \
  --generate-notes \
  --target main
```

### Draft Release

Draft releases are invisible to the public until published. Use drafts to stage releases while finalizing assets and notes.

```bash
# Create a draft release
gh release create v1.2.3 \
  --title "v1.2.3" \
  --draft \
  --generate-notes

# Publish the draft (promote to public)
gh release edit v1.2.3 --draft=false
```

### Release with Notes from File

```bash
# Write release notes to a file
cat > release-notes.md << 'EOF'
## What's Changed

### New Features
- Added widget caching support
- Improved fluent API ergonomics

### Bug Fixes
- Fixed memory leak in widget pool
- Corrected timezone handling in scheduler

### Breaking Changes
- Removed deprecated `Widget.Create()` overload -- use `WidgetBuilder` instead

**Full Changelog**: https://github.com/mycompany/widgets/compare/v1.1.0...v1.2.0
EOF

gh release create v1.2.0 \
  --title "v1.2.0" \
  --notes-file release-notes.md
```

---

## Asset Attachment

Attach build artifacts to a release for direct download. Common .NET assets include NuGet packages, platform-specific binaries, SBOMs, and checksum files.

### Attaching Assets at Creation

```bash
# Create release with attached assets
gh release create v1.2.3 \
  --title "v1.2.3" \
  --generate-notes \
  artifacts/MyCompany.Widgets.1.2.3.nupkg \
  artifacts/MyCompany.Widgets.1.2.3.snupkg \
  artifacts/myapp-linux-x64.tar.gz \
  artifacts/myapp-win-x64.zip \
  artifacts/sbom.spdx.json \
  artifacts/SHA256SUMS.txt
```

### Attaching Assets to Existing Release

```bash
# Upload additional assets after release creation
gh release upload v1.2.3 \
  artifacts/myapp-osx-arm64.tar.gz \
  artifacts/myapp-linux-arm64.tar.gz

# Overwrite an existing asset (same filename)
gh release upload v1.2.3 \
  artifacts/SHA256SUMS.txt --clobber
```

### Common .NET Asset Types

| Asset Type | Filename Pattern | Purpose |
|------------|-----------------|---------|
| NuGet package | `*.nupkg` | Library distribution via NuGet feeds |
| Symbol package | `*.snupkg` | Source-level debugging symbols |
| Platform binary | `myapp-{rid}.tar.gz` / `.zip` | Self-contained runtime |
| SBOM | `sbom.spdx.json` / `sbom.cdx.json` | Software Bill of Materials |
| Checksums | `SHA256SUMS.txt` | Integrity verification |
| Release notes | `RELEASE-NOTES.md` | Detailed change description |

### Generating Checksums

```bash
# Generate SHA-256 checksums for all release assets
cd artifacts
sha256sum *.nupkg *.tar.gz *.zip > SHA256SUMS.txt

# On macOS
shasum -a 256 *.nupkg *.tar.gz *.zip > SHA256SUMS.txt
```

For CLI-specific release pipelines with per-RID checksums and automated package manager PRs, see [skill:dotnet-tooling].

---

## GitHub Actions Release Automation

### softprops/action-gh-release

The `softprops/action-gh-release` action creates GitHub Releases from CI workflows. For full CI pipeline structure (reusable workflows, matrix strategies), see [skill:dotnet-devops] `references/gha-patterns.md`. For NuGet push and container publish steps, see [skill:dotnet-devops] `references/gha-publish.md`.

```yaml
# Release job (add to your CI workflow)
release:
  runs-on: ubuntu-latest
  if: startsWith(github.ref, 'refs/tags/v')
  permissions:
    contents: write
  steps:
    - uses: actions/checkout@v4

    - name: Build and pack
      run: |
        dotnet build --configuration Release
        dotnet pack --configuration Release --output ./artifacts

    - name: Generate checksums
      run: |
        cd artifacts
        sha256sum *.nupkg > SHA256SUMS.txt

    - name: Create GitHub Release
      uses: softprops/action-gh-release@v2
      with:
        generate_release_notes: true
        files: |
          artifacts/*.nupkg
          artifacts/*.snupkg
          artifacts/SHA256SUMS.txt
        draft: false
        prerelease: ${{ contains(github.ref_name, '-') }}
```

### Tag-Triggered vs Release-Triggered Workflows

Two common patterns for triggering release CI:

**Tag-triggered** -- the workflow runs when a version tag is pushed:

```yaml
on:
  push:
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+*'  # Matches v1.2.3, v1.2.3-beta.1
```

**Release-triggered** -- the workflow runs when a GitHub Release is published:

```yaml
on:
  release:
    types: [published]
```

| Pattern | Pros | Cons |
|---------|------|------|
| Tag-triggered | Simple, single event, works with NBGV | Release must be created in workflow |
| Release-triggered | Draft-then-publish workflow, manual gating | Requires two-step process |

### Pre-release Detection in CI

Automatically mark releases as pre-release based on SemVer suffix:

```yaml
- name: Determine pre-release status
  id: prerelease
  run: |
    TAG="${GITHUB_REF_NAME}"
    if [[ "$TAG" == *-* ]]; then
      echo "is_prerelease=true" >> "$GITHUB_OUTPUT"
    else
      echo "is_prerelease=false" >> "$GITHUB_OUTPUT"
    fi

- name: Create release
  uses: softprops/action-gh-release@v2
  with:
    prerelease: ${{ steps.prerelease.outputs.is_prerelease }}
    generate_release_notes: true
```

---

## Release Notes Generation

### GitHub Auto-Generated Notes

GitHub can auto-generate release notes from merged PRs and commits since the last release.

```bash
# Use auto-generated notes
gh release create v1.2.3 --generate-notes

# Auto-generated notes with custom header
gh release create v1.2.3 --generate-notes \
  --notes "## Highlights
- Major performance improvements in widget processing

---
" --notes-start-tag v1.1.0
```

Configure auto-generated note categories in `.github/release.yml`:

```yaml
# .github/release.yml
changelog:
  exclude:
    labels:
      - ignore-for-release
    authors:
      - dependabot
  categories:
    - title: "Breaking Changes"
      labels:
        - breaking-change
    - title: "New Features"
      labels:
        - enhancement
        - feature
    - title: "Bug Fixes"
      labels:
        - bug
        - fix
    - title: "Dependencies"
      labels:
        - dependencies
    - title: "Other Changes"
      labels:
        - "*"
```

### Changelog-Based Notes

Use a maintained `CHANGELOG.md` as the release notes source. For CHANGELOG format and auto-generation tooling, see [skill:dotnet-devops] `references/release-management.md`.

```bash
# Extract the section for this version from CHANGELOG.md
# Note: requires a subsequent ## [ section as delimiter. For the last section:
#   sed -n "/^## \[${VERSION}\]/,\$p" CHANGELOG.md | sed '1d'
VERSION="1.2.3"
NOTES=$(sed -n "/^## \[${VERSION}\]/,/^## \[/p" CHANGELOG.md | sed '1d;$d')

gh release create "v${VERSION}" \
  --title "v${VERSION}" \
  --notes "$NOTES"
```

### Conventional Commit Notes

For projects using conventional commits (`feat:`, `fix:`, `chore:`), tools like `git-cliff` or `conventional-changelog` can generate structured release notes.

```bash
# Generate release notes from conventional commits using git-cliff
git cliff --tag "v1.2.3" --unreleased --strip header > release-notes.md

gh release create v1.2.3 \
  --title "v1.2.3" \
  --notes-file release-notes.md
```

---

## Pre-Release Management

### Pre-Release Flag

Pre-releases are visible on the releases page but not shown as the "Latest" release. NuGet packages attached to pre-releases are still stable unless they have SemVer pre-release suffixes.

```bash
# Create a pre-release
gh release create v1.2.3-beta.1 \
  --title "v1.2.3-beta.1" \
  --prerelease \
  --generate-notes

# Create a pre-release from a specific branch
gh release create v2.0.0-alpha.1 \
  --title "v2.0.0-alpha.1" \
  --prerelease \
  --target feature/v2
```

### Promoting Pre-Release to Stable

When a pre-release has been validated, promote it to a stable release:

```bash
# Remove pre-release flag
gh release edit v1.2.3-rc.1 --prerelease=false

# Or create a new stable release pointing to the same commit
COMMIT=$(gh release view v1.2.3-rc.1 --json targetCommitish -q .targetCommitish)
gh release create v1.2.3 \
  --title "v1.2.3" \
  --target "$COMMIT" \
  --notes "Stable release based on v1.2.3-rc.1. No changes from RC."
```

### Draft-Then-Publish Workflow

Use drafts to stage releases with assets before making them public:

```bash
# 1. CI creates a draft release with all assets
gh release create v1.2.3 \
  --draft \
  --title "v1.2.3" \
  --generate-notes \
  artifacts/*.nupkg artifacts/SHA256SUMS.txt

# 2. Team reviews the draft on GitHub

# 3. Publish the draft when ready
gh release edit v1.2.3 --draft=false

# 4. A release-triggered workflow picks up the published event
#    and pushes NuGet packages to nuget.org
```

### Pre-Release Progression

A typical pre-release progression for a .NET library:

| Stage | Tag | GitHub Pre-release | NuGet Version |
|-------|-----|-------------------|---------------|
| Alpha | `v2.0.0-alpha.1` | Yes | `2.0.0-alpha.1` |
| Beta | `v2.0.0-beta.1` | Yes | `2.0.0-beta.1` |
| Release candidate | `v2.0.0-rc.1` | Yes | `2.0.0-rc.1` |
| Stable | `v2.0.0` | No (Latest) | `2.0.0` |

---

## GitHub API Release Management

### Creating Releases via API

For automation scenarios beyond the `gh` CLI:

```bash
# Create a release via GitHub REST API
curl -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/OWNER/REPO/releases" \
  -d '{
    "tag_name": "v1.2.3",
    "target_commitish": "main",
    "name": "v1.2.3",
    "body": "Release notes here",
    "draft": false,
    "prerelease": false
  }'
```

### Uploading Assets via API

```bash
# Upload an asset to an existing release (REST API needs numeric release ID)
RELEASE_ID=$(gh api repos/OWNER/REPO/releases/tags/v1.2.3 --jq .id)
curl -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Content-Type: application/octet-stream" \
  "https://uploads.github.com/repos/OWNER/REPO/releases/${RELEASE_ID}/assets?name=MyApp.nupkg" \
  --data-binary @artifacts/MyApp.1.2.3.nupkg
```

### Listing and Querying Releases

```bash
# List all releases
gh release list

# View a specific release
gh release view v1.2.3

# Get latest release tag
gh release view --json tagName -q .tagName

# List releases as JSON for scripting
gh release list --json tagName,isPrerelease,publishedAt
```

---

## Agent Gotchas

1. **Never hardcode `GITHUB_TOKEN` values in examples** -- always use `$GITHUB_TOKEN` or `${{ secrets.GITHUB_TOKEN }}` environment variable references. The `GITHUB_TOKEN` is automatically available in GitHub Actions.

2. **`softprops/action-gh-release` requires `permissions: contents: write`** -- without this, the action fails with a 403 error. Always include the permissions block in the workflow job.

3. **Pre-release detection by SemVer suffix requires checking for a hyphen** -- `v1.2.3-beta.1` is pre-release, `v1.2.3` is stable. Use `contains(github.ref_name, '-')` or shell pattern matching, not regex on the version number alone.

4. **`--generate-notes` and `--notes` can be combined** -- custom notes appear first, auto-generated notes are appended. Use `--notes-start-tag` to control the comparison range.

5. **Draft releases do not trigger `release: published` events** -- only publishing the draft triggers the event. This is the intended behavior for draft-then-publish workflows.

6. **Asset filenames must be unique within a release** -- uploading a file with the same name replaces the existing asset only with `--clobber`. Without it, the upload fails.

7. **Tag-triggered workflows should validate the tag format** -- use `if: startsWith(github.ref, 'refs/tags/v')` to ensure the workflow only runs on version tags, not arbitrary tags.

8. **`gh release create` with `--target` creates the tag if it does not exist** -- this is useful for CI but can cause confusion if the tag already exists on a different commit.
