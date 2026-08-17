# CLI Release Pipeline

Unified release CI/CD pipeline for .NET CLI tools: GitHub Actions workflow producing all distribution formats from a single version tag trigger, build matrix per Runtime Identifier (RID), artifact staging between jobs, GitHub Releases with SHA-256 checksums, automated Homebrew formula and winget manifest PR creation, and SemVer versioning strategy with git tags.

**Version assumptions:** .NET 8.0+ baseline. GitHub Actions workflow syntax v2. Patterns apply to any CI system but examples use GitHub Actions.

## Versioning Strategy

### SemVer + Git Tags

Use Semantic Versioning (SemVer) with git tags as the single source of truth for release versions.

**Tag format:** `v{major}.{minor}.{patch}` (e.g., `v1.2.3`)

```bash
# Tag a release
git tag -a v1.2.3 -m "Release v1.2.3"
git push origin v1.2.3
```

### Version Flow

```
git tag v1.2.3
    │
    ▼
GitHub Actions trigger (on push tags: v*)
    │
    ▼
Extract version from tag: GITHUB_REF_NAME → v1.2.3 → 1.2.3
    │
    ▼
Pass to dotnet publish /p:Version=1.2.3
    │
    ▼
Embed in binary (--version output)
    │
    ▼
Stamp in package manifests (Homebrew, winget, Scoop, NuGet)
```

### Extracting Version from Tag

```yaml
- name: Extract version from tag
  id: version
  run: echo "version=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"
  # v1.2.3 → 1.2.3
```

### Pre-release Versions

```bash
# Pre-release tag
git tag -a v1.3.0-rc.1 -m "Release candidate 1"

# CI detects pre-release and skips package manager submissions
# but still creates GitHub Release as pre-release
```


## Unified GitHub Actions Workflow

### Complete Workflow

