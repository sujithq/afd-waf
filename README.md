# AFD WAF OData Automation

This repository implements an AVM-first, dual-IaC approach for Azure Front Door and WAF tuning with API Management OData mocks.

## Objectives
- Keep platform provisioning and policy tuning separated.
- Apply evidence-driven WAF exclusions at narrow scope.
- Validate changes in Detection mode before Prevention mode promotion.

## Repository layout
- infra/bicep: Bicep AVM composition.
- infra/terraform: Terraform AVM composition.
- config/waf: environment tuning payloads and schema.
- .github/workflows: CI and CD automation.
- scripts: deployment, smoke, and AVM guardrail helpers.
- docs: architecture and runbooks.

## Quick start
1. Populate environment variables and secrets used by workflows.
2. Run Infra Validate workflow from a pull request.
3. Run Infra Deploy workflow to provision base resources in dev.
4. Commit config/waf changes and run Config Deploy in Detection mode.
5. Run smoke test script and inspect WAF evidence before promotion.
