# Getting Started: AFD WAF OData Automation

This guide walks you through setting up this repository from scratch, from local environment setup through your first Azure deployment.

**Supported shells**: PowerShell (`pwsh`), Bash, or Zsh on Windows, macOS, or Linux

**Time estimate**: 45–60 minutes (depending on Azure org policies)

**Note**: Most commands are shell-agnostic and work in both PowerShell and bash. Where differences exist (e.g., variable assignment syntax), both variants are shown.

**Terraform focus**: This guide follows the Terraform path because it has been tested end to end. Bicep assets exist in the repo, but the recommended first setup path is Terraform.

**Quick Start Option**: If you prefer to use GitHub workflows instead of local setup, skip to [Quick Start with Workflows](#quick-start-with-workflows) after completing the OIDC setup.

**Table of Contents**
1. [Prerequisites](#prerequisites)
2. [Local Environment Setup](#local-environment-setup)
3. [GitHub OIDC Federation Setup](#github-oidc-federation-setup)
4. [Azure Subscription Setup](#azure-subscription-setup)
5. [Quick Start with Workflows](#quick-start-with-workflows)
6. [GitHub Repository Configuration](#github-repository-configuration)
7. [First Local Validation](#first-local-validation)
8. [First Deployment to Dev](#first-deployment-to-dev)
9. [Testing and Troubleshooting](#testing-and-troubleshooting)

---

## Prerequisites

Before starting, ensure you have:

- **Azure subscription**: With admin or Owner access for initial setup. For workflow Bootstrap to complete end-to-end, the GitHub service principal needs permission to create backend resources and role assignments (for example, `Contributor` plus `User Access Administrator` at subscription scope, or `Owner` during bootstrap).
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

# For Bootstrap and main-branch workflow runs
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

# For Bootstrap and main-branch workflow runs
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

For the tested Terraform workflow path, Terraform creates the environment resource groups (`${TF_NAME_PREFIX}-${environment}-rg`) and the resources inside them. Grant the service principal subscription-scope `Contributor` so Terraform can create those resource groups.

If the same service principal will run the **Bootstrap** workflow end-to-end, it also needs permission to create the backend storage role assignment. Grant `User Access Administrator` during bootstrap, or have an Azure admin run the backend `Storage Blob Data Contributor` assignment manually after backend creation.

**PowerShell**:
```powershell
# Get the service principal object ID
$SP_OBJECT_ID = (az ad sp show --id $CLIENT_ID --query id -o tsv)

# Terraform path: subscription scope because Terraform creates acafd-<env>-rg
az role assignment create `
  --assignee-object-id $SP_OBJECT_ID `
  --assignee-principal-type ServicePrincipal `
  --role "Contributor" `
  --scope "/subscriptions/$SUBSCRIPTION_ID"

# Required only if this service principal runs Bootstrap and creates backend RBAC
az role assignment create `
  --assignee-object-id $SP_OBJECT_ID `
  --assignee-principal-type ServicePrincipal `
  --role "User Access Administrator" `
  --scope "/subscriptions/$SUBSCRIPTION_ID"

# Verify role assignments
az role assignment list `
  --assignee-object-id $SP_OBJECT_ID `
  --scope "/subscriptions/$SUBSCRIPTION_ID" `
  --include-inherited `
  --output table

# Note: If you query with --assignee $CLIENT_ID and see no rows, verify $CLIENT_ID is set.
# For deterministic results, prefer --assignee-object-id with an explicit scope.
```

**Bash**:
```bash
# Get the service principal object ID
SP_OBJECT_ID=$(az ad sp show --id "$CLIENT_ID" --query id -o tsv)

# Terraform path: subscription scope because Terraform creates acafd-<env>-rg
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

# Required only if this service principal runs Bootstrap and creates backend RBAC
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

# Verify role assignments
az role assignment list \
  --assignee-object-id "$SP_OBJECT_ID" \
  --scope "/subscriptions/$SUBSCRIPTION_ID" \
  --include-inherited \
  --output table

# Note: If you query with --assignee "$CLIENT_ID" and see no rows, verify CLIENT_ID is set.
# For deterministic results, prefer --assignee-object-id with an explicit scope.
```

---

## Azure Subscription Setup

For the tested Terraform path, there are two setup tracks:

- **Workflow setup**: use the **Bootstrap** workflow after OIDC is configured. Bootstrap creates the Terraform backend resource group, storage account, `tfstate` container, and backend data-plane RBAC.
- **Manual setup**: create the Terraform backend yourself with Azure CLI, then run Terraform locally or through GitHub Actions.

Application resource groups such as `acafd-dev-rg`, `acafd-test-rg`, and `acafd-prod-rg` are Terraform-owned. Do not pre-create them for the normal Terraform workflow unless you are intentionally importing existing resource groups.

### Manual Terraform Backend Bootstrap

Skip this section when using the **Bootstrap** workflow. Use it only when you want a fully manual backend setup.

**PowerShell**:
```powershell
$SUBSCRIPTION_ID = (az account show --query id -o tsv)
$LOCATION = "swedencentral"
$TF_BACKEND_RG = "afd-waf-tfstate-rg"
$TF_BACKEND_SA = "afdwaftf$(Get-Date -UFormat "%s")"

az group create `
  --name $TF_BACKEND_RG `
  --location $LOCATION

az storage account create `
  --name $TF_BACKEND_SA `
  --resource-group $TF_BACKEND_RG `
  --location $LOCATION `
  --sku Standard_LRS `
  --allow-shared-key-access false

az storage container create `
  --account-name $TF_BACKEND_SA `
  --name tfstate `
  --auth-mode login

Write-Host "TF_BACKEND_RG=$TF_BACKEND_RG"
Write-Host "TF_BACKEND_SA=$TF_BACKEND_SA"
```

**Bash**:
```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
LOCATION="swedencentral"
TF_BACKEND_RG="afd-waf-tfstate-rg"
TF_BACKEND_SA="afdwaftf$(date +%s)"

az group create \
  --name "$TF_BACKEND_RG" \
  --location "$LOCATION"

az storage account create \
  --name "$TF_BACKEND_SA" \
  --resource-group "$TF_BACKEND_RG" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --allow-shared-key-access false

az storage container create \
  --account-name "$TF_BACKEND_SA" \
  --name tfstate \
  --auth-mode login

echo "TF_BACKEND_RG=$TF_BACKEND_RG"
echo "TF_BACKEND_SA=$TF_BACKEND_SA"
```

If GitHub Actions will use this manually created backend, grant the deployment service principal `Storage Blob Data Contributor` on the backend storage account. The Bootstrap workflow does this automatically.

---

## Quick Start with Workflows

If you prefer to use GitHub Actions workflows instead of local setup, follow these streamlined steps after completing the OIDC Federation Setup above.

Before running workflows, the Entra application, service principal, federated credentials, GitHub repository variables, and initial Azure RBAC assignments must exist. Bootstrap can create the Terraform backend, but it cannot create the identity that GitHub uses to sign in.

### Overview

This repository provides automated workflows that you can trigger manually:

1. **Bootstrap** - Creates Terraform backend storage and bootstraps backend RBAC (one-time setup)
2. **Infra Deploy** - Deploys Azure infrastructure with Terraform (AFD, WAF, APIM)
3. **Config Deploy** - Applies WAF configuration with Terraform
4. **Infra Validate** - Validates infrastructure code
5. **Config Validate** - Validates WAF configuration

### Quick Start Steps

#### 1. Set Minimal GitHub Variables

After completing OIDC Federation Setup, add these repository variables in GitHub (**Settings → Secrets and variables → Actions → Variables**):

```
AZURE_CLIENT_ID: <from OIDC Federation Setup>
AZURE_TENANT_ID: <from OIDC Federation Setup>
AZURE_SUBSCRIPTION_ID: <your subscription ID>
TF_LOCATION: swedencentral
TF_NAME_PREFIX: acafd
APIM_PUBLISHER_EMAIL: your-email@example.com
APIM_PUBLISHER_NAME: Your Name
```

#### 2. Run Bootstrap Workflow

1. Go to **Actions → Bootstrap** in your GitHub repository
2. Click **Run workflow**
3. Fill in the parameters:
    - **location**: `swedencentral` (or your preferred region)
    - **backend_rg**: `afd-waf-tfstate-rg`
    - **backend_sa**: optional. Use `afdwaftf<unique-id>` or leave blank to auto-generate a globally unique storage account name.
    - **target_sp_object_id** (optional): service principal object ID to grant backend RBAC to. If omitted, the workflow resolves it from `AZURE_CLIENT_ID`.
4. Click **Run workflow**

**IMPORTANT - Manual Configuration Required:**

After the bootstrap workflow completes, you **must manually** add these GitHub repository variables for subsequent workflows to access the backend:

1. Go to **Settings → Secrets and variables → Actions → Variables** in your GitHub repository
2. Add or update these repository variables with the values from the bootstrap output:
   ```
   TF_BACKEND_RG: afd-waf-tfstate-rg
   TF_BACKEND_SA: <the storage account name you used>
   TF_LOCATION: <the location you used>
   ```

**Why is this needed?**
- When workflows are **chained** (using `workflow_call`), outputs are passed automatically between workflows
- When workflows are run **manually** (using `workflow_dispatch`), they read from GitHub repository variables
- The Bootstrap workflow creates the Azure resources and outputs the values, but GitHub Actions requires manual configuration of repository variables for security reasons
- The Bootstrap workflow also grants `Storage Blob Data Contributor` on the backend storage account scope (idempotent)
- This one-time manual step ensures subsequent workflows (Infra Deploy, Config Deploy) can find the Terraform backend

#### 3. Run Infra Deploy Workflow

1. Go to **Actions → Infra Deploy**
2. Click **Run workflow**
3. Select **environment**: `dev` and **iac**: `terraform`.
4. For a review-only plan, leave **apply_terraform** as `false`; **apply_confirmation** is ignored and can stay blank.
5. To apply the exact saved plan from the same workflow run, set **apply_terraform** to `true` and **apply_confirmation** to `apply-dev`, then review the plan summary before approving the `approve` job.
6. Set **run_config_deploy** to `true` only when you want a follow-up Config Deploy plan after the infra apply succeeds.
7. Click **Run workflow**

This will:
- Always create a Terraform plan and publish it to the job summary
- Upload the binary `tfplan` artifact only when `apply_terraform=true`
- Pause in a separate `approve` job for plan review, then apply the saved plan in the `apply` job
- If `run_config_deploy` is true, automatically run a follow-up Config Deploy plan after a successful Terraform infra apply

#### 4. (Optional) Run Config Deploy Separately

If you didn't enable automatic config deployment, or want to update WAF configuration later:

1. Go to **Actions → Config Deploy**
2. Click **Run workflow**
3. Select **environment**: `dev`
4. Select **iac**: `terraform`
5. For a review-only plan, leave **apply_terraform** as `false`; **apply_confirmation** is ignored and can stay blank.
6. To apply the exact saved config plan from the same workflow run, set **apply_terraform** to `true` and **apply_confirmation** to `apply-dev`, then approve the `approve` job after reviewing the plan summary.
7. Click **Run workflow**

Terraform approval model:
- A normal plan-only run does not apply and does not reuse a plan in a later workflow run.
- A saved-plan apply run creates `tfplan` in the `plan` job, uploads it as a short-lived artifact, pauses in the `approve` job, and then the `apply` job downloads and applies that same artifact.
- If the Terraform plan has no changes, the workflow writes that to the job summary and skips artifact upload, approval, and apply.
- The apply job refuses saved plans older than 60 minutes, so rerun the workflow if approval is delayed.
- Configure required reviewers on the existing `dev`, `test`, and `prod` GitHub environments when you want the explicit approval gate to pause before apply. Because those same environments are also used for Azure OIDC, a protected environment can also pause jobs that need to sign in to Azure.
- Terraform rejects stale plans when state changes, but out-of-band Azure drift that is not reflected in state is not re-checked by an already saved plan.

### Workflow Chaining

The workflows can be chained together:

- **Infra Deploy** can automatically trigger **Config Deploy** if you enable the `run_config_deploy` option
- For Terraform, chained Config Deploy runs as a follow-up plan. Apply Config Deploy separately with `apply_terraform=true` and the matching confirmation when you are ready to approve the saved config plan.

**Understanding Data Flow Between Workflows:**

There are two ways workflows communicate:

1. **Chained Workflows (workflow_call):** Workflows can call each other programmatically. Infra Deploy passes the selected `iac` value to Config Deploy when `run_config_deploy=true`.

2. **Manual Workflows (workflow_dispatch):**
   - When you trigger workflows manually from the Actions UI
   - Workflows read from GitHub repository variables (`${{ vars.VARIABLE_NAME }}`)
   - Example: Bootstrap completes → You manually set `TF_BACKEND_RG` and `TF_BACKEND_SA` as repository variables → Infra Deploy reads these variables
   - Requires one-time manual configuration after bootstrap

**Current Implementation:**
- Bootstrap workflow provides outputs for future chaining capabilities
- Bootstrap workflow grants backend data-plane RBAC for Terraform state access
- For manual execution, you must set the output values as GitHub repository variables
- Infra Deploy and Config Deploy read from repository variables (`vars.TF_BACKEND_RG`, `vars.TF_BACKEND_SA`)
- Config Deploy supports both Terraform and Bicep, but this guide uses `iac=terraform`.

### Manual Validation

You can also manually trigger validation workflows at any time:

- **Infra Validate** - Validates Bicep, Terraform, and AVM governance
- **Config Validate** - Validates WAF JSON schemas and security guardrails

These validation workflows run automatically on pull requests, but you can also trigger them manually for testing.

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
TF_BACKEND_RG: <resource group that contains your Terraform state storage account>
TF_BACKEND_SA: <storage account name used for Terraform state>
APIM_PUBLISHER_EMAIL: devops@contoso.com  (your email)
APIM_PUBLISHER_NAME: Contoso DevOps
```

> **Required for Terraform workflows**: `TF_BACKEND_RG` and `TF_BACKEND_SA` must be set for Infra Deploy (`iac=terraform`) and Config Deploy (`iac=terraform`), otherwise `terraform init` fails with backend errors such as missing `resource_group_name`.

> **Note — production practice**: Sharing a single app registration and subscription across all environments is fine for this demo repo. In a real-world setup, each environment (`dev`, `test`, `prod`) should have its **own app registration** (its own `AZURE_CLIENT_ID` federated credential), ideally its **own Azure subscription**, and possibly a separate `AZURE_TENANT_ID`. In that case, move `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` from repository variables into each environment's variables instead.

**Dev environment variables** (go to **Settings → Environments → dev → Environment variables**):
```
AZURE_RESOURCE_GROUP: acafd-dev-rg
AFD_BASE_URL: https://<afd-endpoint-hostname>  (set after first deployment)
WAF_POLICY_NAME: acafdwafdev
```

**Test environment variables** (go to **Settings → Environments → test → Environment variables**):
```
AZURE_RESOURCE_GROUP: acafd-test-rg
AFD_BASE_URL: https://<afd-endpoint-hostname>
WAF_POLICY_NAME: acafdwaftest
```

**Prod environment variables** (go to **Settings → Environments → prod → Environment variables**):
```
AZURE_RESOURCE_GROUP: acafd-prod-rg
AFD_BASE_URL: https://<afd-endpoint-hostname>
WAF_POLICY_NAME: acafdwafprod
```

### 3. Verify No Secrets Are Needed

Confirm that under **Settings → Secrets and variables → Actions → Secrets**, there are **no long-lived credential secrets** (e.g., no AZURE_CREDENTIALS). OIDC federation handles authentication.

---

## First Local Validation

Before pushing to GitHub, validate your infrastructure code locally.

### 1. Validate Bicep (Optional)

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

**PowerShell**:
```powershell
# Navigate to Terraform directory
cd ../terraform

# Initialize Terraform (downloads providers and modules)
terraform init -backend=false

# Validate configuration
terraform validate

# Expected output: "Success! The configuration is valid."

# Generate a plan (without applying)
terraform plan --% -var-file=env/dev.tfvars -out=tfplan

# Review the plan output for any unexpected resources
# If Terraform then fails with an Azure CLI token error, re-run `az login`
# and confirm the correct subscription with `az account show`.
```

**Bash**:
```bash
# Navigate to Terraform directory
cd ../terraform

# Initialize Terraform (downloads providers and modules)
terraform init -backend=false

# Validate configuration
terraform validate

# Expected output: "Success! The configuration is valid."

# Generate a plan (without applying)
terraform plan -var-file=env/dev.tfvars -out=tfplan

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

# Make a minor change to trigger CI if needed
git add .
git status --short

# If you staged changes, commit them
git commit -m "Initial setup ready for CI/CD validation"

# Push branch to GitHub
git push --set-upstream origin feat/initial-setup
```

### 2. Open a Pull Request

- Go to GitHub repository
- Click **Compare & pull request**
- Add a title and description
- Create the pull request

### 3. Wait for CI Validation

The **Infra Validate** workflow triggers automatically for pull requests that change `infra/**` or `scripts/check-avm-versions.ps1`.
- Check that Infra Validate succeeds (Bicep build, Terraform fmt/validate, AVM governance marker check)
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

After deployment, capture the AFD base URL.

For Terraform deployments, do not use `az deployment group show` (there may be no ARM deployment name to query). Instead, query the AFD endpoint directly.

**PowerShell**:
```powershell
# Terraform path: query AFD endpoint directly (recommended)
# Reuse naming prefix from earlier steps (or set explicitly)
$NAME_PREFIX = "acafd"  # must match TF_NAME_PREFIX / name_prefix in dev.tfvars
$ENVIRONMENT = "dev"
$DEV_RESOURCE_GROUP = "$NAME_PREFIX-dev-rg"
$AFD_PROFILE_NAME = "$NAME_PREFIX-afd-$ENVIRONMENT"
$AFD_ENDPOINT_NAME = "$NAME_PREFIX-ep-$ENVIRONMENT"

$AFD_HOSTNAME = (az afd endpoint show `
  --resource-group $DEV_RESOURCE_GROUP `
  --profile-name $AFD_PROFILE_NAME `
  --endpoint-name $AFD_ENDPOINT_NAME `
  --query hostName -o tsv)

$AFD_BASE_URL = "https://$AFD_HOSTNAME"

Write-Host "AFD Base URL: $AFD_BASE_URL"

# Bicep-only alternative (if you deployed with bicep and know deployment name):
# $AFD_HOSTNAME = az deployment group show --resource-group $DEV_RESOURCE_GROUP --name main --query 'properties.outputs.frontDoorFqdn.value' -o tsv
```

**Bash**:
```bash
# Terraform path: query AFD endpoint directly (recommended)
# Reuse naming prefix from earlier steps (or set explicitly)
NAME_PREFIX="acafd"  # must match TF_NAME_PREFIX / name_prefix in dev.tfvars
ENVIRONMENT="dev"
DEV_RESOURCE_GROUP="${NAME_PREFIX}-dev-rg"
AFD_PROFILE_NAME="${NAME_PREFIX}-afd-${ENVIRONMENT}"
AFD_ENDPOINT_NAME="${NAME_PREFIX}-ep-${ENVIRONMENT}"

AFD_HOSTNAME=$(az afd endpoint show \
  --resource-group "$DEV_RESOURCE_GROUP" \
  --profile-name "$AFD_PROFILE_NAME" \
  --endpoint-name "$AFD_ENDPOINT_NAME" \
  --query hostName -o tsv)

AFD_BASE_URL="https://${AFD_HOSTNAME}"

echo "AFD Base URL: $AFD_BASE_URL"

# Bicep-only alternative (if you deployed with bicep and know deployment name):
# AFD_HOSTNAME=$(az deployment group show --resource-group "$DEV_RESOURCE_GROUP" --name main --query 'properties.outputs.frontDoorFqdn.value' -o tsv)
```

Update the `AFD_BASE_URL` variable in your GitHub dev environment with this value.

---

## Testing and Troubleshooting

### 1. Smoke Test

Test that AFD routes to APIM and returns a 200 response:

**PowerShell**:
```powershell
# From repo root
# Reuse $AFD_BASE_URL captured in the previous step
powershell -File scripts/smoke-odata.ps1 `
  -BaseUrl $AFD_BASE_URL

# Expected output: 
# Testing OData queries against AFD...
# GET /odata1/Entities?$filter=name eq 'test' ... 200 OK
# GET /odata2/Entities?$orderby=id ... 200 OK
```

**Bash**:
```bash
# From repo root
# Reuse $AFD_BASE_URL captured in the previous step
pwsh -File scripts/smoke-odata.ps1 \
  -BaseUrl "$AFD_BASE_URL"
```

### 2. Verify WAF is Active

**PowerShell**:
```powershell
# Check WAF policy mode (should be Detection for dev)
$NAME_PREFIX = "acafd"
$ENVIRONMENT = "dev"
$RESOURCE_GROUP = "$NAME_PREFIX-$ENVIRONMENT-rg"
$WAF_POLICY_NAME = "${NAME_PREFIX}waf${ENVIRONMENT}"

az network front-door waf-policy show `
  --resource-group $RESOURCE_GROUP `
  --name $WAF_POLICY_NAME `
  --query enabledState

# Expected output: "Enabled"

# Check WAF mode (detection vs. prevention)
az network front-door waf-policy show `
  --resource-group $RESOURCE_GROUP `
  --name $WAF_POLICY_NAME `
  --query mode

# Expected output: "Detection"
```

**Bash**:
```bash
# Check WAF policy mode (should be Detection for dev)
NAME_PREFIX="acafd"
ENVIRONMENT="dev"
RESOURCE_GROUP="${NAME_PREFIX}-${ENVIRONMENT}-rg"
WAF_POLICY_NAME="${NAME_PREFIX}waf${ENVIRONMENT}"

az network front-door waf-policy show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WAF_POLICY_NAME" \
  --query enabledState

# Expected output: "Enabled"

# Check WAF mode (detection vs. prevention)
az network front-door waf-policy show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WAF_POLICY_NAME" \
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

**Issue**: Terraform apply fails with `AuthorizationFailed` on `Microsoft.Resources/subscriptions/resourceGroups/read`
- **Cause**: The service principal scope does not cover the resource group name Terraform is trying to read/create. In this repo, Terraform creates `${TF_NAME_PREFIX}-${environment}-rg` (for example, `acafd-dev-rg`).
- **Solution**: For Terraform deployments that create resource groups, grant `Contributor` at subscription scope:
  - PowerShell: `az role assignment create --assignee-object-id <SP_OBJECT_ID> --assignee-principal-type ServicePrincipal --role "Contributor" --scope "/subscriptions/<SUBSCRIPTION_ID>"`
  - Bash: `az role assignment create --assignee-object-id <SP_OBJECT_ID> --assignee-principal-type ServicePrincipal --role "Contributor" --scope "/subscriptions/<SUBSCRIPTION_ID>"`
- Ensure `TF_NAME_PREFIX` matches your intended naming, then re-run the workflow after RBAC propagation.

**Issue**: AFD WAF security policy creation fails because path patterns must be one of `/*`
- **Cause**: Front Door security policy associations for the endpoint default domain are domain-wide. Azure rejects route-specific WAF association patterns such as `/odata1/*` and `/odata2/*`, even when those AFD routes exist.
- **Solution**: Use one active base WAF policy associated to `/*` for the endpoint default domain. Domain-specific WAF policy packages can be rendered for future separate domains, but they cannot be activated as path-scoped associations on the same endpoint default domain.

**Issue**: Terraform init fails with `403 KeyBasedAuthenticationNotPermitted` while listing backend blobs
- **Cause**: The Terraform backend is trying key-based auth against a storage account that has shared key access disabled.
- **Solution**:
  - Ensure Infra Deploy uses Azure AD auth for backend init (`use_azuread_auth=true`).
  - Prefer running **Bootstrap** once (or re-running it) for the same backend values; it now grants backend `Storage Blob Data Contributor` automatically.
    - Optional: pass `target_sp_object_id` if Entra lookup via `AZURE_CLIENT_ID` is restricted.
  - Grant backend data-plane access on the state storage account:
    - PowerShell: `az role assignment create --assignee-object-id <SP_OBJECT_ID> --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" --scope "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<TF_BACKEND_RG>/providers/Microsoft.Storage/storageAccounts/<TF_BACKEND_SA>"`
    - Bash: `az role assignment create --assignee-object-id <SP_OBJECT_ID> --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" --scope "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<TF_BACKEND_RG>/providers/Microsoft.Storage/storageAccounts/<TF_BACKEND_SA>"`
  - Re-run Infra Deploy after RBAC propagation.

**Issue**: Terraform init fails with `403 AuthorizationFailure` while listing backend blobs
- **Cause**: The workflow identity is using Azure AD auth, but it does not yet have backend storage data-plane access, the role assignment has not propagated, or the role was assigned to a different service principal than `AZURE_CLIENT_ID`.
- **Solution**:
  - Check both storage networking properties: `az storage account show -g <TF_BACKEND_RG> -n <TF_BACKEND_SA> --query "{publicNetworkAccess:publicNetworkAccess, defaultAction:networkRuleSet.defaultAction}" -o table`.
  - `networkRuleSet.defaultAction: Allow` rules out firewall allowlist issues, but `publicNetworkAccess: Disabled` still blocks GitHub-hosted runners.
  - For GitHub-hosted runners, enable public network access on the backend storage account: `az storage account update -g <TF_BACKEND_RG> -n <TF_BACKEND_SA> --public-network-access Enabled`. Bootstrap and Infra Deploy also enforce this setting for the Terraform backend.
  - Confirm `AZURE_CLIENT_ID` is the same app registration that received backend RBAC.
  - Verify the assignment with `az role assignment list --assignee-object-id <SP_OBJECT_ID> --scope "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<TF_BACKEND_RG>/providers/Microsoft.Storage/storageAccounts/<TF_BACKEND_SA>" --include-inherited --output table`.
  - Verify data-plane access with `az storage blob list --account-name <TF_BACKEND_SA> --container-name tfstate --auth-mode login --num-results 1` after logging in as the deployment service principal.
  - Re-run the workflow after RBAC propagation. Infra Deploy and Config Deploy also run `scripts/test-terraform-backend-access.ps1` before Terraform init to make this failure explicit.

**Issue**: Bicep build fails
- **Solution**: Ensure Bicep CLI >= 0.42.1: `az bicep version`
- Upgrade: `az bicep upgrade`

**Issue**: AFD hostname not resolving
- **Solution**: Wait ~10 minutes for DNS propagation
- Check AFD status in Azure Portal

**Issue**: Custom domain returns 404 or the certificate name does not match
- **Cause**: The custom domain resource, DNS record, route binding, or edge certificate deployment may be stale even when Azure reports the custom domain as approved. AFD route rules can also be healthy on the default endpoint while the direct custom-domain SNI path is not yet updated.
- **Solution**:
  - Re-run the **Domain Deploy** workflow for the same environment. The script refreshes the managed-certificate settings, preserves existing route custom-domain bindings, and verifies each intended route binding after update.
  - Check the custom domain state: `az afd custom-domain show --resource-group <RG> --profile-name <AFD_PROFILE> --custom-domain-name <CUSTOM_DOMAIN_NAME> -o table`.
  - Check route bindings: `az afd route show --resource-group <RG> --profile-name <AFD_PROFILE> --endpoint-name <ENDPOINT_NAME> --route-name <API_ROUTE_NAME> --query "customDomains" -o table`.
  - Smoke test the direct custom domain after propagation: `pwsh -File scripts/smoke-odata.ps1 -BaseUrl https://<CUSTOM_DOMAIN> -Paths <path1>,<path2>`.

---

## Next Steps

After successful dev deployment:

1. **Deploy to test and prod** using the same Infra Deploy workflow (select different environments)

2. **Run Config Deploy** after every Infra Deploy to apply WAF managed rules. Trigger the **Config Deploy** workflow manually for the same environment, select `iac=terraform`, set `apply_terraform=true`, and type the matching confirmation such as `apply-dev` only when the saved config plan is ready for approval. Terraform imports the base WAF policy plus any domain-specific WAF policies declared in `config/waf/api-policies.json`, applies shared OData exclusions from `config/waf/base/`, applies environment additions from `config/waf/{env}/`, and applies domain-only additions from `config/waf/{env}/domains/{domain}/` when those folders exist.

3. **Update WAF config** for future changes. Add common OData query arguments to `config/waf/base/`. Add environment-wide tuning to `config/waf/{env}/`. Add domain-only tuning to `config/waf/{env}/domains/{domain}/`. For a new isolated domain policy, first add the domain key, hostname, DNS settings, and APIM API bindings to `config/waf/api-policies.json`; Terraform derives the AFD route paths from the APIM API paths. Keep `enabled: false` until DNS is ready. The staged demo hostnames are `api-a.wafdemo.squintelier.net` and `api-b.wafdemo.squintelier.net` under the Azure DNS zone `wafdemo.squintelier.net`. To activate a domain, use a real FQDN that you own, set `dns.zoneName`, set `dns.createZone: true` if Domain Deploy should create the Azure DNS zone, set `dns.manageRecords: true` if Domain Deploy should create DNS records, set `enabled: true`, run Infra Deploy and Config Deploy, then run the **Domain Deploy** workflow. If a new Azure DNS zone is created, delegate it at the registrar or parent DNS zone with the Azure DNS name servers. Use `disabledBaseExclusions` in the domain-specific `exclusions.json` when a domain must opt out of one inherited base exclusion. Run `scripts/show-effective-waf-config.ps1 -Environment dev` to preview the merged policy before deployment. Push changes so Config Validate checks schema and guardrails on PR, then merge to `main` and run Config Deploy manually for the target environment. Domain-only additions do not change other domains.

  When adding a new API or moving an API between domains, treat the workflows as ordered reconciliation steps: Infra Deploy creates the APIM API, AFD route, and empty domain WAF policy resource; Config Deploy applies the WAF rule package to that policy; Domain Deploy binds the route to the custom domain, associates the domain WAF policy, updates DNS if configured, and refreshes the managed certificate binding. Run the matching custom-domain smoke test after Domain Deploy.

4. **Switch WAF mode when needed**:
  - Use `scripts/set-waf-mode.ps1` for an operational live toggle without Terraform redeployment, for example: `pwsh -File scripts/set-waf-mode.ps1 -Environment dev -Mode Prevention -SubscriptionId <SUBSCRIPTION_ID> -NamePrefix acafd -Scope Domains -DomainName domain-a`.
  - Use `-Scope Base`, `-Scope Domains`, or `-Scope All` depending on which WAF policies should change.
  - Update `infra/terraform-config/env/<environment>.tfvars` later only if you want Terraform desired state to retain the mode.

5. **Review WAF evidence** using the KQL template to measure false-positive reduction

**Deployment workflow summary:**
| Step | Workflow | When to run |
|---|---|---|
| Provision/update infrastructure | **Infra Deploy** (`iac=terraform`) | Infrastructure code changes |
| Apply/update WAF rules | **Config Deploy** | WAF JSON config changes |
| Reconcile custom domains and bindings | **Domain Deploy** | New or changed domain/API mappings, DNS settings, or custom-domain certificate/routing repair |

**Emergency fallback (script):**
`scripts/deploy-config.ps1` is available for out-of-band emergency fixes. Use the `-Force` flag to skip the interactive confirmation gate. Always re-run Config Deploy afterwards to bring Terraform state back in sync.

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
