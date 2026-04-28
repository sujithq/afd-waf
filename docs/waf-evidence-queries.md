# WAF evidence queries

Use these queries in the Log Analytics workspace connected to Azure Front Door diagnostics. Always adjust the time window and hostnames for the environment under test.

This workspace uses `policy_s` for the Front Door WAF policy name. Do not project `policyName_s` unless you have first confirmed that column exists in your own `AzureDiagnostics` schema.

Use `contains` for URL path fragments such as `/odata`. KQL `has` is term-based, so `requestUri_s has "/odata"` can miss paths like `/odata1/Entities`.

## Recent WAF rule matches

Shows rule matches for OData traffic. In Detection mode this is the main proof that rules are evaluating, even when the HTTP response is 2xx.

If this query returns no rows, that does not mean traffic is missing. `FrontDoorWebApplicationFirewallLog` only contains requests that matched a WAF rule. Normal allowed traffic with no WAF match appears in `FrontDoorAccessLog` instead.

```kql
AzureDiagnostics
| where TimeGenerated > ago(2h)
| where ResourceProvider == "MICROSOFT.CDN"
| where Category == "FrontDoorWebApplicationFirewallLog"
| extend requestUri = tostring(requestUri_s)
| where requestUri contains "/odata"
| project TimeGenerated, hostName_s, policy_s, action_s, ruleName_s, details_msg_s, requestUri_s, trackingReference_s
| order by TimeGenerated desc
```

## Check whether Front Door is logging

Use this first when a WAF-only query returns no rows. It proves whether the workspace is receiving Front Door diagnostics and shows the newest event per category.

```kql
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where ResourceProvider == "MICROSOFT.CDN"
| summarize Rows = count(), LastSeen = max(TimeGenerated) by Category
| order by Rows desc
```

Then compare AccessLog and WAF rows for OData traffic. This is the best query when a smoke request returns HTTP 200 but the WAF query is empty.

```kql
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where ResourceProvider == "MICROSOFT.CDN"
| where Category in ("FrontDoorAccessLog", "FrontDoorWebApplicationFirewallLog")
| where requestUri_s contains "/odata"
| project TimeGenerated, Category, hostName_s, policy_s, action_s, ruleName_s, httpStatusCode_s, details_msg_s, requestUri_s, trackingReference_s
| order by TimeGenerated desc
```

Expected interpretation:

- `FrontDoorAccessLog` rows with no matching WAF rows means the request reached Front Door but did not match a WAF rule.
- `FrontDoorWebApplicationFirewallLog` rows with `action_s` set to `Log` or `AnomalyScoring` means the request matched WAF while the policy was still allowing the response, usually because the policy is in Detection mode.
- `FrontDoorWebApplicationFirewallLog` rows with `action_s` set to `Block` means WAF blocked or would block that request, depending on policy mode and rule evaluation.

## Matches by policy and rule

Use this to prove that domain-specific policies are active and which managed rules are matching.

```kql
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where ResourceProvider == "MICROSOFT.CDN"
| where Category == "FrontDoorWebApplicationFirewallLog"
| summarize Matches = count() by policy_s, ruleName_s, action_s, bin(TimeGenerated, 15m)
| order by TimeGenerated desc, Matches desc
```

## Domain A versus domain B OData evidence

Compares the demo domains so you can show that each hostname is using its own policy package.

```kql
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where ResourceProvider == "MICROSOFT.CDN"
| where Category in ("FrontDoorAccessLog", "FrontDoorWebApplicationFirewallLog")
| where hostName_s in ("api-a.wafdemo.squintelier.net", "api-b.wafdemo.squintelier.net")
| project TimeGenerated, Category, hostName_s, policy_s, action_s, ruleName_s, httpStatusCode_s, routingRuleName_s, requestUri_s, trackingReference_s
| order by TimeGenerated desc
```

## Requests blocked by WAF

Use this after switching a non-prod policy to Prevention mode. WAF blocks are usually 403 responses with action `Block`.

```kql
AzureDiagnostics
| where TimeGenerated > ago(2h)
| where ResourceProvider == "MICROSOFT.CDN"
| where Category == "FrontDoorWebApplicationFirewallLog"
| where action_s =~ "Block"
| project TimeGenerated, hostName_s, policy_s, ruleName_s, action_s, details_msg_s, requestUri_s, trackingReference_s
| order by TimeGenerated desc
```

