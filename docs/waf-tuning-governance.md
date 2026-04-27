# WAF tuning governance

## Mandatory controls
- Never disable managed rule sets broadly.
- Use rule-level and selector-level exclusions only.
- All changes must include ticket, owner, reason, and expiry.
- Keep common OData query argument exclusions in `config/waf/base/`.
- Keep API-specific additions in `config/waf/{env}/apis/{api}/` so one API does not broaden another API's WAF policy.
- Declare API-specific WAF policies in `config/waf/api-policies.json`.
- Bind each API-specific WAF policy to an APIM API name that exists in Terraform.
- Let Terraform derive AFD route and WAF association paths from the bound APIM API path.
- Use lowercase letters, numbers, or hyphens for API policy keys.
- Keep derived API paths unique and non-overlapping across base and API-specific WAF policies.
- Use `disabledBaseExclusions` in an API-specific `exclusions.json` when an API must reject one inherited base allowance.

## Promotion model
1. Dev in Detection mode.
2. Evidence review from WAF logs.
3. Test with approval.
4. Prod with approval and immutable artifact.

## Rollback triggers
- Unexpected increase in blocked legitimate OData requests.
- Security team rejection during post-deploy monitoring.
