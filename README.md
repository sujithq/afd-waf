# AFD WAF OData Automation

This repository implements an AVM-first, dual-IaC approach for Azure Front Door and WAF tuning with API Management OData mocks.

## Objectives
- Keep platform provisioning and policy tuning separated.
- Apply evidence-driven WAF exclusions at narrow scope.
- Validate changes in Detection mode before Prevention mode promotion.

## Repository layout
- infra/bicep: Bicep AVM composition.
- infra/bicep-config: Bicep WAF configuration deployment.
- infra/terraform: Terraform AVM composition.
- infra/terraform-config: Terraform WAF configuration deployment.
- infra/avm/manifest.json: AVM module intent and version pin manifest.
- config/waf: environment tuning payloads and schema.
- .github/workflows: CI and CD automation.
- scripts: deployment, smoke, and AVM guardrail helpers.
- docs: architecture and runbooks.

## Quick start

> **New to this repo?** Start with [GETTING-STARTED.md](GETTING-STARTED.md) for a complete step-by-step walkthrough including local setup, Azure OIDC federation, GitHub configuration, and first deployment. This guide takes ~45–60 minutes and covers everything from scratch.

> **Quick Start Option:** If you prefer to use GitHub workflows instead of local setup, see the [Quick Start with Workflows](GETTING-STARTED.md#quick-start-with-workflows) section after completing OIDC setup. You can bootstrap the Terraform backend, deploy infrastructure, and apply WAF configuration through GitHub Actions.

### Available Workflows

All workflows support manual triggering (`workflow_dispatch`):

1. **Bootstrap** - One-time setup for Terraform backend storage and backend RBAC
2. **Infra Deploy** - Deploys Azure infrastructure (AFD, WAF, APIM)
3. **Config Deploy** - Applies WAF configuration with Terraform or Bicep
4. **Infra Validate** - Validates infrastructure code (runs on PR and manual trigger)
5. **Config Validate** - Validates WAF configuration (runs on PR and manual trigger)
6. **Config Rollback** - Emergency rollback to known-good configuration

### Workflow Chaining

Workflows can be chained for streamlined deployment:
- **Infra Deploy** can automatically trigger **Config Deploy** after infrastructure deployment by enabling the `run_config_deploy` option

### Prerequisites
- Terraform CLI: `>= 1.14.9, < 2.0.0` (local)
- Bicep CLI: `>= 0.42.1` (local)
- Azure CLI: latest (workflows auto-upgrade at runtime)
- PowerShell 7+ (for local helper scripts)
- GitHub OIDC federated credentials configured before running workflows. The Bootstrap workflow needs the main-branch federated credential; deploy workflows need the `dev`, `test`, and `prod` environment federated credentials.
- For the tested Terraform workflow path, the GitHub service principal needs subscription-scope `Contributor`. If the same principal runs Bootstrap end-to-end, it also needs permission to create role assignments, such as `User Access Administrator` during bootstrap.

### Deployment flow

#### Option 1: Quick Start with Workflows (Recommended)

1. **Run Bootstrap workflow** (one-time setup):
   - Go to **Actions → Bootstrap** in GitHub
   - Provide location and backend resource group
   - Provide a backend storage account name or leave it blank to auto-generate one
   - Bootstrap creates the backend resource group, storage account, `tfstate` container, and backend RBAC
   - Note the output values for GitHub variables

2. **Configure GitHub variables** (see [Quick Start with Workflows](GETTING-STARTED.md#quick-start-with-workflows)):
   - Add repository variables: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, etc.
   - Add backend variables from Bootstrap output: `TF_BACKEND_RG`, `TF_BACKEND_SA`

3. **Run Infra Deploy workflow**:
   - Go to **Actions → Infra Deploy**
   - Select environment and `iac=terraform` for the tested path
   - Enable `run_config_deploy` to automatically run config deployment afterwards

4. **Run Config Deploy workflow** (if not chained):
   - Go to **Actions → Config Deploy**
   - Select environment
   - Select `iac=terraform` for the tested path

#### Option 2: Local Development with Manual Steps

1. **Configure OIDC and GitHub variables** (one-time setup):
   - Follow docs/devops-setup.md step-by-step OIDC section
   - Add GitHub variables listed in devops-setup.md to your repository environments
   - Verify federated credentials: `az ad app federated-credential list --id <APPLICATION_ID>`

2. **Validate locally before pushing**:
   ```bash
   # Validate Bicep
   az bicep build --file infra/bicep/main.bicep
   az bicep build --file infra/bicep-config/main.bicep

   # Validate Terraform
   cd infra/terraform
   terraform init -backend=false
   terraform validate
   terraform plan -var-file=env/dev.tfvars -out=tfplan
   ```

3. **Push to branch and open PR**:
   - Infra Validate workflow runs automatically (Bicep build, Terraform fmt/validate, AVM governance)
   - Review CI outputs and lock file diff
   - Merge when all checks pass

4. **Deploy infrastructure** (manual trigger — first time or on infra changes):
   - Run **Infra Deploy** workflow targeting the environment with `iac=terraform`
   - Workflow uses OIDC to authenticate (no secrets in logs)
   - Creates/updates resource group, WAF policy (bare), APIM, and AFD
   - Terraform state tracks all infrastructure resources
   - Outputs `waf_policy_id` and `waf_policy_name` for reference

5. **Deploy WAF configuration** (separate workflow):
   - Run **Config Deploy** workflow targeting the same environment
   - Use the same IaC stack as the infrastructure deployment (`terraform` or `bicep`)
   - Terraform imports the WAF policy created by the infra stack and applies managed rules from JSON
   - Bicep applies the WAF rule-group overrides from the same JSON config files
   - Config-only changes never touch AFD, APIM, or other infrastructure

6. **Update WAF configuration** (ongoing):
   - Edit `config/waf/{environment}/exclusions.json` or `rule-overrides.json`
   - Push changes and open PR; Config Validate workflow checks schema and guardrails
   - Merge to `main`, then run Config Deploy manually for the target environment, or run Infra Deploy with `run_config_deploy=true`
   - Only the WAF policy managed rules are updated; infrastructure is untouched

7. **Smoke test and evidence collection**:
   - Run `scripts/smoke-odata.ps1` against AFD hostname to generate test traffic
   - Export WAF evidence using KQL template in `scripts/export-waf-evidence.kql`
   - Use findings to refine exclusions in next iteration

## Deployment Model

This repository uses a **two-stack IaC model** with separate Terraform configurations and isolated blast radius:

| Responsibility | Terraform stack | Workflow |
|---|---|---|
| Resource group, WAF policy resources, APIM, AFD | `infra/terraform/` | Infra Deploy |
| WAF managed rules, exclusions, rule overrides | `infra/terraform-config/` | Config Deploy |

- **Infra stack** (`infra/terraform/`): Provisions all Azure resources. WAF policies are created bare (no rules). `lifecycle { ignore_changes = [managed_rule, custom_rule, mode, enabled] }` ensures that config-stack rule and mode changes are never reverted by an infra apply.
- **Config stack** (`infra/terraform-config/`): Imports the WAF policies by ID and applies `managed_rule` blocks built from JSON. `config/waf/api-policies.json` declares optional base path patterns and any API-specific policies. API1 protects `/odata1/*`; API2 protects `/odata2/*` in this demo.
- **Bicep config stack** (`infra/bicep-config/`): Applies the same WAF rule-group overrides from JSON when Config Deploy runs with `iac=bicep`.
- **WAF config JSON**: `config/waf/base/` contains shared OData exclusions such as `$select`, `$expand`, `$filter`, and `$orderby`. `config/waf/{env}/` can append environment-level tuning. `config/waf/{env}/apis/{api}/` appends API-only tuning, such as the current `api1` `$search` and `api2` `$customVar` examples, without changing other APIs.

To add another API-specific WAF policy, add it to `config/waf/api-policies.json` with its APIM API name and path patterns, then optionally add `config/waf/{env}/apis/{api}/exclusions.json` and `rule-overrides.json` for API-specific tuning. API keys must be lowercase letters, numbers, or hyphens, the APIM API name must exist in Terraform, and path patterns must start with the APIM API path. Terraform creates the additional WAF policy and AFD path association from the registry. API policies inherit `config/waf/base/`; use `disabledBaseExclusions` in `api-policies.json` when an API must opt out of one inherited base exclusion, such as API1 disallowing `$top` while API2 still allows it.

Preview effective WAF tuning before deployment with `scripts/show-effective-waf-config.ps1 -Environment dev`. The script shows the merged base, environment, and API-specific exclusions for each path-associated policy, including inherited exclusions that are disabled for a specific API. Add `-AsJson` for machine-readable output.

**Benefits of separation:**
- Config changes have isolated blast radius — a broken exclusion cannot affect AFD or APIM
- Infrastructure and WAF configuration are independently deployable and independently rollbackable
- Terraform state for each stack is separate and independently manageable
- Drift detection works per stack; a config drift does not surface as an infra diff

**Legacy script-based approach (fallback only):**
- `scripts/deploy-config.ps1` is retained as an emergency fallback for out-of-band fixes
- Pass `-Force` to skip the interactive confirmation gate
- New deployments should use the Config Deploy workflow exclusively

