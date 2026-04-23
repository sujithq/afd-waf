# Azure Deployment Plan

Status: Validated

## Summary
Implement an AVM-first platform for AFD plus WAF plus APIM with a separate config pipeline for frequent WAF exclusion and override updates.

## Scope
- Provision stable resources via infra pipeline using AVM composition in Bicep and Terraform.
- Manage WAF tuning via config pipeline using schema-validated JSON payloads.
- Expose two APIM mock OData APIs for safe detection-first validation.

## Recipe
- Infrastructure provisioning patterns: Bicep and Terraform.
- CI and CD: GitHub Actions.

## Validation Path
1. Run infra validation workflow for Bicep and Terraform.
2. Run config validation workflow for schema and guardrails.
3. Deploy to dev in detection mode.
4. Run smoke tests and log evidence checks.
5. Promote with approvals to test and prod.

## Validation Proof
1. `terraform init -upgrade=false` (from `infra/terraform`) -> Success, providers and pinned AVM modules initialized.
2. `terraform validate` (from `infra/terraform`) -> `Success! The configuration is valid.`
3. `az bicep build --file ./main.bicep` (from `infra/bicep`) -> Success (no build errors).
4. `az deployment group what-if --resource-group McapsGovernance --name afd-apim-contract-check --template-file ./main.bicep --parameters ./env/dev.parameters.json` -> Success, preview shows expected creates and no blocking template/contract errors.
5. `pwsh -File ./scripts/check-avm-versions.ps1` -> `AVM governance check passed`.
