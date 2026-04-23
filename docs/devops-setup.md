# DevOps setup

## Required GitHub secrets
- AZURE_CREDENTIALS: JSON service principal credentials for azure/login.
- AZURE_SUBSCRIPTION_ID: Subscription hosting AFD and WAF policy.
- AZURE_RESOURCE_GROUP: Resource group that contains the WAF policy.
- AFD_BASE_URL: Base URL used by smoke tests, for example https://contoso.azurefd.net.

## Required GitHub variables
- WAF_POLICY_NAME: Front Door WAF policy name used by config deploy and rollback workflows.

## Environment protection recommendations
- Require manual approval for test and prod environments.
- Restrict who can deploy to prod environment.
- Enable artifact retention for config deployment manifests.

## AVM governance
- Module intent and pin metadata live in infra/avm/manifest.json.
- CI validates:
  - Manifest exists and has entries.
  - Each entry has a semantic version pin format.
  - Each entry points to an existing file.
  - File contains a matching avm-id marker.
