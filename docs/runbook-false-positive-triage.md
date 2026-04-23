# Runbook: OData false positive triage

1. Export last 24h WAF evidence using KQL script.
2. Group by rule id and OData selector usage.
3. Propose minimum exclusion on QueryStringArgNames for selector and specific rule id.
4. Commit change in config/waf/dev.
5. Deploy in Detection mode.
6. Run smoke tests.
7. Re-check evidence and promote after approval.
