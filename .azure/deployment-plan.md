# Azure Deployment Plan

Status: Validated

## Summary
Implement an AVM-first platform for AFD plus WAF plus APIM with a separate config pipeline for frequent WAF exclusion and override updates. Stage 2 adds a separate domain deployment workflow for DNS-dependent Azure Front Door custom domains and domain-scoped WAF policy activation.

## Scope
- Provision stable resources via infra pipeline using AVM composition in Bicep and Terraform.
- Manage WAF tuning via config pipeline using schema-validated JSON payloads.
- Expose four APIM mock OData APIs for safe detection-first validation.
- Keep AFD custom domain creation out of the infra Terraform stack.
- Create AFD custom domains from a separate workflow only for `config/waf/api-policies.json` domain policies with `enabled = true`.
- Bind each enabled domain's API routes to its custom domain while keeping default-endpoint routes available for smoke testing.
- Associate each enabled custom domain with its rendered domain WAF policy.
- Keep disabled domains as declarative config only, with no DNS-dependent Azure resources created.

## Domain Prerequisites
- A real FQDN that you own for each enabled domain, for example `api-a.contoso.com` and `api-b.contoso.com`.
- DNS authority to create the Front Door validation TXT record and traffic CNAME or alias record.
- No existing Front Door or CDN custom domain using the same hostname.
- Time for Azure managed certificate issuance after DNS validation.

## Recipe
- Infrastructure provisioning patterns: Bicep and Terraform.
- CI and CD: GitHub Actions.

## Validation Path
1. Run infra validation workflow for Bicep and Terraform.
2. Run config validation workflow for schema and guardrails.
3. Validate Terraform for the infra and config stacks with backend disabled.
4. Deploy to dev in detection mode.
5. Run Domain Deploy after DNS-ready hostnames are configured.
6. Add DNS validation and CNAME or alias records for enabled custom domains.
7. Run smoke tests against both the default endpoint and custom domain hostnames.
8. Promote with approvals to test and prod.

## Validation Proof
1. `terraform init -upgrade=false` (from `infra/terraform`) -> Success, providers and pinned AVM modules initialized.
2. `terraform validate` (from `infra/terraform`) -> `Success! The configuration is valid.`
3. `az bicep build --file ./main.bicep` (from `infra/bicep`) -> Success (no build errors).
4. `az deployment group what-if --resource-group McapsGovernance --name afd-apim-contract-check --template-file ./main.bicep --parameters ./env/dev.parameters.json` -> Success, preview shows expected creates and no blocking template/contract errors.
5. `pwsh -File ./scripts/check-avm-versions.ps1` -> `AVM governance check passed`.
6. Stage 2 `./scripts/test-waf-config.ps1` -> `WAF config validation passed`.
7. Stage 2 `terraform -chdir=infra/terraform validate` with backend disabled -> `Success! The configuration is valid.`
8. Stage 2 `terraform -chdir=infra/terraform-config validate` with backend disabled -> `Success! The configuration is valid.`
9. Separate domain workflow script dry run with current disabled domain config -> `No enabled domain policies found in config/waf/api-policies.json. Nothing to create.`
