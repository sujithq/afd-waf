# DevOps setup

## Federated authentication
- Prefer GitHub OpenID Connect with a federated credential on a Microsoft Entra application instead of storing service principal secrets.
- Grant the workflow identity only the Azure roles it needs for the target environment.
- Add a federated credential per protected environment or branch pattern used by deployment workflows.

## Required GitHub variables
- AZURE_CLIENT_ID: Entra application client ID used by GitHub OIDC.
- AZURE_TENANT_ID: Tenant hosting the Entra application.
- AZURE_SUBSCRIPTION_ID: Subscription hosting AFD and WAF policy.
- AZURE_RESOURCE_GROUP: Resource group used by the infra and config deployment workflows.
- AFD_BASE_URL: Base URL used by smoke tests, for example https://contoso.azurefd.net.
- WAF_POLICY_NAME: Front Door WAF policy name used by config deploy and rollback workflows.
- TF_LOCATION: Terraform deployment location, for example westus2.
- TF_NAME_PREFIX: Terraform naming prefix, for example acafd.
- APIM_PUBLISHER_EMAIL: APIM publisher email used by Terraform deployment.
- APIM_PUBLISHER_NAME: APIM publisher name used by Terraform deployment.

## Required GitHub secrets
- No long-lived Azure credential secret is required when OIDC is configured.

## Environment protection recommendations
- Require manual approval for test and prod environments.
- Restrict who can deploy to prod environment.
- Enable artifact retention for config deployment manifests.
- Scope GitHub environment variables per environment where values differ.
- Keep workflow permissions minimal: `contents: read` everywhere and `id-token: write` only on Azure deployment jobs.

## Tooling versions validated in this repo
- Terraform CLI: 1.14.9
- Bicep CLI: 0.42.1
- Azure CLI: upgraded at workflow runtime to the latest available package on Ubuntu runners.
- GitHub Actions pins:
  - actions/checkout v6.0.2
  - actions/upload-artifact v4.6.2
  - Azure/login v3.0.0
  - hashicorp/setup-terraform v3.1.2

## AVM governance
- Module intent and pin metadata live in infra/avm/manifest.json.
- CI validates:
  - Manifest exists and has entries.
  - Each entry has a semantic version pin format.
  - Each entry points to an existing file.
  - File contains a matching avm-id marker.
