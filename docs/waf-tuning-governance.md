# WAF tuning governance

## Mandatory controls
- Never disable managed rule sets broadly.
- Use rule-level and selector-level exclusions only.
- All changes must include ticket, owner, reason, and expiry.

## Promotion model
1. Dev in Detection mode.
2. Evidence review from WAF logs.
3. Test with approval.
4. Prod with approval and immutable artifact.

## Rollback triggers
- Unexpected increase in blocked legitimate OData requests.
- Security team rejection during post-deploy monitoring.