## Correlate a blocked smoke request

Paste the `x-azure-ref` value printed by `scripts/smoke-odata-waf-block.ps1` into `trackingReference`. This links the smoke result to the WAF log row.

```kql
let trackingReference = "PASTE_X_AZURE_REF_HERE";
AzureDiagnostics
| where TimeGenerated > ago(2h)
| where ResourceProvider == "MICROSOFT.CDN"
| where Category in ("FrontDoorAccessLog", "FrontDoorWebApplicationFirewallLog")
| where trackingReference_s == trackingReference
| project TimeGenerated, Category, hostName_s, policy_s, action_s, ruleName_s, httpStatusCode_s, requestUri_s, details_msg_s, routingRuleName_s, trackingReference_s
| order by TimeGenerated asc
```

## Exclusion candidate query arguments

Use this when a legitimate OData query is blocked or matched. It extracts the query string so you can decide which query argument name should become a selector-level exclusion.

```kql
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where ResourceProvider == "MICROSOFT.CDN"
| where Category == "FrontDoorWebApplicationFirewallLog"
| where requestUri_s contains "/odata"
| extend queryString = tostring(split(requestUri_s, "?")[1])
| extend firstQueryName = tostring(split(queryString, "=")[0])
| project TimeGenerated, hostName_s, policy_s, action_s, ruleName_s, firstQueryName, requestUri_s, details_msg_s
| order by TimeGenerated desc
```

## Expected blocked smoke sample

In dev and test the default `waf_mode` is Detection, so this request should return 2xx but still produce WAF evidence if a rule matches. To prove an HTTP block, switch a non-prod environment to Prevention mode first with the direct Azure CLI helper:

```powershell
./scripts/set-waf-mode.ps1 -Environment dev -Mode Prevention -SubscriptionId <subscription-id> -NamePrefix acafd -Scope Domains -DomainName domain-a
```

This changes the live WAF policy mode without running Terraform. Update the matching `infra/terraform-config/env/<environment>.tfvars` later only if you want Terraform desired state to keep that mode.

Run a query parameter that is not fully excluded for the target policy. The best observed demo variable in this repository is `$filter` with an OData function value such as `contains(Name,'a')`:

- `$filter` is included in the shared base OData query-name exclusions, but those exclusions target `QueryStringArgNames`.
- The false positive is caused by the `$filter` query value, for example `contains(Name,'a')`, matching SQLi managed rules.
- Recent live WAF logs showed `$filter=contains(Name,'a')` and `$filter=startswith(Name,'I')` matching SQLi rules such as `942200`, `942360`, and `942370`, followed by `949110` anomaly-score evaluation.
- The same variable can later be allowed by adding narrow `QueryStringArgValues` exclusions for `$filter` on the matching rule IDs.

That gives a clean before/after story: not excluded -> WAF match or block, then add the exclusion -> request is allowed.

Use this request after the domain A policy is in Prevention mode:

```powershell
./scripts/smoke-odata-waf-block.ps1 -BaseUrl https://api-a.wafdemo.squintelier.net -Path odata1 -QueryString '$filter=contains(Name,''a'')'
```

After validating the block, add selector-level exclusions to `config/waf/{environment}/domains/domain-a/exclusions.json`, then run Config Deploy again. Keep them as narrow as possible, for example:

```json
{
	"matchVariable": "QueryStringArgValues",
	"selectorMatchOperator": "Equals",
	"selector": "$filter",
	"ruleSet": "Microsoft_DefaultRuleSet_2.1",
	"ruleGroup": "SQLI",
	"ruleId": "942200"
}
```

Repeat only for the specific rule IDs proven by WAF logs, such as `942370` or `942360`, rather than broadly disabling SQLi inspection.

Other OData query names worth testing when you want additional false-positive candidates are `$apply`, `$compute`, `$format`, and `$search`. Keep the final exclusion selector as narrow as possible: use `QueryStringArgValues` when the value caused the match and `QueryStringArgNames` only when the argument name itself caused the match.

Switch the policy back to Detection after the demo if needed:

```powershell
./scripts/set-waf-mode.ps1 -Environment dev -Mode Detection -SubscriptionId <subscription-id> -NamePrefix acafd -Scope Domains -DomainName domain-a
```
