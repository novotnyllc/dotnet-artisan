# GitHub Actions Deploy

Deployment patterns for .NET applications in GitHub Actions: GitHub Pages deployment for documentation sites (Starlight/Docusaurus), container registry push patterns for GHCR and ACR, Azure Web Apps deployment via `azure/webapps-deploy`, GitHub Environments with protection rules for staged rollouts, and rollback strategies for failed deployments.

**Version assumptions:** GitHub Actions workflow syntax v2. `azure/webapps-deploy@v3` for Azure App Service. `azure/login@v2` for Azure credential management. GitHub Environments for deployment gates.

## GitHub Pages Deployment for Documentation

### Static Site Deployment (Starlight/Docusaurus)

Deploy a .NET project's documentation site to GitHub Pages:

```yaml
name: Deploy Docs

on:
  push:
    branches: [main]
    paths:
      - 'docs/**'
      - '.github/workflows/deploy-docs.yml'
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: npm
          cache-dependency-path: docs/package-lock.json

      - name: Install dependencies
        working-directory: docs
        run: npm ci

      - name: Build documentation site
        working-directory: docs
        run: npm run build

      - name: Upload Pages artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: docs/dist

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

**Key decisions:**

- `concurrency.cancel-in-progress: false` prevents cancelling an in-progress Pages deployment
- `id-token: write` permission is required for the Pages deployment token
- Separate `build` and `deploy` jobs allow the deploy job to use the `github-pages` environment with protection rules

### API Documentation from XML Comments

Generate and deploy API reference documentation from .NET XML comments:

```yaml
- name: Setup .NET
  uses: actions/setup-dotnet@v4
  with:
    dotnet-version: '8.0.x'

- name: Build with XML docs
  run: |
    set -euo pipefail
    dotnet build src/MyLibrary/MyLibrary.csproj \
      -c Release \
      -p:GenerateDocumentationFile=true

- name: Generate API docs with docfx
  run: |
    set -euo pipefail
    dotnet tool install -g docfx
    docfx docs/docfx.json

- name: Upload Pages artifact
  uses: actions/upload-pages-artifact@v3
  with:
    path: docs/_site
```

---

## Container Registry Push Patterns

### Push to GHCR with Environment Gates

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      image-digest: ${{ steps.build.outputs.digest }}
    steps:
      - uses: actions/checkout@v4

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push
        id: build
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ghcr.io/${{ github.repository }}:${{ github.sha }}

  deploy-staging:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: staging
      url: https://staging.example.com
    steps:
      - name: Deploy container to staging
        run: |
          set -euo pipefail
          echo "Deploying ghcr.io/${{ github.repository }}@${{ needs.build.outputs.image-digest }} to staging"
          # Platform-specific deployment command here

  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment:
      name: production
      url: https://example.com
    steps:
      - name: Deploy container to production
        run: |
          set -euo pipefail
          echo "Deploying ghcr.io/${{ github.repository }}@${{ needs.build.outputs.image-digest }} to production"
```

### Promote by Digest (Immutable Deployments)

Use image digest references for immutable deployments across environments:

```yaml
- name: Retag for production
  run: |
    set -euo pipefail
    # Pull by digest (immutable), retag for production
    docker pull ghcr.io/${{ github.repository }}@${{ needs.build.outputs.image-digest }}
    docker tag ghcr.io/${{ github.repository }}@${{ needs.build.outputs.image-digest }} \
      ghcr.io/${{ github.repository }}:production
    docker push ghcr.io/${{ github.repository }}:production
```

Digest-based promotion ensures the exact same image bytes are deployed to production, regardless of tag mutations.

---

## Azure Web Apps Deployment

### Deploy via `azure/webapps-deploy`

```yaml
name: Deploy to Azure

on:
  push:
    branches: [main]

permissions:
  contents: read
  id-token: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Publish
        run: |
          set -euo pipefail
          dotnet publish src/MyApp/MyApp.csproj \
            -c Release \
            -o ./publish

      - name: Upload publish artifact
        uses: actions/upload-artifact@v4
        with:
          name: webapp
          path: ./publish

  deploy-staging:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: staging
      url: https://myapp-staging.azurewebsites.net
    steps:
      - name: Download artifact
        uses: actions/download-artifact@v4
        with:
          name: webapp
          path: ./publish

      - name: Login to Azure
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Deploy to Azure Web App
        uses: azure/webapps-deploy@v3
        with:
          app-name: myapp-staging
          package: ./publish

  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment:
      name: production
      url: https://myapp.azurewebsites.net
    steps:
      - name: Download artifact
        uses: actions/download-artifact@v4
        with:
          name: webapp
          path: ./publish

      - name: Login to Azure
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Deploy to Azure Web App
        uses: azure/webapps-deploy@v3
        with:
          app-name: myapp-production
          package: ./publish
```

### Azure Web App with Deployment Slots

Use deployment slots for zero-downtime deployments with pre-swap validation:

```yaml
- name: Deploy to staging slot
  uses: azure/webapps-deploy@v3
  with:
    app-name: myapp-production
    slot-name: staging
    package: ./publish

- name: Validate staging slot
  shell: bash
  run: |
    set -euo pipefail
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
      https://myapp-production-staging.azurewebsites.net/healthz)
    if [ "$HTTP_STATUS" != "200" ]; then
      echo "Health check failed with status $HTTP_STATUS"
      exit 1
    fi

- name: Swap slots
  uses: azure/cli@v2
  with:
    inlineScript: |
      az webapp deployment slot swap \
        --resource-group myapp-rg \
        --name myapp-production \
        --slot staging \
        --target-slot production
```

### OIDC Authentication (Federated Credentials)

Use OIDC for passwordless Azure authentication instead of service principal secrets:

