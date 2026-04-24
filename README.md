# AFD WAF OData Automation

This repository implements an AVM-first, dual-IaC approach for Azure Front Door and WAF tuning with API Management OData mocks.

## Objectives
- Keep platform provisioning and policy tuning separated.
- Apply evidence-driven WAF exclusions at narrow scope.
- Validate changes in Detection mode before Prevention mode promotion.

## Repository layout
- infra/bicep: Bicep AVM composition.
- infra/terraform: Terraform AVM composition.
- infra/avm/manifest.json: AVM module intent and version pin manifest.
- config/waf: environment tuning payloads and schema.
- .github/workflows: CI and CD automation.
- scripts: deployment, smoke, and AVM guardrail helpers.
- docs: architecture and runbooks.

## Quick start

> **New to this repo?** Start with [GETTING-STARTED.md](GETTING-STARTED.md) for a complete step-by-step walkthrough including local setup, Azure OIDC federation, GitHub configuration, and first deployment. This guide takes ~45–60 minutes and covers everything from scratch.

### Prerequisites
- Terraform CLI: `>= 1.14.9, < 2.0.0` (local)
- Bicep CLI: `>= 0.42.1` (local)
- Azure CLI: latest (workflows auto-upgrade at runtime)
- PowerShell 7+ (for local helper scripts)
- GitHub OIDC federated credentials configured (see docs/devops-setup.md for step-by-step setup)

### Deployment flow

1. **Configure OIDC and GitHub variables** (one-time setup):
   - Follow docs/devops-setup.md step-by-step OIDC section
   - Add GitHub variables listed in devops-setup.md to your repository environments
   - Verify federated credentials: `az ad app federated-credential list --id <APPLICATION_ID>`

2. **Validate locally before pushing**:
   ```bash
   # Validate Bicep
   az bicep build --file infra/bicep/main.bicep

   # Validate Terraform
   cd infra/terraform
   terraform init
   terraform validate
   terraform plan -var-file=env/dev.tfvars -out=tfplan
   ```

3. **Push to branch and open PR**:
   - Infra Validate workflow runs automatically (lint, schema, what-if)
   - Review CI outputs and lock file diff
   - Merge when all checks pass

4. **Deploy infrastructure and WAF configuration** (manual trigger):
   - Run Infra Deploy workflow targeting dev environment with iac=terraform
   - Workflow uses OIDC to authenticate (no secrets in logs)
   - Terraform reads WAF config from `config/waf/{environment}/` JSON files
   - Infrastructure and WAF policy deployed together in single apply
   - Terraform state tracks both infrastructure and WAF configuration

5. **Update WAF configuration** (after initial deployment):
   - Edit `config/waf/{environment}/exclusions.json` or `rule-overrides.json`
   - Push changes and open PR
   - Config Validate workflow checks schema and policy guardrails
   - Run Infra Deploy workflow with iac=terraform to apply config changes
   - Terraform detects configuration drift and applies only WAF policy updates
   - No need to re-provision base infrastructure (AFD, APIM remain unchanged)

6. **Smoke test and evidence collection**:
   - Run `scripts/smoke-odata.ps1` against AFD hostname to generate test traffic
   - Export WAF evidence using KQL template in `scripts/export-waf-evidence.kql`
   - Use findings to refine exclusions in next iteration

## Deployment Model

This repository uses a **unified IaC approach** where both infrastructure provisioning and WAF configuration are managed through Terraform:

- **Infrastructure components** (AFD, APIM, WAF policy resource): Defined in Terraform modules
- **WAF configuration** (exclusions, rule overrides): Stored as JSON in `config/waf/`, read by Terraform
- **Single deployment workflow**: Infra Deploy workflow handles both infrastructure and configuration
- **Declarative updates**: Changes to WAF config JSON files trigger Terraform to update only affected resources

**Benefits:**
- Terraform state tracks all changes (no out-of-band updates)
- WAF config changes deployable independently (Terraform applies minimal diff)
- Version control for all configuration
- Drift detection between desired (JSON) and actual (Azure) state

**Legacy script-based approach (DEPRECATED):**
- `scripts/deploy-config.ps1` and Config Deploy workflow are deprecated
- Kept for reference and emergency fallback only
- New deployments should use Terraform exclusively