```yaml
name: Release

on:
  push:
    tags:
      - "v[0-9]+.[0-9]+.[0-9]+*"  # v1.2.3, v1.2.3-rc.1

permissions:
  contents: write  # Create GitHub Releases

defaults:
  run:
    shell: bash

env:
  PROJECT: src/MyCli/MyCli.csproj
  DOTNET_VERSION: "8.0.x"

jobs:
  build:
    strategy:
      matrix:
        include:
          - rid: linux-x64
            os: ubuntu-latest
          - rid: linux-arm64
            os: ubuntu-latest
          - rid: osx-arm64
            os: macos-latest
          - rid: win-x64
            os: windows-latest
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: ${{ env.DOTNET_VERSION }}

      - name: Extract version
        id: version
        shell: bash
        run: echo "version=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"

      - name: Publish
        run: >-
          dotnet publish ${{ env.PROJECT }}
          -c Release
          -r ${{ matrix.rid }}
          -o ./publish
          /p:Version=${{ steps.version.outputs.version }}

      - name: Package (Unix)
        if: runner.os != 'Windows'
        run: |
          set -euo pipefail
          cd publish
          tar -czf "$GITHUB_WORKSPACE/mytool-${{ steps.version.outputs.version }}-${{ matrix.rid }}.tar.gz" .

      - name: Package (Windows)
        if: runner.os == 'Windows'
        shell: pwsh
        run: |
          Compress-Archive -Path "publish/*" `
            -DestinationPath "mytool-${{ steps.version.outputs.version }}-${{ matrix.rid }}.zip"

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: release-${{ matrix.rid }}
          path: |
            *.tar.gz
            *.zip

  release:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Extract version
        id: version
        run: echo "version=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"

      - name: Download all artifacts
        uses: actions/download-artifact@v4
        with:
          path: artifacts
          merge-multiple: true

      - name: Generate checksums
        working-directory: artifacts
        run: |
          set -euo pipefail
          shasum -a 256 *.tar.gz *.zip > checksums-sha256.txt
          cat checksums-sha256.txt

      - name: Detect pre-release
        id: prerelease
        run: |
          set -euo pipefail
          if [[ "${{ steps.version.outputs.version }}" == *-* ]]; then
            echo "is_prerelease=true" >> "$GITHUB_OUTPUT"
          else
            echo "is_prerelease=false" >> "$GITHUB_OUTPUT"
          fi

      # Pin third-party actions to a commit SHA in production for supply-chain security
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          name: v${{ steps.version.outputs.version }}
          prerelease: ${{ steps.prerelease.outputs.is_prerelease }}
          generate_release_notes: true
          files: |
            artifacts/*.tar.gz
            artifacts/*.zip
            artifacts/checksums-sha256.txt

  publish-nuget:
    needs: release
    if: ${{ !contains(github.ref_name, '-') }}  # Skip pre-releases
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: ${{ env.DOTNET_VERSION }}

      - name: Extract version
        id: version
        run: echo "version=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"

      - name: Pack
        run: >-
          dotnet pack ${{ env.PROJECT }}
          -c Release
          /p:Version=${{ steps.version.outputs.version }}
          -o ./nupkgs

      - name: Push to NuGet
        run: >-
          dotnet nuget push ./nupkgs/*.nupkg
          --source https://api.nuget.org/v3/index.json
          --api-key ${{ secrets.NUGET_API_KEY }}
```


## Build Matrix per RID

### Matrix Strategy

The build matrix produces one artifact per RID. Each RID runs on the appropriate runner OS.

```yaml
strategy:
  matrix:
    include:
      - rid: linux-x64
        os: ubuntu-latest
      - rid: linux-arm64
        os: ubuntu-latest        # Cross-compile ARM64 on x64 runner
      - rid: osx-arm64
        os: macos-latest         # Native ARM64 runner
      - rid: win-x64
        os: windows-latest
```

### Cross-Compilation Notes

- **linux-arm64 on ubuntu-latest:** .NET supports cross-compilation for managed (non-AOT) builds. `dotnet publish -r linux-arm64` on an x64 runner produces a valid ARM64 binary without QEMU. For Native AOT, cross-compiling ARM64 on an x64 runner requires the ARM64 cross-compilation toolchain (`gcc-aarch64-linux-gnu` or equivalent). See `references/native-aot.md` for cross-compile prerequisites.
- **osx-arm64:** Use `macos-latest` (which provides ARM64 runners) for native compilation. Cross-compiling macOS ARM64 from Linux is not supported.
- **win-x64 on windows-latest:** Native compilation on Windows runner.

### Extended Matrix (Optional)

```yaml
strategy:
  matrix:
    include:
      # Primary targets
      - rid: linux-x64
        os: ubuntu-latest
      - rid: linux-arm64
        os: ubuntu-latest
      - rid: osx-arm64
        os: macos-latest
      - rid: win-x64
        os: windows-latest
      # Extended targets
      - rid: osx-x64
        os: macos-13           # Intel macOS runner
      - rid: linux-musl-x64
        os: ubuntu-latest      # Alpine musl cross-compile
```


## Artifact Staging

### Upload Per-RID Artifacts

Each matrix job uploads its artifact with a RID-specific name:

```yaml
- name: Upload artifact
  uses: actions/upload-artifact@v4
  with:
    name: release-${{ matrix.rid }}
    path: |
      *.tar.gz
      *.zip
    retention-days: 1  # Short retention -- artifacts are published to GitHub Releases
```

### Download in Release Job

The release job downloads all artifacts from the build matrix:

```yaml
- name: Download all artifacts
  uses: actions/download-artifact@v4
  with:
    path: artifacts
    merge-multiple: true  # Merge all release-* artifacts into one directory
```

After download, `artifacts/` contains:

```
artifacts/
  mytool-1.2.3-linux-x64.tar.gz
  mytool-1.2.3-linux-arm64.tar.gz
  mytool-1.2.3-osx-arm64.tar.gz
  mytool-1.2.3-win-x64.zip
```


## GitHub Releases with Checksums

### Checksum Generation

```yaml
- name: Generate checksums
  working-directory: artifacts
  run: |
    set -euo pipefail
    shasum -a 256 *.tar.gz *.zip > checksums-sha256.txt
    cat checksums-sha256.txt
```

**Output format (checksums-sha256.txt):**

```
abc123...  mytool-1.2.3-linux-x64.tar.gz
def456...  mytool-1.2.3-linux-arm64.tar.gz
ghi789...  mytool-1.2.3-osx-arm64.tar.gz
jkl012...  mytool-1.2.3-win-x64.zip
```

### Creating the Release

```yaml
- name: Create GitHub Release
  uses: softprops/action-gh-release@v2
  with:
    name: v${{ steps.version.outputs.version }}
    prerelease: ${{ steps.prerelease.outputs.is_prerelease }}
    generate_release_notes: true
    files: |
      artifacts/*.tar.gz
      artifacts/*.zip
      artifacts/checksums-sha256.txt
```

`generate_release_notes: true` auto-generates release notes from merged PRs and commit messages since the last tag.


## Automated Formula/Manifest PR Creation

### Homebrew Formula Update

After the GitHub Release is published, update the Homebrew tap automatically:

```yaml
  update-homebrew:
    needs: release
    if: ${{ !contains(github.ref_name, '-') }}
    runs-on: ubuntu-latest
    steps:
      - name: Extract version
        id: version
        run: echo "version=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"

      - uses: actions/checkout@v4
        with:
          repository: myorg/homebrew-tap
          token: ${{ secrets.TAP_GITHUB_TOKEN }}

      - name: Download checksums
        run: |
          set -euo pipefail
          curl -sL "https://github.com/myorg/mytool/releases/download/v${{ steps.version.outputs.version }}/checksums-sha256.txt" \
            -o checksums.txt

      - name: Update formula
        run: |
          set -euo pipefail
          VERSION="${{ steps.version.outputs.version }}"
          LINUX_X64_SHA=$(grep "linux-x64" checksums.txt | awk '{print $1}')
          LINUX_ARM64_SHA=$(grep "linux-arm64" checksums.txt | awk '{print $1}')
          OSX_ARM64_SHA=$(grep "osx-arm64" checksums.txt | awk '{print $1}')

          # Use sed or a templating script to update Formula/mytool.rb
          # with new version and SHA-256 values
          python3 scripts/update-formula.py \
            --version "$VERSION" \
            --linux-x64-sha "$LINUX_X64_SHA" \
            --linux-arm64-sha "$LINUX_ARM64_SHA" \
            --osx-arm64-sha "$OSX_ARM64_SHA"

      - name: Create PR
        uses: peter-evans/create-pull-request@v6
        with:
          title: "mytool ${{ steps.version.outputs.version }}"
          commit-message: "Update mytool to ${{ steps.version.outputs.version }}"
          branch: "update-mytool-${{ steps.version.outputs.version }}"
          body: |
            Automated update for mytool v${{ steps.version.outputs.version }}
            Release: https://github.com/myorg/mytool/releases/tag/v${{ steps.version.outputs.version }}
```

### winget Manifest Update

```yaml
  update-winget:
    needs: release
    if: ${{ !contains(github.ref_name, '-') }}
    runs-on: windows-latest
    steps:
      - name: Extract version
        id: version
        shell: bash
        run: echo "version=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"

      - name: Submit to winget-pkgs
        uses: vedantmgoyal9/winget-releaser@main
        with:
          identifier: MyOrg.MyTool
          version: ${{ steps.version.outputs.version }}
          installers-regex: '\.zip$'
          token: ${{ secrets.WINGET_GITHUB_TOKEN }}
```

### Scoop Manifest Update

```yaml
  update-scoop:
    needs: release
    if: ${{ !contains(github.ref_name, '-') }}
    runs-on: ubuntu-latest
    steps:
      - name: Extract version
        id: version
        run: echo "version=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"

      - uses: actions/checkout@v4
        with:
          repository: myorg/scoop-mytool
          token: ${{ secrets.SCOOP_GITHUB_TOKEN }}

      - name: Download checksums
        run: |
          set -euo pipefail
          curl -sL "https://github.com/myorg/mytool/releases/download/v${{ steps.version.outputs.version }}/checksums-sha256.txt" \
            -o checksums.txt

      - name: Update manifest
        run: |
          set -euo pipefail
          VERSION="${{ steps.version.outputs.version }}"
          WIN_X64_SHA=$(grep "win-x64" checksums.txt | awk '{print $1}')

          # Update bucket/mytool.json with new version and hash
          jq --arg v "$VERSION" --arg h "$WIN_X64_SHA" \
            '.version = $v | .architecture."64bit".hash = $h |
             .architecture."64bit".url = "https://github.com/myorg/mytool/releases/download/v\($v)/mytool-\($v)-win-x64.zip"' \
            bucket/mytool.json > tmp.json && mv tmp.json bucket/mytool.json

      - name: Create PR
        uses: peter-evans/create-pull-request@v6
        with:
          title: "mytool ${{ steps.version.outputs.version }}"
          commit-message: "Update mytool to ${{ steps.version.outputs.version }}"
          branch: "update-mytool-${{ steps.version.outputs.version }}"
```


## Versioning Strategy Details

### SemVer for CLI Tools

| Change Type | Version Bump | Example |
|-------------|-------------|---------|
| Breaking CLI flag rename/removal | Major | 1.x.x -> 2.0.0 |
| New command or option | Minor | x.1.x -> x.2.0 |
| Bug fix, performance improvement | Patch | x.x.1 -> x.x.2 |
| Release candidate | Pre-release suffix | x.x.x-rc.1 |

### Version Embedding

The version flows from the git tag through `dotnet publish` into the binary:

```xml
<!-- .csproj -- Version is set at publish time via /p:Version -->
<PropertyGroup>
  <!-- Fallback version for local development -->
  <Version>0.0.0-dev</Version>
</PropertyGroup>
```

```bash
# --version output matches the git tag
$ mytool --version
1.2.3
```

### Tagging Workflow

```bash
# 1. Update CHANGELOG.md (if applicable)
# 2. Commit the changelog
git commit -am "docs: update changelog for v1.2.3"

# 3. Tag the release
git tag -a v1.2.3 -m "Release v1.2.3"

# 4. Push tag -- triggers the release workflow
git push origin v1.2.3
```


## Workflow Security

### Secret Management

```yaml
# Required repository secrets:
# NUGET_API_KEY         - NuGet.org API key for package publishing
# TAP_GITHUB_TOKEN      - PAT with repo scope for homebrew-tap
# WINGET_GITHUB_TOKEN   - PAT with public_repo scope for winget-pkgs PRs
# SCOOP_GITHUB_TOKEN    - PAT with repo scope for scoop bucket
# CHOCO_API_KEY         - Chocolatey API key for package push
```

### Permissions

```yaml
permissions:
  contents: write  # Minimum: create GitHub Releases and upload assets
```

Use job-level permissions when different jobs need different scopes. Never grant `write-all`.


## Agent Gotchas

1. **Do not use `set -e` without `set -o pipefail` in GitHub Actions bash steps.** Without `pipefail`, a failing command piped to `tee` or another utility exits 0, masking the failure. Always use `set -euo pipefail`.
2. **Do not hardcode the .NET version in the publish path.** Use `dotnet publish -o ./publish` to control the output directory explicitly. Hardcoding `net8.0` in artifact paths breaks when upgrading to .NET 9+.
3. **Do not skip the pre-release detection step.** Package manager submissions (Homebrew, winget, Scoop, Chocolatey, NuGet) must be gated on stable versions. Publishing a `-rc.1` to winget-pkgs or NuGet as stable causes user confusion.
4. **Do not use `actions/upload-artifact` v3 with `merge-multiple`.** The `merge-multiple` parameter requires `actions/download-artifact@v4`. Using v3 silently ignores the flag and creates nested directories.
5. **Do not forget `retention-days: 1` on intermediate build artifacts.** Release artifacts are published to GitHub Releases (permanent). Workflow artifacts are temporary and should expire quickly to save storage.
6. **Do not create GitHub Releases with `gh release create` in a matrix job.** Only the release job (after all builds complete) should create the release. Matrix jobs upload artifacts; the release job assembles them.


## References

- [GitHub Actions workflow syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- [softprops/action-gh-release](https://github.com/softprops/action-gh-release)
- [peter-evans/create-pull-request](https://github.com/peter-evans/create-pull-request)
- [vedantmgoyal9/winget-releaser](https://github.com/vedantmgoyal9/winget-releaser)
- [Semantic Versioning](https://semver.org/)
- [.NET versioning](https://learn.microsoft.com/en-us/dotnet/core/versions/)
- [GitHub Actions artifacts](https://docs.github.com/en/actions/using-workflows/storing-workflow-data-as-artifacts)
