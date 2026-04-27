Param(
  [ValidateSet("dev", "test", "prod")]
  [string]$Environment = "dev",
  [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$configRoot = Join-Path $repoRoot "config/waf"
$apiPolicyPath = Join-Path $configRoot "api-policies.json"

function Read-JsonFile($Path) {
  if (!(Test-Path $Path)) {
    return $null
  }

  return Get-Content $Path -Raw | ConvertFrom-Json
}

function Get-ExclusionKey($Exclusion) {
  return "$($Exclusion.matchVariable)|$($Exclusion.selectorMatchOperator)|$($Exclusion.selector)|$($Exclusion.ruleSet)|$($Exclusion.ruleGroup)|$($Exclusion.ruleId)"
}

function Format-Exclusion($Exclusion) {
  return "$($Exclusion.selector) / $($Exclusion.ruleGroup) / $($Exclusion.ruleId)"
}

function Get-ConfigPackage($Path) {
  $exclusionsPath = Join-Path $Path "exclusions.json"
  $overridesPath = Join-Path $Path "rule-overrides.json"

  if (!(Test-Path $exclusionsPath) -or !(Test-Path $overridesPath)) {
    return [pscustomobject]@{
      Path = $Path
      Exists = $false
      Exclusions = @()
      Overrides = @()
    }
  }

  $exclusionsJson = Read-JsonFile $exclusionsPath
  $overridesJson = Read-JsonFile $overridesPath

  return [pscustomobject]@{
    Path = $Path
    Exists = $true
    Exclusions = @($exclusionsJson.exclusions)
    Overrides = @($overridesJson.overrides)
  }
}

function Merge-Exclusions($Packages, $DisabledExclusions) {
  $disabledKeys = @{}
  foreach ($exclusion in @($DisabledExclusions)) {
    if ($null -ne $exclusion) {
      $disabledKeys[(Get-ExclusionKey $exclusion)] = $true
    }
  }

  $merged = [ordered]@{}
  foreach ($package in $Packages) {
    foreach ($exclusion in @($package.Exclusions)) {
      $key = Get-ExclusionKey $exclusion
      if (!$disabledKeys.Contains($key) -and !$merged.Contains($key)) {
        $merged[$key] = $exclusion
      }
    }
  }

  return @($merged.Values)
}

function Merge-Overrides($Packages) {
  $merged = [ordered]@{}
  foreach ($package in $Packages) {
    foreach ($group in @($package.Overrides)) {
      foreach ($rule in @($group.rules)) {
        $key = "$($group.ruleGroup).$($rule.ruleId)"
        $merged[$key] = [pscustomobject]@{
          ruleGroup = $group.ruleGroup
          ruleId = $rule.ruleId
          action = $rule.action
        }
      }
    }
  }

  return @($merged.Values)
}

if (!(Test-Path $apiPolicyPath)) {
  throw "Missing API policy registry: $apiPolicyPath"
}

$apiPolicyConfig = Read-JsonFile $apiPolicyPath
$basePackage = Get-ConfigPackage (Join-Path $configRoot "base")
$environmentPackage = Get-ConfigPackage (Join-Path $configRoot $Environment)
$apiProperties = @()
if ($null -ne $apiPolicyConfig.apiPolicies) {
  $apiProperties = @($apiPolicyConfig.apiPolicies.PSObject.Properties)
}

$results = @()

if (@($apiPolicyConfig.base.pathPatterns).Count -gt 0) {
  $basePackages = @($basePackage, $environmentPackage)
  $results += [pscustomobject]@{
    policy = "base"
    environment = $Environment
    pathPatterns = @($apiPolicyConfig.base.pathPatterns)
    configSources = @($basePackages | Where-Object { $_.Exists } | ForEach-Object { Resolve-Path -Relative $_.Path })
    inheritedBaseExclusions = @($basePackage.Exclusions).Count
    disabledBaseExclusions = @()
    effectiveExclusions = @(Merge-Exclusions $basePackages @())
    effectiveRuleOverrides = @(Merge-Overrides $basePackages)
  }
}

foreach ($api in $apiProperties) {
  $apiPackage = Get-ConfigPackage (Join-Path $configRoot "$Environment/apis/$($api.Name)")
  $packages = @($basePackage, $environmentPackage, $apiPackage)
  $disabledExclusions = @()
  if ($null -ne $api.Value.disabledBaseExclusions) {
    $disabledExclusions = @($api.Value.disabledBaseExclusions)
  }

  $results += [pscustomobject]@{
    policy = $api.Name
    environment = $Environment
    pathPatterns = @($api.Value.pathPatterns)
    configSources = @($packages | Where-Object { $_.Exists } | ForEach-Object { Resolve-Path -Relative $_.Path })
    inheritedBaseExclusions = @($basePackage.Exclusions).Count
    disabledBaseExclusions = @($disabledExclusions)
    effectiveExclusions = @(Merge-Exclusions $packages $disabledExclusions)
    effectiveRuleOverrides = @(Merge-Overrides $packages)
  }
}

if ($AsJson) {
  $results | ConvertTo-Json -Depth 20
  exit 0
}

Write-Host "Environment: $Environment"
Write-Host ""

foreach ($result in $results) {
  Write-Host "Policy: $($result.policy)"
  Write-Host "Path patterns: $(@($result.pathPatterns) -join ', ')"
  Write-Host "Config sources: $(@($result.configSources) -join ', ')"
  Write-Host "Inherited base exclusions: $($result.inheritedBaseExclusions)"

  if (@($result.disabledBaseExclusions).Count -gt 0) {
    Write-Host "Disabled inherited exclusions:"
    foreach ($exclusion in @($result.disabledBaseExclusions)) {
      Write-Host "  - $(Format-Exclusion $exclusion)"
    }
  } else {
    Write-Host "Disabled inherited exclusions: none"
  }

  if (@($result.effectiveRuleOverrides).Count -gt 0) {
    Write-Host "Effective rule overrides:"
    foreach ($override in @($result.effectiveRuleOverrides)) {
      Write-Host "  - $($override.ruleGroup) / $($override.ruleId) / $($override.action)"
    }
  } else {
    Write-Host "Effective rule overrides: none"
  }

  Write-Host "Effective exclusions:"
  foreach ($exclusion in @($result.effectiveExclusions)) {
    Write-Host "  - $(Format-Exclusion $exclusion)"
  }

  Write-Host ""
}