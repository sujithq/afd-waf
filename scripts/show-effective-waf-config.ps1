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
      DisabledBaseExclusions = @()
      Overrides = @()
    }
  }

  $exclusionsJson = Read-JsonFile $exclusionsPath
  $overridesJson = Read-JsonFile $overridesPath
  $disabledBaseExclusions = @()
  if ($null -ne $exclusionsJson.disabledBaseExclusions) {
    $disabledBaseExclusions = @($exclusionsJson.disabledBaseExclusions)
  }

  return [pscustomobject]@{
    Path = $Path
    Exists = $true
    Exclusions = @($exclusionsJson.exclusions)
    DisabledBaseExclusions = @($disabledBaseExclusions)
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

function Get-ApimApiPathsByName() {
  $apimCompositionPath = Join-Path $repoRoot "infra/terraform/modules/apim-composition/main.tf"
  if (!(Test-Path $apimCompositionPath)) {
    throw "Missing APIM composition file: $apimCompositionPath"
  }

  $apimComposition = Get-Content $apimCompositionPath -Raw
  $pathsByName = @{}
  foreach ($match in [regex]::Matches($apimComposition, '(?ms)^\s{4}[A-Za-z0-9_-]+\s*=\s*\{\s*name\s*=\s*"([^"]+)".*?^\s*path\s*=\s*"([^"]+)"')) {
    $pathsByName[$match.Groups[1].Value] = $match.Groups[2].Value
  }

  return $pathsByName
}

function Get-ApiPathPattern($ApimPath) {
  return "/$ApimPath/*"
}

if (!(Test-Path $apiPolicyPath)) {
  throw "Missing API policy registry: $apiPolicyPath"
}

$apiPolicyConfig = Read-JsonFile $apiPolicyPath
$apimApiPathsByName = Get-ApimApiPathsByName
$basePackage = Get-ConfigPackage (Join-Path $configRoot "base")
$environmentPackage = Get-ConfigPackage (Join-Path $configRoot $Environment)
$domainProperties = @()
if ($null -ne $apiPolicyConfig.domainPolicies) {
  $domainProperties = @($apiPolicyConfig.domainPolicies.PSObject.Properties)
}

$results = @()

if ($apiPolicyConfig.base.enabled -eq $true) {
  $basePackages = @($basePackage, $environmentPackage)
  $results += [pscustomobject]@{
    policy = "base"
    environment = $Environment
    pathPatterns = @("/*")
    configSources = @($basePackages | Where-Object { $_.Exists } | ForEach-Object { Resolve-Path -Relative $_.Path })
    inheritedBaseExclusions = @($basePackage.Exclusions).Count
    disabledBaseExclusions = @()
    effectiveExclusions = @(Merge-Exclusions $basePackages @())
    effectiveRuleOverrides = @(Merge-Overrides $basePackages)
  }
}

foreach ($domain in $domainProperties) {
  $domainPackage = Get-ConfigPackage (Join-Path $configRoot "$Environment/domains/$($domain.Name)")
  $packages = @($basePackage, $environmentPackage, $domainPackage)
  $domainApis = @($domain.Value.apis.PSObject.Properties | ForEach-Object {
    [pscustomobject]@{
      name = $_.Name
      apimApiName = $_.Value.apimApiName
      pathPattern = Get-ApiPathPattern ($apimApiPathsByName[$_.Value.apimApiName])
    }
  })
  $disabledExclusions = @($domainPackage.DisabledBaseExclusions)

  $results += [pscustomobject]@{
    policy = $domain.Name
    environment = $Environment
    hostName = $domain.Value.hostName
    dnsZoneId = $domain.Value.dnsZoneId
    customDomainEnabled = $domain.Value.enabled -eq $true
    apis = @($domainApis)
    pathPatterns = @($domainApis | ForEach-Object { $_.pathPattern })
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

Write-Output "Environment: $Environment"
Write-Output ""

foreach ($result in $results) {
  Write-Output "Policy: $($result.policy)"
  if ($null -ne $result.hostName) {
    Write-Output "Host name: $($result.hostName)"
    if ($null -ne $result.dnsZoneId) {
      Write-Output "DNS zone ID: $($result.dnsZoneId)"
    }
    Write-Output "Custom domain enabled: $($result.customDomainEnabled)"
  }
  if ($null -ne $result.apis -and @($result.apis).Count -gt 0) {
    Write-Output "APIs:"
    foreach ($api in @($result.apis)) {
      Write-Output "  - $($api.name) -> $($api.apimApiName) ($($api.pathPattern))"
    }
  }
  Write-Output "Path patterns: $(@($result.pathPatterns) -join ', ')"
  Write-Output "Config sources: $(@($result.configSources) -join ', ')"
  Write-Output "Inherited base exclusions: $($result.inheritedBaseExclusions)"

  if (@($result.disabledBaseExclusions).Count -gt 0) {
    Write-Output "Disabled inherited exclusions:"
    foreach ($exclusion in @($result.disabledBaseExclusions)) {
      Write-Output "  - $(Format-Exclusion $exclusion)"
    }
  } else {
    Write-Output "Disabled inherited exclusions: none"
  }

  if (@($result.effectiveRuleOverrides).Count -gt 0) {
    Write-Output "Effective rule overrides:"
    foreach ($override in @($result.effectiveRuleOverrides)) {
      Write-Output "  - $($override.ruleGroup) / $($override.ruleId) / $($override.action)"
    }
  } else {
    Write-Output "Effective rule overrides: none"
  }

  Write-Output "Effective exclusions:"
  foreach ($exclusion in @($result.effectiveExclusions)) {
    Write-Output "  - $(Format-Exclusion $exclusion)"
  }

  Write-Output ""
}