```yaml
- name: Login to Azure (OIDC)
  uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

OIDC requires configuring a federated credential in Azure AD that trusts the GitHub Actions OIDC provider. No client secret is stored in GitHub Secrets.

---

## GitHub Environments with Protection Rules

### Multi-Environment Pipeline

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: dotnet publish -c Release -o ./publish
      - uses: actions/upload-artifact@v4
        with:
          name: app
          path: ./publish

  deploy-dev:
    needs: build
    runs-on: ubuntu-latest
    environment: development
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: app
      - run: echo "Deploy to dev"

  deploy-staging:
    needs: deploy-dev
    runs-on: ubuntu-latest
    environment:
      name: staging
      url: https://staging.example.com
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: app
      - run: echo "Deploy to staging"

  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment:
      name: production
      url: https://example.com
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: app
      - run: echo "Deploy to production"
```

### Protection Rule Configuration

Configure in GitHub Settings > Environments for each environment:

| Environment | Required Reviewers | Wait Timer | Branch Policy |
|-------------|-------------------|------------|---------------|
| development | None | None | Any branch |
| staging | 1 reviewer | None | `main`, `release/*` |
| production | 2 reviewers | 15 minutes | `main` only |

### Environment-Specific Secrets and Variables

Each environment can override repository-level secrets:

```yaml
jobs:
  deploy:
    environment: production
    runs-on: ubuntu-latest
    steps:
      - name: Deploy with environment-specific config
        env:
          # Resolves to the production environment's secret, not the repo-level one
          DB_CONNECTION: ${{ secrets.DB_CONNECTION_STRING }}
          APP_URL: ${{ vars.APP_URL }}
        run: |
          set -euo pipefail
          echo "Deploying to $APP_URL"
```

---

## Rollback Patterns

### Revert Deployment

Re-deploy the previous known-good version on failure:

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - name: Deploy new version
        id: deploy
        continue-on-error: true
        run: |
          set -euo pipefail
          # Deploy logic here
          ./deploy.sh --version ${{ github.sha }}

      - name: Health check
        id: health
        if: steps.deploy.outcome == 'success'
        continue-on-error: true
        shell: bash
        run: |
          set -euo pipefail
          for i in {1..5}; do
            HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://example.com/healthz)
            if [ "$HTTP_STATUS" = "200" ]; then
              echo "Health check passed"
              exit 0
            fi
            sleep 10
          done
          echo "Health check failed after 5 attempts"
          exit 1

      - name: Rollback on failure
        if: steps.deploy.outcome == 'failure' || steps.health.outcome == 'failure'
        run: |
          set -euo pipefail
          echo "Rolling back to previous version"
          # Re-deploy the last known-good artifact
          ./deploy.sh --version ${{ github.event.before }}

      - name: Fail the job if rollback was needed
        if: steps.deploy.outcome == 'failure' || steps.health.outcome == 'failure'
        run: exit 1
```

### Azure Deployment Slot Rollback

Swap back to the previous slot on health check failure:

```yaml
- name: Swap to production
  id: swap
  uses: azure/cli@v2
  with:
    inlineScript: |
      az webapp deployment slot swap \
        --resource-group myapp-rg \
        --name myapp-production \
        --slot staging \
        --target-slot production

- name: Post-swap health check
  id: post-health
  continue-on-error: true
  shell: bash
  run: |
    set -euo pipefail
    sleep 30  # allow swap to stabilize
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://myapp.azurewebsites.net/healthz)
    if [ "$HTTP_STATUS" != "200" ]; then
      echo "Post-swap health check failed"
      exit 1
    fi

- name: Rollback swap on failure
  if: steps.post-health.outcome == 'failure'
  uses: azure/cli@v2
  with:
    inlineScript: |
      az webapp deployment slot swap \
        --resource-group myapp-rg \
        --name myapp-production \
        --slot staging \
        --target-slot production
      echo "Rolled back: swapped staging back to production"
```

### Manual Rollback via workflow_dispatch

Provide a manual trigger for emergency rollbacks:

```yaml
on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Version to roll back to (e.g., v1.2.3)'
        required: true
        type: string
      environment:
        description: 'Target environment'
        required: true
        type: choice
        options:
          - staging
          - production

jobs:
  rollback:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ inputs.version }}

      - name: Publish
        run: |
          set -euo pipefail
          dotnet publish src/MyApp/MyApp.csproj -c Release -o ./publish

      - name: Deploy rollback version
        run: |
          set -euo pipefail
          echo "Rolling back ${{ inputs.environment }} to ${{ inputs.version }}"
          # Platform-specific deployment
```

---

## Agent Gotchas

1. **Use `set -euo pipefail` in all multi-line bash steps** -- without `pipefail`, failures in piped commands are silently swallowed, producing false-green deployments.
2. **Never use `cancel-in-progress: true` for deployment concurrency groups** -- cancelling an in-progress deployment can leave infrastructure in a partially deployed state.
3. **Always run health checks after deployment** -- a successful `deploy` step does not guarantee the application is running correctly; verify with HTTP health checks.
4. **Use `id-token: write` permission for OIDC Azure login** -- without it, the federated credential exchange fails with a cryptic 403 error.
5. **Deployment slot swaps are atomic** -- if the swap fails, both slots retain their original deployments; no partial state.
6. **Never hardcode Azure credentials in workflow files** -- use OIDC federated credentials or environment-scoped secrets; hardcoded secrets in YAML are visible in repository history.
7. **Use digest-based image references for production deployments** -- tags are mutable and can be overwritten; digests are immutable and guarantee the exact image bytes.
8. **Separate build and deploy jobs** -- build artifacts once, deploy to multiple environments from the same artifact to ensure consistency.
