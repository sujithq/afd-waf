# WAF tuning governance

## Mandatory controls
- Never disable managed rule sets broadly.
- Use rule-level and selector-level exclusions only.
- All changes must include ticket, owner, reason, and expiry.
- Keep common OData query argument exclusions in `config/waf/base/`.
- Keep shared exclusions in the base package because the active AFD default-domain WAF association applies to `/*`.
- Keep domain-specific additions in `config/waf/{env}/domains/{domain}/` as policy packages for separate domains.
- Declare domain policy packages in `config/waf/api-policies.json` and bind each domain to one or more APIM API names that exist in Terraform.
- Keep domain policies disabled until the hostname is a real FQDN you own and DNS validation can be completed.
- Use the Domain Deploy workflow, not Infra Deploy, for DNS-dependent custom domain creation and route binding.
- Run deployment surfaces in order for new or moved APIs: Infra Deploy, then Config Deploy, then Domain Deploy.
- Do not remove route custom-domain bindings with Infra Deploy. Route custom-domain bindings are Domain Deploy owned and are ignored by the infra Terraform stack.
- Use `dns.zoneName`, `dns.createZone`, and `dns.manageRecords` when Domain Deploy should create an Azure DNS zone and DNS records. Newly created zones still require registrar or parent-zone delegation.
- Optionally set `dnsZoneId` only when you already know the Azure DNS zone resource ID; otherwise prefer the `dns` object.
- Let Terraform derive AFD route paths from the bound APIM API paths. Do not create path-scoped AFD WAF associations; Front Door accepts only `/*` for each domain security policy association.
- Use lowercase letters, numbers, or hyphens for API policy keys.
- Keep derived API paths unique and non-overlapping across domain policy packages.
- Use `disabledBaseExclusions` in a domain-specific `exclusions.json` when a domain must reject one inherited base allowance.
- Re-run Domain Deploy when AFD custom-domain routing or certificates drift. The script preserves existing route custom-domain bindings, refreshes the managed certificate settings, and verifies route binding presence after update.
- Run custom-domain smoke tests after Domain Deploy for each enabled domain/API group.

## Previous deployment fixes
- AFD security policies are domain-scoped in this demo. Path-specific WAF behavior is modeled with separate custom domains rather than path-scoped security-policy associations.
- Infra Deploy creates WAF policy resources but ignores WAF managed rules, custom rules, mode, and enabled state so Config Deploy owns WAF tuning.
- Infra Deploy ignores route custom-domain bindings so Domain Deploy can own DNS-dependent bindings without the next infrastructure apply removing live custom domains.
- Infra Deploy and Config Deploy use saved Terraform plans with environment approval and exact `tfplan` reuse. Apply is skipped when a detailed-exitcode plan reports no changes.
- Domain Deploy refreshes AFD managed-certificate settings because the control plane can show an approved custom domain while an edge node still presents the fallback certificate until the binding is refreshed.

## Promotion model
1. Dev in Detection mode.
2. Evidence review from WAF logs.
3. Test with approval.
4. Prod with approval and immutable artifact.

## Rollback triggers
- Unexpected increase in blocked legitimate OData requests.
- Security team rejection during post-deploy monitoring.
