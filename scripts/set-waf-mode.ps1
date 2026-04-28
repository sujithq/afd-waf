<#
.SYNOPSIS
Switches Azure Front Door WAF policy mode directly with Azure CLI.

.EXAMPLE
./scripts/set-waf-mode.ps1 -Environment dev -Mode Detection -SubscriptionId <subscription-id> -NamePrefix acafd

.EXAMPLE
./scripts/set-waf-mode.ps1 -Environment dev -Mode Prevention -SubscriptionId <subscription-id> -NamePrefix acafd -Scope Domains -DomainName domain-a -WhatIf
#>
Param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("dev", "test", "prod")]
  [string]$Environment,

  [Parameter(Mandatory = $true)]
  [ValidateSet("Detection", "Prevention")]
  [string]$Mode,

  [Parameter(Mandatory = $true)]
  [string]$SubscriptionId,

  [Parameter(Mandatory = $true)]
  [string]$NamePrefix,

  [string]$ResourceGroupName,

  [ValidateSet("All", "Base", "Domains")]
  [string]$Scope = "All",

  [string[]]$DomainName = @(),

  [string]$ConfigPath = "config/waf/api-policies.json",

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

function Get-PolicyTargets {
  $targets = @()

  if ($Scope -in @("All", "Base")) {
    $targets += [pscustomobject]@{
      Name = Get-SanitizedResourceName "$NamePrefix`waf$Environment"
      Kind = "base"
    }
  }

  if ($Scope -in @("All", "Domains")) {
    $resolvedConfigPath = Resolve-Path $ConfigPath
    $config = Get-Content $resolvedConfigPath -Raw | ConvertFrom-Json
    $domainPolicies = @($config.domainPolicies.PSObject.Properties | Where-Object { $_.Value.enabled -eq $true })

    if ($DomainName.Count -gt 0) {
      $domainPolicies = @($domainPolicies | Where-Object { $DomainName -contains $_.Name })
      $missingDomains = @($DomainName | Where-Object { $domainPolicies.Name -notcontains $_ })
      if ($missingDomains.Count -gt 0) {
        throw "Domain policy not found or not enabled in ${ConfigPath}: $($missingDomains -join ', ')"
      }
    }

    foreach ($domainPolicy in $domainPolicies) {
      $targets += [pscustomobject]@{
        Name = Get-SanitizedResourceName "$NamePrefix`waf$Environment$($domainPolicy.Name)"
        Kind = "domain:$($domainPolicy.Name)"
      }
    }
  }

  return $targets
}

if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) {
  $ResourceGroupName = "$NamePrefix-$Environment-rg"
}

Invoke-AzCli -Arguments @("account", "set", "--subscription", $SubscriptionId) | Out-Null

$targets = @(Get-PolicyTargets)
if ($targets.Count -eq 0) {
  throw "No WAF policies matched the requested scope."
}

foreach ($target in $targets) {
  Write-Host "Switching $($target.Kind) WAF policy '$($target.Name)' to $Mode."

  $before = Get-AzCliJson -Arguments @(
    "network", "front-door", "waf-policy", "show",
    "--resource-group", $ResourceGroupName,
    "--name", $target.Name,
    "--only-show-errors"
  )

  if ($null -ne $before) {
    Write-Host "Current mode: $($before.policySettings.mode)"
  }

  Invoke-AzCli -Arguments @(
    "network", "front-door", "waf-policy", "update",
    "--resource-group", $ResourceGroupName,
    "--name", $target.Name,
    "--mode", $Mode,
    "--only-show-errors"
  ) | Out-Null

  if (-not $WhatIf) {
    $after = Get-AzCliJson -Arguments @(
      "network", "front-door", "waf-policy", "show",
      "--resource-group", $ResourceGroupName,
      "--name", $target.Name,
      "--only-show-errors"
    )

    if ($after.policySettings.mode -ne $Mode) {
      throw "Policy '$($target.Name)' is still in mode '$($after.policySettings.mode)' after update."
    }

    Write-Host "Updated mode: $($after.policySettings.mode)"
  }
}

if (-not $WhatIf) {
  Write-Host "WAF mode switch complete. This is an operational Azure CLI change; update tfvars later if you want Terraform config to retain this mode as desired state."
}
