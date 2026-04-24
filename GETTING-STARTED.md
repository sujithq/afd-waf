# Getting Started: AFD WAF OData Automation

This guide walks you through setting up this repository from scratch, from local environment setup through your first Azure deployment.

**Supported shells**: PowerShell (`pwsh`), Bash, or Zsh on Windows, macOS, or Linux

**Time estimate**: 45–60 minutes (depending on Azure org policies)

**Note**: Most commands are shell-agnostic and work in both PowerShell and bash. Where differences exist (e.g., variable assignment syntax), both variants are shown.

**Table of Contents**
1. [Prerequisites](#prerequisites)
2. [Local Environment Setup](#local-environment-setup)
3. [Azure Subscription Setup](#azure-subscription-setup)
4. [GitHub OIDC Federation Setup](#github-oidc-federation-setup)
5. [GitHub Repository Configuration](#github-repository-configuration)
6. [First Local Validation](#first-local-validation)
7. [First Deployment to Dev](#first-deployment-to-dev)
8. [Testing and Troubleshooting](#testing-and-troubleshooting)

---

## Prerequisites

Before starting, ensure you have:

- **Azure subscription**: With admin or Owner access to create resource groups, app registrations, and role assignments
- **GitHub account and repository**: Admin access to configure secrets, variables, and environments
- **Local machine**: Windows 10+ with PowerShell 7+, or macOS/Linux with bash

---

## Local Environment Setup

### 1. Install Required Tools

**On Windows (PowerShell 7+)**:
```powershell
# Install Terraform (if not already installed)
# Download from https://www.terraform.io/downloads or use Chocolatey:
choco install terraform --version=1.14.9

# Install Bicep
az bicep install

# Install or upgrade Azure CLI
choco install azure-cli

# Verify installations
terraform --version  # Should be >= 1.14.9
az bicep version     # Should be >= 0.42.1
az --version         # Latest available
```

**On macOS**:
```bash
# Using Homebrew
brew install terraform@1.14
brew install bicep
brew install azure-cli

# Verify installations
terraform version
az bicep version
az --version
```

**On Linux**:
```bash
# Using apt (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y terraform

# Install Bicep
az bicep install

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Verify installations
terraform --version
az bicep version
az --version
```

### 2. Clone and Navigate to Repository

**PowerShell** or **bash**:
```bash
git clone https://github.com/<YOUR_ORG>/<YOUR_REPO>.git afd-waf-repo
cd afd-waf-repo
```

### 3. Authenticate to Azure Locally

**PowerShell** or **bash**:
```bash
az login

# If you have multiple subscriptions, select the target one
az account set --subscription <SUBSCRIPTION_ID>

# Verify
az account show
```

---

## Azure Subscription Setup

### 1. Create Resource Groups

Create one resource group per environment (dev, test, prod):

**PowerShell**:
```powershell
# Set variables for convenience
$SUBSCRIPTION_ID = (az account show --query id -o tsv)
$LOCATION = "swedencentral"  # Change to your preferred region

# Create dev resource group
az group create `
  --name afd-waf-dev-rg `
  --location $LOCATION

# Create test resource group
az group create `
  --name afd-waf-test-rg `
  --location $LOCATION

# Create prod resource group
az group create `
  --name afd-waf-prod-rg `
  --location $LOCATION

# List created groups
az group list --query "[].name" -o table
```

**Bash**:
```bash
# Set variables for convenience
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
LOCATION="swedencentral"  # Change to your preferred region

# Create dev resource group
az group create \
  --name afd-waf-dev-rg \
  --location $LOCATION

# Create test resource group
az group create \
  --name afd-waf-test-rg \
  --location $LOCATION

# Create prod resource group
az group create \
  --name afd-waf-prod-rg \
  --location $LOCATION

# List created groups
az group list --query "[].name" -o table
```

### 2. Create Storage Account for Terraform Remote State (Optional but Recommended)

**PowerShell**:
```powershell
# Storage account names must be globally unique and lowercase
$TIMESTAMP = Get-Date -UFormat "%s"
$STORAGE_ACCOUNT = "afdwaftf$TIMESTAMP"

# Create storage account for Terraform state
az storage account create `
  --name $STORAGE_ACCOUNT `
  --resource-group afd-waf-dev-rg `
  --location $LOCATION `
  --sku Standard_LRS

# Create storage container
az storage container create `
  --account-name $STORAGE_ACCOUNT `
  --name tfstate `
  --auth-mode login

Write-Host "Storage Account: $STORAGE_ACCOUNT"
Write-Host "Connection string:"
az storage account show-connection-string `
  --name $STORAGE_ACCOUNT `
  --resource-group afd-waf-dev-rg `
  --query connectionString -o tsv
```

**Bash**:
```bash
# Storage account names must be globally unique and lowercase
STORAGE_ACCOUNT="afdwaftf$(date +%s)"

# Create storage account for Terraform state
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group afd-waf-dev-rg \
  --location $LOCATION \
  --sku Standard_LRS

# Create storage container
az storage container create \
  --account-name $STORAGE_ACCOUNT \
  --name tfstate \
  --auth-mode login

echo "Storage Account: $STORAGE_ACCOUNT"
echo "Connection string:"
az storage account show-connection-string \
  --name $STORAGE_ACCOUNT \
  --resource-group afd-waf-dev-rg \
  --query connectionString -o tsv
```

---

## GitHub OIDC Federation Setup

GitHub OIDC federation replaces long-lived service principal secrets with short-lived tokens. This section walks through the setup.

### 1. Define GitHub Repository Variables

Set these once and reuse them in all OIDC subject strings:

**PowerShell**:
```powershell
$GITHUB_ORG = "<YOUR_GITHUB_ORG>"
$GITHUB_REPO = "<YOUR_REPO>"

# Quick sanity check
Write-Host "GITHUB_ORG=$GITHUB_ORG"
Write-Host "GITHUB_REPO=$GITHUB_REPO"
if ([string]::IsNullOrWhiteSpace($GITHUB_ORG) -or [string]::IsNullOrWhiteSpace($GITHUB_REPO)) {
  throw "Set both GITHUB_ORG and GITHUB_REPO before creating federated credentials."
}
```

**Bash**:
```bash
GITHUB_ORG="<YOUR_GITHUB_ORG>"
GITHUB_REPO="<YOUR_REPO>"
```

### 2. Create an Entra Application

**PowerShell**:
```powershell
# Create the Entra app (service principal)
$APP_NAME = "afd-waf-github-ci"
$APP_RESPONSE = az ad app create --display-name $APP_NAME | ConvertFrom-Json
$APP_ID = $APP_RESPONSE.id
$CLIENT_ID = $APP_RESPONSE.appId

# Create the service principal
az ad sp create --id $CLIENT_ID

# Get your tenant ID
$TENANT_ID = (az account show --query tenantId -o tsv)

Write-Host "App ID (for manifest): $APP_ID"
Write-Host "Client ID (for GitHub): $CLIENT_ID"
Write-Host "Tenant ID (for GitHub): $TENANT_ID"

# Save these values—you'll need them in GitHub configuration
```

**Bash**:
```bash
# Create the Entra app (service principal)
APP_NAME="afd-waf-github-ci"
APP_RESPONSE=$(az ad app create --display-name "$APP_NAME")
APP_ID=$(echo "$APP_RESPONSE" | jq -r '.id')
CLIENT_ID=$(echo "$APP_RESPONSE" | jq -r '.appId')

# Create the service principal
az ad sp create --id "$CLIENT_ID"

# Get your tenant ID
TENANT_ID=$(az account show --query tenantId -o tsv)

echo "App ID (for manifest): $APP_ID"
echo "Client ID (for GitHub): $CLIENT_ID"
echo "Tenant ID (for GitHub): $TENANT_ID"

# Save these values—you'll need them in GitHub configuration
```

### 3. Add Federated Credentials for Each Environment

GitHub OIDC federation requires a federated credential per environment or branch pattern.

**PowerShell**:
```powershell
# Azure CLI cannot parse multi-line JSON from PowerShell inline; write JSON to a temp file

# For dev environment
@{
  name      = "afd-waf-github-dev"
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:dev"
  audiences = @("api://AzureADTokenExchange")
} | ConvertTo-Json | Out-File "$env:TEMP\fic.json" -Encoding utf8
az ad app federated-credential create --id $APP_ID --parameters "@$env:TEMP\fic.json"

# For test environment
@{
  name      = "afd-waf-github-test"
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:test"
  audiences = @("api://AzureADTokenExchange")
} | ConvertTo-Json | Out-File "$env:TEMP\fic.json" -Encoding utf8
az ad app federated-credential create --id $APP_ID --parameters "@$env:TEMP\fic.json"

# For prod environment
@{
  name      = "afd-waf-github-prod"
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:prod"
  audiences = @("api://AzureADTokenExchange")
} | ConvertTo-Json | Out-File "$env:TEMP\fic.json" -Encoding utf8
az ad app federated-credential create --id $APP_ID --parameters "@$env:TEMP\fic.json"

# For PR/merge-to-main branch (optional)
@{
  name      = "afd-waf-github-main"
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main"
  audiences = @("api://AzureADTokenExchange")
} | ConvertTo-Json | Out-File "$env:TEMP\fic.json" -Encoding utf8
az ad app federated-credential create --id $APP_ID --parameters "@$env:TEMP\fic.json"

# Verify all credentials were created
az ad app federated-credential list --id $APP_ID
```

**Bash**:
```bash
# For dev environment
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters "$(cat <<EOF
{
  "name": "afd-waf-github-dev",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:dev",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF
)"

# For test environment
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters "$(cat <<EOF
{
  "name": "afd-waf-github-test",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:test",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF
)"

# For prod environment
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters "$(cat <<EOF
{
  "name": "afd-waf-github-prod",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:prod",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF
)"

# For PR/merge-to-main branch (optional)
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters "$(cat <<EOF
{
  "name": "afd-waf-github-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF
)"

# Verify all credentials were created
az ad app federated-credential list --id "$APP_ID"
```

### 4. Grant Azure Roles to the Service Principal

Grant the service principal only the roles it needs per environment (least privilege).

**PowerShell**:
```powershell
# Get the service principal object ID
$SP_OBJECT_ID = (az ad sp show --id $CLIENT_ID --query id -o tsv)

# For DEV: Broad access for testing
az role assignment create `
  --assignee-object-id $SP_OBJECT_ID `
  --assignee-principal-type ServicePrincipal `
  --role "Contributor" `
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/afd-waf-dev-rg"

# For TEST: Restricted to necessary roles
az role assignment create `
  --assignee-object-id $SP_OBJECT_ID `
  --assignee-principal-type ServicePrincipal `
  --role "CDN Profile Contributor" `
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/afd-waf-test-rg"

az role assignment create `
  --assignee-object-id $SP_OBJECT_ID `
  --assignee-principal-type ServicePrincipal `
  --role "API Management Service Contributor" `
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/afd-waf-test-rg"

# For PROD: Minimal + approval gates (enforced in GitHub)
az role assignment create `
  --assignee-object-id $SP_OBJECT_ID `
  --assignee-principal-type ServicePrincipal `
  --role "CDN Profile Contributor" `
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/afd-waf-prod-rg"

# Verify role assignments
az role assignment list `
  --assignee-object-id $SP_OBJECT_ID `
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/afd-waf-prod-rg" `
  --include-inherited `
  --output table

# Note: If you query with --assignee $CLIENT_ID and see no rows, verify $CLIENT_ID is set.
# For deterministic results, prefer --assignee-object-id with an explicit scope.
```

**Bash**:
```bash
# Get the service principal object ID
SP_OBJECT_ID=$(az ad sp show --id "$CLIENT_ID" --query id -o tsv)

# For DEV: Broad access for testing
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/afd-waf-dev-rg"

# For TEST: Restricted to necessary roles
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "CDN Profile Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/afd-waf-test-rg"

az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "API Management Service Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/afd-waf-test-rg"

# For PROD: Minimal + approval gates (enforced in GitHub)
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "CDN Profile Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/afd-waf-prod-rg"

# Verify role assignments
az role assignment list \
  --assignee-object-id "$SP_OBJECT_ID" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/afd-waf-prod-rg" \
  --include-inherited \
  --output table

# Note: If you query with --assignee "$CLIENT_ID" and see no rows, verify CLIENT_ID is set.
# For deterministic results, prefer --assignee-object-id with an explicit scope.
```

---

## GitHub Repository Configuration

### 1. Create GitHub Environments

Create three environments in your GitHub repository for dev, test, and prod.

1. Go to **Settings → Environments**
2. Click **New environment** and create:
   - `dev`
   - `test`
   - `prod`

**For test and prod environments**, enable deployment protection rules:
- Click the environment
- Under "Deployment branches and environments", select "Selected branches and tags"
- Under "Required reviewers", add 1–2 team members
- Save

### 2. Add GitHub Variables

Add the following **variables**. Variables are **not** secrets; they're configuration values.

GitHub supports two scopes for variables:
- **Repository variables** — set once at repository level, available to all workflows regardless of environment.
- **Environment variables** — set per environment (`dev`, `test`, `prod`); override a repository variable of the same name when the workflow targets that environment.

**Repository variables** (go to **Settings → Secrets and variables → Actions → Variables**, *not* inside an environment):
```
AZURE_CLIENT_ID: <from step 1 of GitHub OIDC Federation Setup>
AZURE_TENANT_ID: <from step 1 of GitHub OIDC Federation Setup>
AZURE_SUBSCRIPTION_ID: <your subscription ID from az account show>
TF_LOCATION: swedencentral
TF_NAME_PREFIX: acafd  (or your naming prefix)
```

> **Note — production practice**: Sharing a single app registration and subscription across all environments is fine for this demo repo. In a real-world setup, each environment (`dev`, `test`, `prod`) should have its **own app registration** (its own `AZURE_CLIENT_ID` federated credential), ideally its **own Azure subscription**, and possibly a separate `AZURE_TENANT_ID`. In that case, move `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` from repository variables into each environment's variables instead.

**Dev environment variables** (go to **Settings → Environments → dev → Environment variables**):
```
AZURE_RESOURCE_GROUP: afd-waf-dev-rg
AFD_BASE_URL: https://afd-dev-<unique-suffix>.azurefd.net  (set after first deployment)
WAF_POLICY_NAME: afd-waf-dev-policy
APIM_PUBLISHER_EMAIL: devops@contoso.com  (your email)
APIM_PUBLISHER_NAME: Contoso DevOps
```

**Test environment variables** (go to **Settings → Environments → test → Environment variables**):
```
AZURE_RESOURCE_GROUP: afd-waf-test-rg
AFD_BASE_URL: https://afd-test-<unique-suffix>.azurefd.net
WAF_POLICY_NAME: afd-waf-test-policy
APIM_PUBLISHER_EMAIL: devops@contoso.com
APIM_PUBLISHER_NAME: Contoso DevOps
```

**Prod environment variables** (go to **Settings → Environments → prod → Environment variables**):
```
AZURE_RESOURCE_GROUP: afd-waf-prod-rg
AFD_BASE_URL: https://afd-prod-<unique-suffix>.azurefd.net
WAF_POLICY_NAME: afd-waf-prod-policy
APIM_PUBLISHER_EMAIL: devops@contoso.com
APIM_PUBLISHER_NAME: Contoso DevOps
```

### 3. Verify No Secrets Are Needed

Confirm that under **Settings → Secrets and variables → Actions → Secrets**, there are **no long-lived credential secrets** (e.g., no AZURE_CREDENTIALS). OIDC federation handles authentication.

---

## First Local Validation

Before pushing to GitHub, validate your infrastructure code locally.

### 1. Validate Bicep

**PowerShell** or **bash**:
```bash
# Navigate to Bicep directory
cd infra/bicep

# Validate main template (syntax check)
az bicep build --file main.bicep

# Expected output: No errors, generates main.json

# Clean up generated file (optional)
rm main.json
```

### 2. Validate Terraform

**PowerShell** or **bash**:
```bash
# Navigate to Terraform directory
cd ../terraform

# Initialize Terraform (downloads providers and modules)
terraform init

# Validate configuration
terraform validate

# Expected output: "Success! The configuration is valid."

# Generate a plan (without applying)
terraform plan \
  -var-file=env/dev.tfvars \
  -out=tfplan

# Review the plan output for any unexpected resources

```

### 3. Check AVM Governance

**PowerShell**:
```powershell
# Navigate to repo root
cd ../..

# Run AVM governance checks
powershell -File scripts/check-avm-versions.ps1

# Expected output: "AVM governance check passed"
```

**Bash**:
```bash
# Navigate to repo root
cd ../..

# Run AVM governance checks (if compatible with bash)
bash scripts/check-avm-versions.ps1

# Or on macOS/Linux, run PowerShell if installed
pwsh -File scripts/check-avm-versions.ps1
```

---

## First Deployment to Dev

Once validation passes, deploy infrastructure to the dev environment.

### 1. Create a Feature Branch and Push

**PowerShell** or **bash**:
```bash
# Create and switch to a feature branch
git checkout -b feat/initial-setup

# Make a minor change to trigger CI (or just push as-is)
git add .
git commit -m "Initial setup ready for CI/CD validation" || true

# Push branch to GitHub
git push --set-upstream origin feat/initial-setup
```

### 2. Open a Pull Request

- Go to GitHub repository
- Click **Compare & pull request**
- Add a title and description
- Create the pull request

### 3. Wait for CI Validation

The **Infra Validate** workflow should trigger automatically:
- Check that all GitHub Actions succeed (lint, Bicep build, Terraform validate, what-if)
- Review the workflow logs for any errors
- If all pass, you're ready to deploy

### 4. Merge and Deploy

Once CI passes:
1. Merge the pull request to `main`
2. Go to **Actions → Infra Deploy**
3. Click **Run workflow**
4. Select `main` branch and `dev` environment
5. Click **Run workflow**

The deployment will:
- Use OIDC to authenticate (no secrets in logs)
- Provision AFD, WAF policy, APIM, and networking
- Take ~10–15 minutes
- Provide deployment outputs (AFD hostname, APIM gateway URL)

### 5. Capture Outputs

After deployment, capture the AFD base URL:

**PowerShell**:
```powershell
# From deployment outputs or Azure portal
$AFD_BASE_URL = (az deployment group show `
  --resource-group afd-waf-dev-rg `
  --name main `
  --query 'properties.outputs.frontDoorFqdn.value' -o tsv)

Write-Host "AFD Base URL: $AFD_BASE_URL"
```

**Bash**:
```bash
# From deployment outputs or Azure portal
AFD_BASE_URL=$(az deployment group show \
  --resource-group afd-waf-dev-rg \
  --name main \
  --query 'properties.outputs.frontDoorFqdn.value' -o tsv)

echo "AFD Base URL: $AFD_BASE_URL"
```

Update the `AFD_BASE_URL` variable in your GitHub dev environment with this value.

---

## Testing and Troubleshooting

### 1. Smoke Test

Test that AFD routes to APIM and returns a 200 response:

**PowerShell**:
```powershell
# From repo root
powershell -File scripts/smoke-odata.ps1 `
  -AfdBaseUrl "https://afd-dev-xxxx.azurefd.net" `
  -Environment dev

# Expected output: 
# Testing OData queries against AFD...
# GET /api1/odata?$filter=name eq 'test' ... 200 OK
# GET /api2/odata?$orderby=id ... 200 OK
```

**Bash** (if script is adapted to bash):
```bash
# From repo root
bash scripts/smoke-odata.ps1 \
  --afd-base-url "https://afd-dev-xxxx.azurefd.net" \
  --environment dev
```

### 2. Verify WAF is Active

**PowerShell**:
```powershell
# Check WAF policy mode (should be Detection for dev)
az network front-door waf-policy show `
  --resource-group afd-waf-dev-rg `
  --name afd-waf-dev-policy `
  --query enabledState

# Expected output: "Enabled"

# Check WAF mode (detection vs. prevention)
az network front-door waf-policy show `
  --resource-group afd-waf-dev-rg `
  --name afd-waf-dev-policy `
  --query mode

# Expected output: "Detection"
```

**Bash**:
```bash
# Check WAF policy mode (should be Detection for dev)
az network front-door waf-policy show \
  --resource-group afd-waf-dev-rg \
  --name afd-waf-dev-policy \
  --query enabledState

# Expected output: "Enabled"

# Check WAF mode (detection vs. prevention)
az network front-door waf-policy show \
  --resource-group afd-waf-dev-rg \
  --name afd-waf-dev-policy \
  --query mode

# Expected output: "Detection"
```

### 3. Inspect WAF Logs

WAF logs are sent to Log Analytics. Query them using KQL:

**PowerShell**:
```powershell
# Export KQL template
Get-Content scripts/export-waf-evidence.kql

# In Azure Portal:
# 1. Go to your Log Analytics workspace
# 2. Click Logs
# 3. Paste the KQL query
# 4. Run to see recent WAF logs
```

**Bash**:
```bash
# Export KQL template
cat scripts/export-waf-evidence.kql

# In Azure Portal:
# 1. Go to your Log Analytics workspace
# 2. Click Logs
# 3. Paste the KQL query
# 4. Run to see recent WAF logs
```

### 4. Troubleshooting Common Issues

**Issue**: OIDC login fails in workflows
- **Solution**: Verify federated credentials exist: `az ad app federated-credential list --id <APP_ID>`
- Ensure subject matches repo in federated credential (e.g., `repo:<ORG>/<REPO>:environment:dev`)

**Issue**: Terraform plan fails with "Contributor role not sufficient"
- **Solution**: Check role assignments: `az role assignment list --assignee <CLIENT_ID> -o table`
- Add missing roles for specific resource types

**Issue**: Bicep build fails
- **Solution**: Ensure Bicep CLI >= 0.42.1: `az bicep version`
- Upgrade: `az bicep upgrade`

**Issue**: AFD hostname not resolving
- **Solution**: Wait ~10 minutes for DNS propagation
- Check AFD status in Azure Portal

---

## Next Steps

After successful dev deployment:

1. **Deploy to test and prod** using the same Infra Deploy workflow (select different environments)
2. **Update WAF config** by modifying `config/waf/dev/exclusions.json` with OData-specific rules
3. **Run config-deploy** workflow in Detection mode to test tuning
4. **Review WAF evidence** using the KQL template to measure false-positive reduction
5. **Promote to Prevention mode** after manual approval

For detailed operational guidance, see:
- [docs/architecture.md](docs/architecture.md) - System design
- [docs/devops-setup.md](docs/devops-setup.md) - OIDC and GitHub configuration reference
- [docs/waf-tuning-governance.md](docs/waf-tuning-governance.md) - Governance and approval flows
- [docs/runbook-false-positive-triage.md](docs/runbook-false-positive-triage.md) - Operational runbook

---

## Getting Help

- Check [docs/devops-setup.md](docs/devops-setup.md) for detailed configuration reference
- Review workflow logs in GitHub Actions for error details
- Inspect Azure activity logs: `az monitor activity-log list --resource-group <RG>`
- Contact your cloud platform team for subscription/RBAC questions
