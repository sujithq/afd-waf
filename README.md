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
   - Infra Validate workflow runs automatically on `infra/**` changes (lint, schema, what-if)
   - Config Validate workflow runs automatically on `config/waf/**` and WAF module changes
   - Review CI outputs and lock file diff
   - Merge when all checks pass

4. **Deploy base infrastructure** (manual trigger — run once or when infra changes):
   - Run **Infra Deploy** workflow targeting the desired environment
   - Provisions AFD, WAF policy, APIM, and networking via Terraform or Bicep
   - Workflow uses OIDC to authenticate (no secrets in logs)

5. **Deploy WAF config** (separate workflow — run on every tuning change):
   - Commit changes under `config/waf/` (e.g. add a selector to `exclusions.json`)
   - Config Validate CI checks JSON schema and policy guardrails automatically
   - Run **Config Deploy** workflow, select environment and WAF mode
   - Terraform applies `module.waf` only (`-target=module.waf`), leaving infra untouched
   - WAF exclusions and overrides are stored in Terraform state — no out-of-band patch needed

6. **Smoke test and evidence collection**:
   - Run `scripts/smoke-odata.ps1` against AFD hostname to generate test traffic
   - Export WAF evidence using KQL template in `scripts/export-waf-evidence.kql`
   - Use findings to refine exclusions in next iteration

> **`scripts/deploy-config.ps1`** is retained as an emergency fallback for out-of-band patching
> when Terraform is unavailable. Always re-apply via the Config Deploy workflow afterwards to
> keep Terraform state consistent.

