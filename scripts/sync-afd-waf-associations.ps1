Param(
  [Parameter(Mandatory = $true)]
  [string]$SubscriptionId,

  [Parameter(Mandatory = $true)]
  [string]$ResourceGroupName,

  [Parameter(Mandatory = $true)]
  [string]$ProfileName,

  [Parameter(Mandatory = $true)]
  [string]$EndpointName,

  [Parameter(Mandatory = $true)]
  [string]$NamePrefix,

  [Parameter(Mandatory = $true)]
  [string]$Environment,

  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")),

  [int]$PollSeconds = 20,

  [int]$MaxPollAttempts = 45
)

$ErrorActionPreference = "Stop"

function Invoke-AzCliJson($Arguments) {
  $output = & az @Arguments --only-show-errors -o json
  if ($LASTEXITCODE -ne 0) {
    throw "az $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
  }

  if ([string]::IsNullOrWhiteSpace($output)) {
    return $null
  }

  return $output | ConvertFrom-Json
}

function Get-NormalizedResourceName($Value) {
  return ($Value.ToLowerInvariant() -replace "-", "")
}

function Get-ApimApiPathsByName($Path) {
  $content = Get-Content $Path -Raw
  $paths = @{}

  foreach ($match in [regex]::Matches($content, '(?ms)^\s{4}[A-Za-z0-9_-]+\s*=\s*\{\s*name\s*=\s*"([^"]+)".*?^\s*path\s*=\s*"([^"]+)"')) {
    $paths[$match.Groups[1].Value] = $match.Groups[2].Value
  }

  if ($paths.Count -eq 0) {
    throw "No APIM API name/path pairs were found in $Path"
  }

  return $paths
}

Push-Location $RepoRoot
try {
  $apiPolicyPath = "config/waf/api-policies.json"
  $apimCompositionPath = "infra/terraform/modules/apim-composition/main.tf"

  if (!(Test-Path $apiPolicyPath)) {
    throw "Missing API policy registry: $apiPolicyPath"
  }

  if (!(Test-Path $apimCompositionPath)) {
    throw "Missing APIM composition file: $apimCompositionPath"
  }

  $apiPolicyConfig = Get-Content $apiPolicyPath | ConvertFrom-Json
  $apimApiPathsByName = Get-ApimApiPathsByName $apimCompositionPath
  $apiPolicies = @($apiPolicyConfig.apiPolicies.PSObject.Properties)

  if ($apiPolicies.Count -eq 0) {
    Write-Output "No API WAF policies declared; nothing to sync."
    return
  }

  $endpoint = Invoke-AzCliJson @("afd", "endpoint", "show", "--resource-group", $ResourceGroupName, "--profile-name", $ProfileName, "--endpoint-name", $EndpointName)
  $profileId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Cdn/profiles/$ProfileName"
  $apiVersion = "2024-09-01"

  foreach ($api in $apiPolicies) {
    $apiName = $api.Name
    $apimApiName = $api.Value.apimApiName

    if (-not $apimApiPathsByName.ContainsKey($apimApiName)) {
      throw "API policy '$apiName' references APIM API '$apimApiName', but no matching API name is defined in $apimCompositionPath"
    }

    $pathPattern = "/$($apimApiPathsByName[$apimApiName])/*"
    $wafPolicyName = Get-NormalizedResourceName "${NamePrefix}waf${Environment}${apiName}"
    $securityPolicyName = "$apiName-waf-association"

    $wafPolicy = Invoke-AzCliJson @("network", "front-door", "waf-policy", "show", "--resource-group", $ResourceGroupName, "--name", $wafPolicyName)

    $body = @{
      properties = @{
        parameters = @{
          type         = "WebApplicationFirewall"
          wafPolicy    = @{ id = $wafPolicy.id }
          associations = @(
            @{
              domains         = @(@{ id = $endpoint.id })
              patternsToMatch = @($pathPattern)
            }
          )
        }
      }
    } | ConvertTo-Json -Depth 20 -Compress

    $bodyPath = Join-Path ([System.IO.Path]::GetTempPath()) "afd-security-policy-$securityPolicyName.json"
    Set-Content -Path $bodyPath -Value $body -Encoding utf8

    $uri = "https://management.azure.com$profileId/securityPolicies/$securityPolicyName`?api-version=$apiVersion"
    Write-Output "Syncing AFD WAF association '$securityPolicyName' for pattern '$pathPattern'."
    & az rest --method put --uri $uri --body "@$bodyPath" --headers "Content-Type=application/json" --only-show-errors -o none
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to create or update AFD security policy '$securityPolicyName'."
    }

    for ($attempt = 1; $attempt -le $MaxPollAttempts; $attempt++) {
      $policy = Invoke-AzCliJson @("rest", "--method", "get", "--uri", $uri)
      $state = $policy.properties.provisioningState

      if ($state -eq "Succeeded") {
        Write-Output "AFD WAF association '$securityPolicyName' is ready."
        break
      }

      if ($attempt -eq $MaxPollAttempts) {
        throw "AFD WAF association '$securityPolicyName' did not reach Succeeded. Last state: $state"
      }

      Write-Output "Waiting for '$securityPolicyName' provisioning state '$state' ($attempt/$MaxPollAttempts)."
      Start-Sleep -Seconds $PollSeconds
    }
  }
}
finally {
  Pop-Location
}
