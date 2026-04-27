# Architecture

This implementation separates stable infrastructure and frequent WAF tuning changes.

## Stable infra pipeline
- Azure Front Door profile, endpoint, routes, and one endpoint-domain WAF association for `/*`.
- WAF policy baseline in managed rules mode.
- API Management with two OData mock APIs.

## Config pipeline
- Environment-scoped exclusions and overrides payloads.
- Schema validation and guardrails.
- Detection-first promotion to Prevention mode with manual approvals.

## AVM-first principle
- Prefer AVM modules for Bicep and Terraform.
- Keep composition wrappers for integration logic and exceptions.
- Track version and source governance in CI.
- All module versions are pinned in `infra/avm/manifest.json` for reproducibility.

## Security and reproducibility
- **OIDC federation**: Workflows use short-lived GitHub OIDC tokens instead of long-lived secrets (see docs/devops-setup.md).
- **Lock file commitment**: `.terraform.lock.hcl` is committed to ensure identical provider versions across all runs.
- **Action pinning**: All GitHub Actions are pinned to specific versions (checkout v6.0.2, Azure/login v3.0.0, setup-terraform v3.1.2).
- **Tool versions**: Terraform CLI >= 1.14.9, Bicep CLI >= 0.42.1 (workflows auto-upgrade Azure CLI).
