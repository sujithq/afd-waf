# WAF tuning governance

## Mandatory controls
- Never disable managed rule sets broadly.
- Use rule-level and selector-level exclusions only.
- All changes must include ticket, owner, reason, and expiry.
- Keep common OData query argument exclusions in `config/waf/base/`.
- Keep shared exclusions in the base package because the active AFD default-domain WAF association applies to `/*`.
- Keep API-specific additions in `config/waf/{env}/apis/{api}/` only as candidate policy packages for future separate domains/endpoints.
- Declare API-specific policy packages in `config/waf/api-policies.json` and bind each one to an APIM API name that exists in Terraform.
- Let Terraform derive AFD route paths from the bound APIM API path. Do not create path-scoped AFD WAF associations; Front Door accepts only `/*` for the endpoint default domain security policy association.
- Use lowercase letters, numbers, or hyphens for API policy keys.
- Keep derived API paths unique and non-overlapping across API-specific policy packages.
- Use `disabledBaseExclusions` in an API-specific `exclusions.json` when an API must reject one inherited base allowance.

## Promotion model
1. Dev in Detection mode.
2. Evidence review from WAF logs.
3. Test with approval.
4. Prod with approval and immutable artifact.

## Rollback triggers
- Unexpected increase in blocked legitimate OData requests.
- Security team rejection during post-deploy monitoring.
