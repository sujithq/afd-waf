# DevOps setup

## Federated authentication (OIDC)

GitHub OpenID Connect (OIDC) eliminates the need for long-lived Azure credentials stored in secrets. Instead, GitHub requests short-lived access tokens from your Entra tenant on-demand.

### Prerequisites
- Azure subscription with appropriate admin access to configure Entra app registrations and role assignments
- GitHub repository with admin access to configure environments, variables, and secrets

### Step-by-step OIDC setup

1. **Create an Entra application (service principal)**:
   ```bash
   # Using Azure CLI
   az ad app create --display-name "afd-waf-github-ci"
   
   # Save the Application ID (client-id) from output
   # Then create a service principal:
   az ad sp create --id <APPLICATION_ID>
   ```

2. **Add a federated credential for GitHub**:
   ```bash
   # Use Azure Portal or CLI
   az ad app federated-credential create \
     --id <APPLICATION_ID> \
     --parameters @- <<EOF
   {
     "name": "afd-waf-github-dev",
     "issuer": "https://token.actions.githubusercontent.com",
     "subject": "repo:<YOUR_GITHUB_ORG>/<YOUR_REPO>:environment:dev",
     "audiences": ["api://AzureADTokenExchange"]
   }
   EOF
   ```
   Repeat for each environment (dev, test, prod):
   - Replace `environment:dev` with `environment:test` and `environment:prod`
   - Alternatively, use `ref:refs/heads/main` for branch-based triggers

3. **Grant Azure roles to the service principal**:
   ```bash
   # Dev environment - broad permissions for testing
   az role assignment create \
     --assignee-object-id <PRINCIPAL_ID> \
     --role "Contributor" \
     --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<DEV_RG>
   
   # Test and prod - minimal permissions (example)
   az role assignment create \
     --assignee-object-id <PRINCIPAL_ID> \
     --role "CDN Profile Contributor" \
     --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<TEST_RG>
   ```

4. **Configure GitHub repository secrets and variables**:
   - Go to Settings → Environments (or Secrets and variables → Actions)
   - Create environment-specific variables for each tier (dev, test, prod)
   - Add the variables listed in the **Required GitHub variables** section below

### How OIDC flows in workflows

1. GitHub Action runs `Azure/login@v3.0.0` with `client-id`, `tenant-id`, `subscription-id`
2. Action calls GitHub's OIDC provider to get a short-lived token
3. Token is exchanged with your Entra tenant for an Azure access token
4. All subsequent `az` and `terraform` commands use that token (no secrets in logs)
5. Token expires after workflow completes (typically 60 min)

### Security best practices

- Grant the federated identity only the roles it needs per environment (least privilege)
- Use separate Entra apps or credentials per repository for audit trail separation
- Enable managed identity on Azure resources (VMs, Functions) to further reduce credential sprawl
- Audit federated credential assignments periodically: `az ad app federated-credential list --id <APPLICATION_ID>`
- Restrict who can trigger deployments using GitHub branch protection and environment approvals

## Required GitHub variables
- AZURE_CLIENT_ID: Entra application client ID used by GitHub OIDC.
- AZURE_TENANT_ID: Tenant hosting the Entra application.
- AZURE_SUBSCRIPTION_ID: Subscription hosting AFD and WAF policy.
- AZURE_RESOURCE_GROUP: Resource group used by the infra and config deployment workflows.
- AFD_BASE_URL: Base URL used by smoke tests, for example https://contoso.azurefd.net.
- WAF_POLICY_NAME: Front Door WAF policy name used by config deploy and rollback workflows.
- TF_LOCATION: Terraform deployment location, for example swedencentral.
- TF_NAME_PREFIX: Terraform naming prefix, for example acafd.
- APIM_PUBLISHER_EMAIL: APIM publisher email used by Terraform deployment.
- APIM_PUBLISHER_NAME: APIM publisher name used by Terraform deployment.

## Required GitHub secrets
- No long-lived Azure credential secret is required when OIDC is configured.

## Environment protection recommendations
- Require manual approval for test and prod environments.
- Restrict who can deploy to prod environment.
- Enable artifact retention for config deployment manifests.
- Scope GitHub environment variables per environment where values differ.
- Keep workflow permissions minimal: `contents: read` everywhere and `id-token: write` only on Azure deployment jobs.

## Tooling versions validated in this repo
- Terraform CLI: 1.14.9
- Bicep CLI: 0.42.1
- Azure CLI: upgraded at workflow runtime to the latest available package on Ubuntu runners.
- GitHub Actions pins:
  - actions/checkout v6.0.2
  - actions/upload-artifact v4.6.2
  - Azure/login v3.0.0
  - hashicorp/setup-terraform v3.1.2

## Lock file governance

**Why `.terraform.lock.hcl` is committed**:
- Ensures reproducible `terraform init` across CI/CD runs and local development
- Prevents silent provider upgrades that could introduce breaking changes
- Enables auditability: review lock file diffs to see what versions are pinned
- Required for `terraform apply -auto-approve` to work reliably in CI

**Updating lock file**:
- Run `terraform init` locally to refresh locks if providers update
- Commit lock file changes in the same PR as `versions.tf` version constraint updates
- CI will reject lock file changes if `versions.tf` constraints don't align

## AVM governance
- Module intent and pin metadata live in infra/avm/manifest.json.
- CI validates:
  - Manifest exists and has entries.
  - Each entry has a semantic version pin format.
  - Each entry points to an existing file.
  - File contains a matching avm-id marker.

**AVM module versions in this repo (locked)**:
- Bicep WAF: `0.3.3` (br/public)
- Bicep APIM: `0.14.1` (br/public)
- Bicep CDN/AFD: `0.19.2` (br/public)
- Terraform WAF: `0.1.0` (Azure/avm-res-network-frontdoorwebapplicationfirewallpolicy)
- Terraform APIM: `0.0.7` (Azure/avm-res-apimanagement-service)
- Terraform CDN/AFD: `0.1.9` (Azure/avm-res-cdn-profile)

**Why pinned versions**:
- AVM modules are frequently updated; pinning ensures known-good composition
- Update strategy: test new AVM versions in dev first, then update pin in `infra/avm/manifest.json` and corresponding Bicep/Terraform files
- Never auto-update AVM sources in production pipelines
