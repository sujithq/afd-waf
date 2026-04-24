# ============================================================================
# DEPRECATED: This script is no longer the recommended way to deploy WAF config
# ============================================================================
# WAF configuration is now managed through Terraform IaC.
# This script is kept for reference and emergency fallback scenarios only.
#
# RECOMMENDED APPROACH:
# 1. Update config/waf/{environment}/exclusions.json or rule-overrides.json
# 2. Run the "Infra Deploy" workflow with iac=terraform
# 3. Terraform will read the JSON files and apply changes to the WAF policy
#
# This approach provides:
# - Infrastructure as Code benefits (version control, drift detection)
# - Declarative configuration management
# - Integration with Terraform state
# - No out-of-band imperative updates
#
# Only use this script if:
# - You need an emergency rollback outside of Terraform
# - Terraform state is corrupted and you need immediate mitigation
# - You are migrating from script-based to IaC approach
# ============================================================================

Param(
  [ValidateSet("dev", "test", "prod")]
  [string]$Environment,
  [ValidateSet("Detection", "Prevention")]
  [string]$Mode = "Detection",
  [Parameter(Mandatory = $true)]
  [string]$SubscriptionId,
  [Parameter(Mandatory = $true)]
  [string]$ResourceGroup,
  [Parameter(Mandatory = $true)]
  [string]$WafPolicyName,
  [string]$ApiVersion = "2022-05-01",
  [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Warning "=========================================="
Write-Warning "DEPRECATION NOTICE"
Write-Warning "=========================================="
Write-Warning "This script is deprecated. Please use Terraform to manage WAF configuration."
Write-Warning "See the script header for recommended approach."
Write-Warning "=========================================="

if (-not $Force) {
  $answer = Read-Host "Proceed anyway? Type 'yes' to continue or press Enter to abort"
  if ($answer -ne 'yes') {
    Write-Host "Aborted."
    exit 0
  }
}

Write-Host "Applying WAF config for environment: $Environment in mode: $Mode"

$exclusionsPath = "config/waf/$Environment/exclusions.json"
$overridesPath = "config/waf/$Environment/rule-overrides.json"

if (!(Test-Path $exclusionsPath)) { throw "Missing exclusions file: $exclusionsPath" }
if (!(Test-Path $overridesPath)) { throw "Missing overrides file: $overridesPath" }

$exclusions = Get-Content $exclusionsPath -Raw | ConvertFrom-Json
$overrides = Get-Content $overridesPath -Raw | ConvertFrom-Json

$resourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Network/frontDoorWebApplicationFirewallPolicies/$WafPolicyName"
$getUrl = "https://management.azure.com$resourceId?api-version=$ApiVersion"

Write-Host "Fetching existing WAF policy"
$currentPolicy = az rest --method get --url $getUrl | ConvertFrom-Json

$managedRules = $currentPolicy.properties.managedRules
if (-not $managedRules) {
  $managedRules = [ordered]@{
    managedRuleSets = @(
      [ordered]@{
        ruleSetType = "Microsoft_DefaultRuleSet"
        ruleSetVersion = "2.1"
      }
    )
  }
}

$managedRules.exclusions = @($exclusions.exclusions)

if ($overrides.overrides -and $overrides.overrides.Count -gt 0) {
  if (-not $managedRules.managedRuleSets -or $managedRules.managedRuleSets.Count -eq 0) {
    throw "Cannot apply overrides because managedRuleSets is empty."
  }

  if (-not $managedRules.managedRuleSets[0].ruleGroupOverrides) {
    $managedRules.managedRuleSets[0] | Add-Member -NotePropertyName ruleGroupOverrides -NotePropertyValue @()
  }

  $managedRules.managedRuleSets[0].ruleGroupOverrides = @($overrides.overrides)
}

$policySettings = $currentPolicy.properties.policySettings
if (-not $policySettings) {
  $policySettings = [ordered]@{
    enabledState = "Enabled"
    mode = $Mode
    requestBodyCheck = "Enabled"
  }
} else {
  $policySettings.mode = $Mode
}

$body = [ordered]@{
  location = $currentPolicy.location
  sku = $currentPolicy.sku
  properties = [ordered]@{
    policySettings = $policySettings
    managedRules = $managedRules
    customRules = $currentPolicy.properties.customRules
  }
}

$tmpBody = Join-Path $PWD "waf-config-payload-$Environment.json"
$body | ConvertTo-Json -Depth 30 | Set-Content -Path $tmpBody -Encoding utf8

Write-Host "Applying WAF config update"
az rest --method put --url $getUrl --body "@$tmpBody" | Out-Null

$metadata = $exclusions.metadata
$manifest = [ordered]@{
  timestampUtc = (Get-Date).ToUniversalTime().ToString("o")
  environment = $Environment
  mode = $Mode
  policyResourceId = $resourceId
  changeTicket = $metadata.changeTicket
  owner = $metadata.owner
  reason = $metadata.reason
  excludesCount = @($exclusions.exclusions).Count
}

$manifestPath = Join-Path $PWD "waf-config-manifest-$Environment.json"
$manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath -Encoding utf8

Write-Host "WAF config applied successfully"
Write-Host "Manifest file: $manifestPath"
