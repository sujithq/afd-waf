# WAF tuning governance

## Mandatory controls
- Never disable managed rule sets broadly.
- Use rule-level and selector-level exclusions only.
- All changes must include ticket, owner, reason, and expiry.
- Keep common OData query argument exclusions in `config/waf/base/`.
- Keep shared exclusions in the base package because the active AFD default-domain WAF association applies to `/*`.
- Keep domain-specific additions in `config/waf/{env}/domains/{domain}/` as policy packages for separate domains.
- Declare domain policy packages in `config/waf/api-policies.json` and bind each domain to one or more APIM API names that exist in Terraform.
- Let Terraform derive AFD route paths from the bound APIM API paths. Do not create path-scoped AFD WAF associations; Front Door accepts only `/*` for each domain security policy association.
- Use lowercase letters, numbers, or hyphens for API policy keys.
- Keep derived API paths unique and non-overlapping across domain policy packages.
- Use `disabledBaseExclusions` in a domain-specific `exclusions.json` when a domain must reject one inherited base allowance.

## Promotion model
1. Dev in Detection mode.
2. Evidence review from WAF logs.
3. Test with approval.
4. Prod with approval and immutable artifact.

## Rollback triggers
- Unexpected increase in blocked legitimate OData requests.
- Security team rejection during post-deploy monitoring.
