Param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("dev", "test", "prod")]
  [string]$Environment,

  [string]$ConfigPath = "config/waf/api-policies.json",

  [Parameter(Mandatory = $true)]
  [string]$SubscriptionId,

  [Parameter(Mandatory = $true)]
  [string]$ResourceGroupName,

  [Parameter(Mandatory = $true)]
  [string]$NamePrefix,

  [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

function Get-SanitizedResourceName([string]$Value) {
  return ($Value.ToLowerInvariant() -replace "-", "")
}

function Invoke-AzCli([string[]]$Arguments) {
  if ($WhatIf) {
    Write-Host "az $($Arguments -join ' ')"
    return $null
  }

  $output = & az @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI command failed: az $($Arguments -join ' ')"
  }

  return $output
}

function Get-AzCliJson([string[]]$Arguments) {
  $output = Invoke-AzCli ($Arguments + @("--output", "json"))
  if ($null -eq $output) {
    return $null
  }

  return $output | ConvertFrom-Json
}

function Test-AzResourceExists([string[]]$Arguments) {
  if ($WhatIf) {
    return $false
  }

  & az @Arguments --output none 2>$null
  return $LASTEXITCODE -eq 0
}

$resolvedConfigPath = Resolve-Path $ConfigPath
$config = Get-Content $resolvedConfigPath -Raw | ConvertFrom-Json
$domainPolicies = @($config.domainPolicies.PSObject.Properties | Where-Object { $_.Value.enabled -eq $true })

if ($domainPolicies.Count -eq 0) {
  Write-Host "No enabled domain policies found in $ConfigPath. Nothing to create."
  return
}

$profileName = "$NamePrefix-afd-$Environment"
$endpointName = "$NamePrefix-ep-$Environment"

Invoke-AzCli @("account", "set", "--subscription", $SubscriptionId) | Out-Null

$endpointHostName = Invoke-AzCli @(
  "afd", "endpoint", "show",
  "--resource-group", $ResourceGroupName,
  "--profile-name", $profileName,
  "--endpoint-name", $endpointName,
  "--query", "hostName",
  "--output", "tsv"
)

Write-Host "AFD profile: $profileName"
Write-Host "AFD endpoint: $endpointName"
Write-Host "AFD endpoint hostname: $endpointHostName"

foreach ($domainPolicy in $domainPolicies) {
  $domainName = $domainPolicy.Name
  $domain = $domainPolicy.Value
  $hostName = [string]$domain.hostName

  if ($hostName -match '(^|\.)example\.com$') {
    throw "Domain policy '$domainName' is enabled but uses placeholder host name '$hostName'. Use a real FQDN that you own."
  }

  $customDomainName = Get-SanitizedResourceName "$NamePrefix-$Environment-$domainName"
  $securityPolicyName = Get-SanitizedResourceName "$domainName-waf-association"
  $wafPolicyName = Get-SanitizedResourceName "$NamePrefix`waf$Environment$domainName"

  Write-Host ""
  Write-Host "Processing $domainName -> $hostName"

  $customDomainExists = Test-AzResourceExists @(
    "afd", "custom-domain", "show",
    "--resource-group", $ResourceGroupName,
    "--profile-name", $profileName,
    "--custom-domain-name", $customDomainName
  )

  if (-not $customDomainExists) {
    $createArgs = @(
      "afd", "custom-domain", "create",
      "--resource-group", $ResourceGroupName,
      "--profile-name", $profileName,
      "--custom-domain-name", $customDomainName,
      "--host-name", $hostName,
      "--minimum-tls-version", "TLS12",
      "--certificate-type", "ManagedCertificate",
      "--only-show-errors"
    )

    if ($null -ne $domain.dnsZoneId -and [string]$domain.dnsZoneId -ne "") {
      $createArgs += @("--azure-dns-zone", [string]$domain.dnsZoneId)
    }

    Invoke-AzCli $createArgs | Out-Null
  }
  else {
    Write-Host "Custom domain '$customDomainName' already exists."
  }

  $customDomain = Get-AzCliJson @(
    "afd", "custom-domain", "show",
    "--resource-group", $ResourceGroupName,
    "--profile-name", $profileName,
    "--custom-domain-name", $customDomainName,
    "--only-show-errors"
  )

  $customDomainId = if ($WhatIf) { "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Cdn/profiles/$profileName/customDomains/$customDomainName" } else { $customDomain.id }

  foreach ($api in @($domain.apis.PSObject.Properties)) {
    $routeName = "$($api.Name)-route"
    Write-Host "Binding route '$routeName' to custom domain '$customDomainName'."
    Invoke-AzCli @(
      "afd", "route", "update",
      "--resource-group", $ResourceGroupName,
      "--profile-name", $profileName,
      "--endpoint-name", $endpointName,
      "--route-name", $routeName,
      "--custom-domains", $customDomainId,
      "--only-show-errors"
    ) | Out-Null
  }

  $wafPolicyId = Invoke-AzCli @(
    "network", "front-door", "waf-policy", "show",
    "--resource-group", $ResourceGroupName,
    "--name", $wafPolicyName,
    "--query", "id",
    "--output", "tsv"
  )

  $securityPolicyExists = Test-AzResourceExists @(
    "afd", "security-policy", "show",
    "--resource-group", $ResourceGroupName,
    "--profile-name", $profileName,
    "--security-policy-name", $securityPolicyName
  )

  $securityPolicyCommand = if ($securityPolicyExists) { "update" } else { "create" }
  Write-Host "$($securityPolicyCommand.Substring(0,1).ToUpperInvariant())$($securityPolicyCommand.Substring(1)) security policy '$securityPolicyName'."
  Invoke-AzCli @(
    "afd", "security-policy", $securityPolicyCommand,
    "--resource-group", $ResourceGroupName,
    "--profile-name", $profileName,
    "--security-policy-name", $securityPolicyName,
    "--domains", $customDomainId,
    "--waf-policy", $wafPolicyId,
    "--only-show-errors"
  ) | Out-Null

  $domainState = if ($WhatIf) { "WhatIf" } else { $customDomain.domainValidationState }
  Write-Host "Domain validation state: $domainState"
  Write-Host "Create/verify DNS: CNAME $hostName -> $endpointHostName"
  Write-Host "If validation is pending, inspect the custom domain in Azure for the required _dnsauth TXT token."
}