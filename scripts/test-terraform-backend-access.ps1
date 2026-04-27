Param(
  [Parameter(Mandatory = $true)]
  [string]$SubscriptionId,

  [Parameter(Mandatory = $true)]
  [string]$BackendResourceGroup,

  [Parameter(Mandatory = $true)]
  [string]$BackendStorageAccount,

  [Parameter(Mandatory = $true)]
  [string]$ClientId,

  [string]$ContainerName = "tfstate",

  [int]$MaxAttempts = 1,

  [int]$DelaySeconds = 10
)

$ErrorActionPreference = "Stop"

$scope = "/subscriptions/$SubscriptionId/resourceGroups/$BackendResourceGroup/providers/Microsoft.Storage/storageAccounts/$BackendStorageAccount"

Write-Output "Checking Terraform backend data-plane access..."
Write-Output "Backend storage scope: $scope"

$spObjectId = $null
try {
  $spObjectId = az ad sp show --id $ClientId --query id -o tsv
  if ($spObjectId) {
    Write-Output "Deployment service principal object ID: $spObjectId"
  }
} catch {
  Write-Output "Could not resolve service principal object ID from client ID. Continuing with data-plane access test."
}

$attempt = 1
while ($attempt -le $MaxAttempts) {
  Write-Output "Backend access check attempt $attempt of $MaxAttempts..."

  $output = az storage blob list `
    --account-name $BackendStorageAccount `
    --container-name $ContainerName `
    --auth-mode login `
    --num-results 1 `
    --only-show-errors 2>&1

  if ($LASTEXITCODE -eq 0) {
    Write-Output "Terraform backend data-plane access verified."
    exit 0
  }

  Write-Output $output

  if ($attempt -lt $MaxAttempts) {
    Write-Output "Backend access is not ready yet. Waiting $DelaySeconds seconds for RBAC propagation..."
    Start-Sleep -Seconds $DelaySeconds
  }

  $attempt++
}

$message = @"
Terraform backend data-plane access failed.

The GitHub deployment service principal must have Storage Blob Data Contributor on:
$scope

This is required because the backend uses Azure AD auth with shared key access disabled.
If you just created the role assignment, wait a few minutes for RBAC propagation and rerun the workflow.
If it keeps failing, verify that GitHub Actions variable AZURE_CLIENT_ID points to the same service principal that received the role assignment.
"@

throw $message