# Rollback

## Config rollback
- Trigger workflow Config Rollback.
- Select target environment.
- Select known-good git reference.
- Redeploy previous payloads.

## Infra rollback
- Use previous successful IaC revision and run Infra Deploy with selected environment.
- Validate endpoint and WAF status immediately.
