# Architecture

This implementation separates stable infrastructure and frequent WAF tuning changes.

## Stable infra pipeline
- Azure Front Door profile, endpoint, route, and WAF association.
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
