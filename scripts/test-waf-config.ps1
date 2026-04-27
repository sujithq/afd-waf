Param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot ".."))
)

$ErrorActionPreference = "Stop"

Push-Location $RepoRoot
try {
  $schemaPath = "config/waf/schema/waf-tuning.schema.json"
  $apiPolicySchemaPath = "config/waf/schema/api-policies.schema.json"

  if (!(Test-Path $schemaPath)) {
    throw "Missing schema file: $schemaPath"
  }

  if (!(Test-Path $apiPolicySchemaPath)) {
    throw "Missing schema file: $apiPolicySchemaPath"
  }

  $apiPolicyPath = "config/waf/api-policies.json"
  if (!(Test-Path $apiPolicyPath)) {
    throw "Missing API policy registry: $apiPolicyPath"
  }

  $isApiPolicyValid = Test-Json -Path $apiPolicyPath -SchemaFile $apiPolicySchemaPath
  if (-not $isApiPolicyValid) {
    throw "Schema validation failed for $apiPolicyPath"
  }

  $apiPolicyConfig = Get-Content $apiPolicyPath | ConvertFrom-Json
  if ($null -eq $apiPolicyConfig.base.enabled) {
    throw "config/waf/api-policies.json must define base.enabled"
  }

  $apimCompositionPath = "infra/terraform/modules/apim-composition/main.tf"
  if (!(Test-Path $apimCompositionPath)) {
    throw "Missing APIM composition file: $apimCompositionPath"
  }

  $apimComposition = Get-Content $apimCompositionPath -Raw
  $apimApiPathsByName = @{}
  foreach ($match in [regex]::Matches($apimComposition, '(?ms)^\s{4}[A-Za-z0-9_-]+\s*=\s*\{\s*name\s*=\s*"([^"]+)".*?^\s*path\s*=\s*"([^"]+)"')) {
    $apimApiPathsByName[$match.Groups[1].Value] = $match.Groups[2].Value
  }

  if ($apimApiPathsByName.Count -eq 0) {
    throw "No APIM API name/path pairs were found in $apimCompositionPath"
  }

  function Get-ExclusionKey($exclusion) {
    return "$($exclusion.matchVariable)|$($exclusion.selectorMatchOperator)|$($exclusion.selector)|$($exclusion.ruleSet)|$($exclusion.ruleGroup)|$($exclusion.ruleId)"
  }

  function Get-PathPrefix($pattern) {
    if ($pattern.EndsWith('*')) {
      return $pattern.Substring(0, $pattern.Length - 1)
    }

    return $pattern
  }

  function Test-PathPatternOverlap($left, $right) {
    $leftPrefix = Get-PathPrefix $left.pattern
    $rightPrefix = Get-PathPrefix $right.pattern

    return $leftPrefix.StartsWith($rightPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
      $rightPrefix.StartsWith($leftPrefix, [System.StringComparison]::OrdinalIgnoreCase)
  }

  function Get-ApiPathPattern($apimPath) {
    return "/$apimPath/*"
  }

  $apiProperties = @()
  if ($null -ne $apiPolicyConfig.apiPolicies) {
    $apiProperties = @($apiPolicyConfig.apiPolicies.PSObject.Properties)
  }

  $declaredApis = @($apiProperties | ForEach-Object { $_.Name })
  foreach ($api in $apiProperties) {
    if (-not $apimApiPathsByName.ContainsKey($api.Value.apimApiName)) {
      throw "API policy '$($api.Name)' references APIM API '$($api.Value.apimApiName)', but no matching API name is defined in $apimCompositionPath"
    }
  }

  $pathPatterns = @()

  foreach ($api in $apiProperties) {
    $apiPathPattern = Get-ApiPathPattern ($apimApiPathsByName[$api.Value.apimApiName])
    $pathPatterns += [pscustomobject]@{
      policy = $api.Name
      pattern = $apiPathPattern
    }
  }

  $patternsByValue = $pathPatterns | Group-Object -Property pattern
  foreach ($group in $patternsByValue) {
    if ($group.Count -gt 1) {
      $owners = ($group.Group | ForEach-Object { $_.policy }) -join ", "
      throw "Path pattern '$($group.Name)' is declared by multiple WAF policies: $owners"
    }
  }

  for ($i = 0; $i -lt $pathPatterns.Count; $i++) {
    for ($j = $i + 1; $j -lt $pathPatterns.Count; $j++) {
      $left = $pathPatterns[$i]
      $right = $pathPatterns[$j]

      if (Test-PathPatternOverlap $left $right) {
        throw "API path pattern '$($left.pattern)' in API policy '$($left.policy)' overlaps with '$($right.pattern)' in API policy '$($right.policy)'. Use one policy for the broader path or make the patterns non-overlapping."
      }
    }
  }

  $apiOverlayDirs = @(Get-ChildItem config/waf -Directory -Recurse | Where-Object { $_.Parent.Name -eq "apis" })
  foreach ($dir in $apiOverlayDirs) {
    if ($declaredApis -notcontains $dir.Name) {
      throw "API overlay folder '$($dir.FullName)' is not declared in config/waf/api-policies.json"
    }
  }

  $baseExclusionsPath = "config/waf/base/exclusions.json"
  if (!(Test-Path $baseExclusionsPath)) {
    throw "Missing base exclusions file: $baseExclusionsPath"
  }

  $baseExclusions = @((Get-Content $baseExclusionsPath | ConvertFrom-Json).exclusions)
  $baseExclusionKeys = @($baseExclusions | ForEach-Object { Get-ExclusionKey $_ })

  $exclusionFiles = Get-ChildItem config/waf -Recurse -File -Filter exclusions.json
  if ($exclusionFiles.Count -eq 0) {
    throw "No WAF exclusions.json files found under config/waf"
  }

  foreach ($file in $exclusionFiles) {
    $isValid = Test-Json -Path $file.FullName -SchemaFile $schemaPath
    if (-not $isValid) {
      throw "Schema validation failed for $($file.FullName)"
    }

    $overridePath = Join-Path $file.DirectoryName "rule-overrides.json"
    if (!(Test-Path $overridePath)) {
      throw "Missing matching rule-overrides.json for $($file.FullName)"
    }

    $exclusionsJson = Get-Content $file.FullName | ConvertFrom-Json
    Get-Content $overridePath | ConvertFrom-Json | Out-Null

    foreach ($disabledExclusion in @($exclusionsJson.disabledBaseExclusions)) {
      if ($null -eq $disabledExclusion) {
        continue
      }

      if ($file.Directory.Parent.Name -ne "apis") {
        throw "disabledBaseExclusions is only allowed in API-specific config packages: $($file.FullName)"
      }

      if ($declaredApis -notcontains $file.Directory.Name) {
        throw "API config package '$($file.Directory.FullName)' disables a base exclusion but is not declared in config/waf/api-policies.json"
      }

      $disabledKey = Get-ExclusionKey $disabledExclusion
      if ($baseExclusionKeys -notcontains $disabledKey) {
        throw "API config package '$($file.Directory.FullName)' disables a base exclusion that does not exist: $disabledKey"
      }
    }
  }

  $all = Get-ChildItem config/waf -Recurse -File | ForEach-Object { Get-Content $_.FullName -Raw }
  foreach ($txt in $all) {
    if ($txt -match '"ruleId"\s*:\s*"\*"') {
      throw "Wildcard ruleId is not allowed"
    }
  }

  Write-Output "WAF config validation passed"
}
finally {
  Pop-Location
}