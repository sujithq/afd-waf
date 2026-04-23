## Plan: AFD WAF OData DevOps Foundation (AVM-First)

Build an auditable, scalable Azure platform where stable resources are managed by an infra pipeline and frequently changing WAF tuning data is managed by a separate config pipeline. Implement both Terraform and Bicep in parallel with AVM-first composition, use GitHub Actions for CI/CD governance, and expose 2 test OData APIs via APIM mock endpoints to validate WAF OData false-positive tuning without backend compute complexity.

**Steps**
1. Phase 1 - Repository bootstrap and standards: create top-level folders for infra, config, pipelines, scripts, tests, and docs; define naming/versioning conventions for WAF tuning artifacts; define environment model (dev, test, prod). This step blocks all others.
2. Phase 2 - Infrastructure as code (Bicep): add Bicep AVM composition modules for resource group, Log Analytics, AFD profile, AFD endpoint/domain/route, WAF policy (base managed rules only), APIM instance, and WAF association; parameterize per environment with isolated parameter files and version pinning. Depends on step 1.
3. Phase 3 - Infrastructure as code (Terraform): add Terraform root and AVM composition modules mirroring Bicep resource model (resource group, observability, AFD, WAF base, APIM, association); configure remote state pattern and tfvars per environment with version constraints. Depends on step 1. Parallel with step 2.
4. Phase 4 - Config-as-code for WAF tuning: create config schema and environment-specific data files for OData-focused exclusions and narrowly scoped rule overrides; include metadata fields for change ticket, owner, reason, expiry, and related WAF rule IDs from evidence. Depends on step 1.
5. Phase 5 - Config deployment wiring: add deploy logic (Bicep deployment + Terraform apply path) that updates only mutable WAF tuning portions while preserving baseline infra resources; implement detection-first mode toggle, promote to prevention only after verification gate. Depends on steps 2, 3, 4.
6. Phase 6 - APIM test APIs for OData: provision 2 APIM APIs with mock operations that include representative OData query patterns ($filter, $orderby, $select, $expand) and deterministic 200 responses to generate safe test traffic through AFD+WAF. Depends on steps 2 and 3.
7. Phase 7 - CI for validation and quality gates: create GitHub Actions workflows for lint/validate of Bicep and Terraform, AVM marker/version governance checks, JSON schema validation for WAF config, policy guardrails, what-if/plan outputs, and artifact publication. Depends on steps 2, 3, 4.
8. Phase 8 - CD promotion flow: create environment-based GitHub Actions deploy workflows with required approvals; run config deployments in detection mode first, execute smoke tests against APIM OData endpoints, evaluate WAF logs, then allow prevention-mode promotion. Depends on steps 5, 6, 7.
9. Phase 9 - Audit and rollback controls: persist deployment manifests (applied config hash, commit, actor, timestamp, environment), store previous known-good config versions, and implement one-command rollback workflow to prior config package. Depends on step 8.
10. Phase 10 - Operations and evidence loop: define runbook to extract WAF log evidence, map false positives to exact managed rule IDs, propose minimal exclusions, test in dev detection mode, promote with approvals, and close with post-change review metrics. Depends on steps 8 and 9.

