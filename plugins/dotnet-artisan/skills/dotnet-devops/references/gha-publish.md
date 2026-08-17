# GitHub Actions Publish

Publishing workflows for .NET projects in GitHub Actions: NuGet package push to nuget.org and GitHub Packages, container image build and push to GHCR/DockerHub/ACR, artifact signing with NuGet signing and sigstore, SBOM generation with Microsoft SBOM tool, and conditional publishing triggered by tags and releases.

**Version assumptions:** `actions/setup-dotnet@v4` for .NET 8/9/10. `docker/build-push-action@v6` for container image builds. `docker/login-action@v3` for registry authentication. .NET SDK container publish (`dotnet publish` with `PublishContainer`) for Dockerfile-free container builds.

## NuGet Push to nuget.org

### Tag-Triggered Package Publishing

```yaml
name: Publish NuGet Package

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: read

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Extract version from tag
        id: version
        shell: bash
        run: |
          set -euo pipefail
          VERSION="${GITHUB_REF_NAME#v}"
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"

      - name: Pack
        run: |
          set -euo pipefail
          dotnet pack src/MyLibrary/MyLibrary.csproj \
            -c Release \
            -p:Version=${{ steps.version.outputs.version }} \
            -o ./nupkgs

      - name: Push to nuget.org
        run: |
          set -euo pipefail
          dotnet nuget push ./nupkgs/*.nupkg \
            --api-key ${{ secrets.NUGET_API_KEY }} \
            --source https://api.nuget.org/v3/index.json \
            --skip-duplicate
```

The `--skip-duplicate` flag prevents failures when a package version is already published (idempotent retries).

### Publishing to GitHub Packages

```yaml
- name: Push to GitHub Packages
  run: |
    set -euo pipefail
    dotnet nuget push ./nupkgs/*.nupkg \
      --api-key ${{ secrets.GITHUB_TOKEN }} \
      --source https://nuget.pkg.github.com/${{ github.repository_owner }}/index.json \
      --skip-duplicate
```

### Publishing to Both Feeds

Publish to nuget.org for public consumption and GitHub Packages for organization-internal pre-release:

```yaml
- name: Push to nuget.org (stable releases)
  if: "!contains(steps.version.outputs.version, '-')"
  run: |
    set -euo pipefail
    dotnet nuget push ./nupkgs/*.nupkg \
      --api-key ${{ secrets.NUGET_API_KEY }} \
      --source https://api.nuget.org/v3/index.json \
      --skip-duplicate

- name: Push to GitHub Packages (all versions)
  run: |
    set -euo pipefail
    dotnet nuget push ./nupkgs/*.nupkg \
      --api-key ${{ secrets.GITHUB_TOKEN }} \
      --source https://nuget.pkg.github.com/${{ github.repository_owner }}/index.json \
      --skip-duplicate
```

Pre-release versions (containing `-` like `1.2.3-preview.1`) go only to GitHub Packages; stable versions go to both.

---

## Container Image Build and Push

### Dockerfile-Based Build with docker/build-push-action

For projects with a custom Dockerfile -- see [skill:dotnet-devops] `references/containers.md` for Dockerfile authoring guidance:

```yaml
name: Publish Container Image

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: read
  packages: write

jobs:
  container:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
```

### SDK Container Publish (Dockerfile-Free)

Use .NET SDK container publish for projects without a Dockerfile -- see [skill:dotnet-devops] `references/containers.md` for `PublishContainer` MSBuild configuration:

```yaml
- name: Setup .NET
  uses: actions/setup-dotnet@v4
  with:
    dotnet-version: '8.0.x'

- name: Log in to GHCR
  run: |
    set -euo pipefail
    echo "${{ secrets.GITHUB_TOKEN }}" | \
      docker login ghcr.io -u ${{ github.actor }} --password-stdin

- name: Publish container image
  run: |
    set -euo pipefail
    VERSION="${GITHUB_REF_NAME#v}"
    dotnet publish src/MyApp/MyApp.csproj \
      -c Release \
      -p:PublishProfile=DefaultContainer \
      -p:ContainerRegistry=ghcr.io \
      -p:ContainerRepository=${{ github.repository }} \
      -p:ContainerImageTags="\"${VERSION};latest\""
```

### Push to Multiple Registries

Push to GHCR and DockerHub from the same workflow:

```yaml
- name: Log in to GHCR
  uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}

- name: Log in to DockerHub
  uses: docker/login-action@v3
  with:
    username: ${{ secrets.DOCKERHUB_USERNAME }}
    password: ${{ secrets.DOCKERHUB_TOKEN }}

- name: Extract metadata
  id: meta
  uses: docker/metadata-action@v5
  with:
    images: |
      ghcr.io/${{ github.repository }}
      ${{ secrets.DOCKERHUB_USERNAME }}/${{ github.event.repository.name }}
    tags: |
      type=semver,pattern={{version}}

- name: Build and push to both registries
  uses: docker/build-push-action@v6
  with:
    context: .
    push: true
    tags: ${{ steps.meta.outputs.tags }}
    labels: ${{ steps.meta.outputs.labels }}
```

### Push to Azure Container Registry (ACR)

```yaml
- name: Log in to ACR
  uses: docker/login-action@v3
  with:
    registry: ${{ secrets.ACR_LOGIN_SERVER }}
    username: ${{ secrets.ACR_USERNAME }}
    password: ${{ secrets.ACR_PASSWORD }}

- name: Build and push to ACR
  uses: docker/build-push-action@v6
  with:
    context: .
    push: true
    tags: ${{ secrets.ACR_LOGIN_SERVER }}/myapp:${{ github.ref_name }}
```

### Native AOT Container Publish

Publish a Native AOT binary as a container image. AOT configuration is owned by [skill:dotnet-tooling]; this shows the CI pipeline step only:

```yaml
- name: Publish AOT container
  run: |
    set -euo pipefail
    dotnet publish src/MyApp/MyApp.csproj \
      -c Release \
      -r linux-x64 \
      -p:PublishAot=true \
      -p:PublishProfile=DefaultContainer \
      -p:ContainerRegistry=ghcr.io \
      -p:ContainerRepository=${{ github.repository }} \
      -p:ContainerBaseImage=mcr.microsoft.com/dotnet/runtime-deps:8.0-noble-chiseled
```

The `runtime-deps` base image is sufficient for AOT binaries since they include the runtime.

---

## Artifact Signing

### NuGet Package Signing

Sign NuGet packages with a certificate for tamper detection:

```yaml
- name: Sign NuGet packages
  run: |
    set -euo pipefail
    dotnet nuget sign ./nupkgs/*.nupkg \
      --certificate-path ${{ runner.temp }}/signing-cert.pfx \
      --certificate-password ${{ secrets.CERT_PASSWORD }} \
      --timestamper http://timestamp.digicert.com
```

For CI, extract the certificate from a base64-encoded secret:

```yaml
- name: Decode signing certificate
  shell: bash
  run: |
    set -euo pipefail
    echo "${{ secrets.SIGNING_CERT_BASE64 }}" | base64 -d > "${{ runner.temp }}/signing-cert.pfx"

- name: Sign NuGet packages
  run: |
    set -euo pipefail
    dotnet nuget sign ./nupkgs/*.nupkg \
      --certificate-path ${{ runner.temp }}/signing-cert.pfx \
      --certificate-password ${{ secrets.CERT_PASSWORD }} \
      --timestamper http://timestamp.digicert.com

- name: Clean up certificate
  if: always()
  run: rm -f "${{ runner.temp }}/signing-cert.pfx"
```

### Container Image Signing with Sigstore

Sign container images with keyless signing via sigstore/cosign:

```yaml
- name: Install cosign
  uses: sigstore/cosign-installer@v3

- name: Sign container image
  env:
    COSIGN_EXPERIMENTAL: '1'
  run: |
    set -euo pipefail
    cosign sign --yes ghcr.io/${{ github.repository }}@${{ steps.build.outputs.digest }}
```