**Relevant files**
- .github/workflows/infra-validate.yml - Validate Bicep and Terraform on pull requests.
- .github/workflows/infra-deploy.yml - Deploy stable platform resources to target environment.
- .github/workflows/config-validate.yml - Validate WAF tuning payloads and enforce policy schema.
- .github/workflows/config-deploy.yml - Detection-first WAF tuning deployment with approvals.
- .github/workflows/config-rollback.yml - Restore previous approved WAF config package.
- infra/bicep/main.bicep - Orchestrate AFD, APIM, WAF, diagnostics, and associations.
- infra/bicep/modules/waf-policy-composition.bicep - AVM-first WAF baseline composition.
- infra/bicep/modules/afd-composition.bicep - AVM-first AFD composition.
- infra/bicep/modules/apim-composition.bicep - AVM-first APIM composition.
- infra/bicep/modules/apim-odata-mock-apis.bicep - 2 test OData APIs and operations.
- infra/bicep/env/dev.parameters.json - Dev environment parameters.
- infra/bicep/env/test.parameters.json - Test environment parameters.
- infra/bicep/env/prod.parameters.json - Prod environment parameters.
- infra/terraform/main.tf - Terraform orchestration equivalent of Bicep main.
- infra/terraform/modules/waf-policy-composition/main.tf - AVM-first WAF composition.
- infra/terraform/modules/afd-composition/main.tf - AVM-first AFD composition.
- infra/terraform/modules/apim-composition/main.tf - AVM-first APIM composition.
- scripts/check-avm-versions.ps1 - AVM governance checks in CI.
- infra/terraform/env/dev.tfvars - Dev variables.
- infra/terraform/env/test.tfvars - Test variables.
- infra/terraform/env/prod.tfvars - Prod variables.
- config/waf/schema/waf-tuning.schema.json - Contract for exclusions/overrides payloads.
- config/waf/dev/exclusions.json - Dev exclusion set.
- config/waf/test/exclusions.json - Test exclusion set.
- config/waf/prod/exclusions.json - Prod exclusion set.
- config/waf/dev/rule-overrides.json - Dev rule override set.
- config/waf/test/rule-overrides.json - Test rule override set.
- config/waf/prod/rule-overrides.json - Prod rule override set.
- scripts/deploy-config.ps1 - Apply config-only changes safely.
- scripts/smoke-odata.ps1 - Execute OData query smoke tests through AFD hostname.
- scripts/export-waf-evidence.kql - KQL query template for false-positive evidence extraction.
- docs/architecture.md - Separation-of-concerns architecture and trust boundaries.
- docs/waf-tuning-governance.md - Governance model, approvals, and blast-radius controls.
- docs/runbook-false-positive-triage.md - Detection-to-promotion operational process.
- docs/rollback.md - Rollback triggers and execution steps.

**Verification**
1. Static validation: bicep build passes for all modules and parameters per environment.
2. Static validation: terraform fmt, terraform validate, and terraform plan pass per environment.
3. Config contract validation: every exclusions and override payload validates against schema and policy rules.
4. Security checks: no broad managed rule disables, only narrow rule-level overrides and argument-name exclusions are allowed.
5. Deploy verification in dev: infra deploy completes and AFD route to APIM is reachable.
6. Functional verification: smoke suite executes representative OData queries via AFD; expected 2xx responses from APIM mock APIs.
7. Detection-first verification: config deploy in detection mode shows reduced false positives for targeted OData queries without increasing high-severity alerts.
8. Promotion verification: test and prod deployments require manual approval and immutable build artifact reuse.
9. Rollback verification: rollback workflow restores previous tuning package and recovers expected traffic behavior.
10. Audit verification: deployment metadata and approvals are recorded and queryable.

**Decisions**
- AVM-first for both IaC implementations, with composition wrappers where integration logic is required.
- Include both IaC implementations in one repo with mirrored resource boundaries.
- Use GitHub Actions as the authoritative CI/CD platform.
- Implement 2 OData test APIs as APIM mock endpoints (no backend compute) for fast and low-cost validation.
- Included scope: AFD, WAF policy baseline, APIM, WAF config-as-code, CI/CD, detection-first promotions, rollback, runbooks.
- Excluded scope: production business API backend implementation, custom SIEM integration beyond provided KQL templates, global multi-region DR topology.

**Further Considerations**
1. WAF policy mode defaults: Option A start dev and test in Detection, prod in Prevention after gate; Option B all in Detection initially for one sprint. Recommendation: Option A.
2. State management strategy for Terraform: Option A Azure Storage backend per environment; Option B single backend with workspaces. Recommendation: Option A.
3. APIM tier for non-prod: Option A Developer tier for cost; Option B Premium-like parity testing. Recommendation: Option A with documented production delta.