Keyless signing uses GitHub's OIDC token -- no private key management required.

---

## SBOM Generation

### Microsoft SBOM Tool

Generate a Software Bill of Materials for supply chain transparency:

```yaml
- name: Generate SBOM
  uses: microsoft/sbom-action@v0
  with:
    BuildDropPath: ./nupkgs
    PackageName: MyLibrary
    PackageVersion: ${{ steps.version.outputs.version }}
    NamespaceUriBase: https://github.com/${{ github.repository }}

- name: Upload SBOM
  uses: actions/upload-artifact@v4
  with:
    name: sbom-${{ steps.version.outputs.version }}
    path: ./nupkgs/_manifest/
    retention-days: 365
```

### SBOM for Container Images

```yaml
- name: Generate container SBOM
  uses: anchore/sbom-action@v0
  with:
    image: ghcr.io/${{ github.repository }}:${{ steps.version.outputs.version }}
    artifact-name: container-sbom
    output-file: container-sbom.spdx.json
```

### Attach SBOM to GitHub Release

```yaml
- name: Create GitHub Release with SBOM
  uses: softprops/action-gh-release@v2
  with:
    files: |
      ./nupkgs/*.nupkg
      ./nupkgs/_manifest/spdx_2.2/manifest.spdx.json
    generate_release_notes: true
```

---

## Conditional Publishing on Tags and Releases

### Tag Pattern Matching

```yaml
on:
  push:
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+'         # stable: v1.2.3
      - 'v[0-9]+.[0-9]+.[0-9]+-*'        # pre-release: v1.2.3-preview.1

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - name: Determine release type
        id: release-type
        shell: bash
        run: |
          set -euo pipefail
          VERSION="${GITHUB_REF_NAME#v}"
          if [[ "$VERSION" == *-* ]]; then
            echo "prerelease=true" >> "$GITHUB_OUTPUT"
          else
            echo "prerelease=false" >> "$GITHUB_OUTPUT"
          fi
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"
```

### Release-Triggered Publishing

Publish only when a GitHub Release is created (provides manual approval gate):

```yaml
on:
  release:
    types: [published]

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.release.tag_name }}

      - name: Extract version
        id: version
        shell: bash
        run: |
          set -euo pipefail
          VERSION="${{ github.event.release.tag_name }}"
          VERSION="${VERSION#v}"
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"

      - name: Pack and publish
        run: |
          set -euo pipefail
          dotnet pack -c Release -p:Version=${{ steps.version.outputs.version }} -o ./nupkgs
          dotnet nuget push ./nupkgs/*.nupkg \
            --api-key ${{ secrets.NUGET_API_KEY }} \
            --source https://api.nuget.org/v3/index.json \
            --skip-duplicate
```

---

## Agent Gotchas

1. **Always use `--skip-duplicate` with `dotnet nuget push`** -- without it, re-running a publish workflow for an already-published version fails the job instead of being idempotent.
2. **Never hardcode API keys in workflow files** -- use `${{ secrets.NUGET_API_KEY }}` or environment-scoped secrets for all credentials.
3. **Use `set -euo pipefail` in all multi-line bash steps** -- without `pipefail`, a failure in a piped command does not propagate, producing false-green CI.
4. **Clean up signing certificates in an `if: always()` step** -- temporary files with private key material must be removed even when the job fails.
5. **SDK container publish requires Docker daemon** -- `dotnet publish` with `PublishProfile=DefaultContainer` needs Docker installed on the runner; use `ubuntu-latest` which includes Docker.
6. **AOT publish requires matching RID** -- `dotnet publish -r linux-x64` must match the runner OS; do not use `-r win-x64` on `ubuntu-latest`.
7. **Tag-triggered workflows do not run on pull requests** -- tags pushed from PRs still trigger the workflow; use `if: github.ref_type == 'tag'` as an extra guard if needed.
8. **GHCR authentication uses `GITHUB_TOKEN`, not a PAT** -- for public repositories, `packages: write` permission is sufficient; PATs are only needed for cross-repository access.
