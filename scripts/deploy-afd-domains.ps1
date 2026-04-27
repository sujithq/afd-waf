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

function Get-OptionalProperty($Object, [string]$Name, $DefaultValue = $null) {
  if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) {
    return $Object.$Name
  }

  return $DefaultValue
}

function Get-OptionalBool($Object, [string]$Name, [bool]$DefaultValue = $false) {
  $value = Get-OptionalProperty $Object $Name $null
  if ($null -eq $value) {
    return $DefaultValue
  }

  return $value -eq $true
}

function Get-RelativeDnsRecordName([string]$HostName, [string]$ZoneName) {
  if ($HostName.Equals($ZoneName, [System.StringComparison]::OrdinalIgnoreCase)) {
    return "@"
  }

  $zoneSuffix = ".$ZoneName"
  if (-not $HostName.EndsWith($zoneSuffix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Host name '$HostName' is not inside DNS zone '$ZoneName'."
  }

  return $HostName.Substring(0, $HostName.Length - $zoneSuffix.Length)
}

function Get-ValidationToken($CustomDomain) {
  $validationProperties = @(
    $CustomDomain.validationProperties,
    $CustomDomain.properties.validationProperties
  ) | Where-Object { $null -ne $_ } | Select-Object -First 1

  if ($null -eq $validationProperties) {
    return $null
  }

  return @(
    $validationProperties.validationToken,
    $validationProperties.token
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 1
}

function Test-TxtRecordValueExists([string]$ResourceGroupName, [string]$ZoneName, [string]$RecordName, [string]$Value) {
  if ($WhatIf) {
    return $false
  }

  $exists = Test-AzResourceExists -Arguments @(
    "network", "dns", "record-set", "txt", "show",
    "--resource-group", $ResourceGroupName,
    "--zone-name", $ZoneName,
    "--record-set-name", $RecordName
  )

  if (-not $exists) {
    return $false
  }

  $recordSet = Get-AzCliJson -Arguments @(
    "network", "dns", "record-set", "txt", "show",
    "--resource-group", $ResourceGroupName,
    "--zone-name", $ZoneName,
    "--record-set-name", $RecordName,
    "--only-show-errors"
  )

  $values = @($recordSet.txtRecords | ForEach-Object { $_.value } | ForEach-Object { $_ })
  return $values -contains $Value
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

Invoke-AzCli -Arguments @("account", "set", "--subscription", $SubscriptionId) | Out-Null

$endpointHostName = Invoke-AzCli -Arguments @(
  "afd", "endpoint", "show",
  "--resource-group", $ResourceGroupName,
  "--profile-name", $profileName,
  "--endpoint-name", $endpointName,
  "--query", "hostName",
  "--output", "tsv"
)

if ($WhatIf -and [string]::IsNullOrWhiteSpace([string]$endpointHostName)) {
  $endpointHostName = "$endpointName.azurefd.net"
}

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
  $dns = Get-OptionalProperty $domain "dns" $null
  $dnsZoneName = [string](Get-OptionalProperty $dns "zoneName" "")
  $dnsResourceGroupName = [string](Get-OptionalProperty $dns "resourceGroupName" $ResourceGroupName)
  $createDnsZone = Get-OptionalBool $dns "createZone" $false
  $manageDnsRecords = Get-OptionalBool $dns "manageRecords" $createDnsZone
  $dnsTtl = [int](Get-OptionalProperty $dns "ttl" 300)
  $dnsZoneId = [string](Get-OptionalProperty $domain "dnsZoneId" "")

  Write-Host ""
  Write-Host "Processing $domainName -> $hostName"

  if (-not [string]::IsNullOrWhiteSpace($dnsZoneName)) {
    $relativeRecordName = Get-RelativeDnsRecordName $hostName $dnsZoneName
    if ($createDnsZone) {
      Write-Host "Creating or updating Azure DNS zone '$dnsZoneName' in resource group '$dnsResourceGroupName'."
      Invoke-AzCli -Arguments @(
        "network", "dns", "zone", "create",
        "--resource-group", $dnsResourceGroupName,
        "--name", $dnsZoneName,
        "--only-show-errors"
      ) | Out-Null
    }

    $resolvedDnsZoneId = Invoke-AzCli -Arguments @(
      "network", "dns", "zone", "show",
      "--resource-group", $dnsResourceGroupName,
      "--name", $dnsZoneName,
      "--query", "id",
      "--output", "tsv"
    )

    if (-not [string]::IsNullOrWhiteSpace($resolvedDnsZoneId)) {
      $dnsZoneId = [string]$resolvedDnsZoneId
    }

    if ($WhatIf -and [string]::IsNullOrWhiteSpace($dnsZoneId)) {
      $dnsZoneId = "/subscriptions/$SubscriptionId/resourceGroups/$dnsResourceGroupName/providers/Microsoft.Network/dnsZones/$dnsZoneName"
    }
  }

  $customDomainExists = Test-AzResourceExists -Arguments @(
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

    if (-not [string]::IsNullOrWhiteSpace($dnsZoneId)) {
      $createArgs += @("--azure-dns-zone", $dnsZoneId)
    }

    Invoke-AzCli $createArgs | Out-Null
  }
  else {
    Write-Host "Custom domain '$customDomainName' already exists."
  }

  $customDomain = Get-AzCliJson -Arguments @(
    "afd", "custom-domain", "show",
    "--resource-group", $ResourceGroupName,
    "--profile-name", $profileName,
    "--custom-domain-name", $customDomainName,
    "--only-show-errors"
  )

  $customDomainId = if ($WhatIf) { "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Cdn/profiles/$profileName/customDomains/$customDomainName" } else { $customDomain.id }

  if ($manageDnsRecords) {
    if ([string]::IsNullOrWhiteSpace($dnsZoneName)) {
      throw "Domain policy '$domainName' sets dns.manageRecords but does not set dns.zoneName."
    }

    $relativeRecordName = Get-RelativeDnsRecordName $hostName $dnsZoneName
    Write-Host "Creating or updating CNAME '$relativeRecordName.$dnsZoneName' -> '$endpointHostName'."
    Invoke-AzCli -Arguments @(
      "network", "dns", "record-set", "cname", "set-record",
      "--resource-group", $dnsResourceGroupName,
      "--zone-name", $dnsZoneName,
      "--record-set-name", $relativeRecordName,
      "--cname", $endpointHostName,
      "--ttl", "$dnsTtl",
      "--only-show-errors"
    ) | Out-Null

    $validationToken = Get-ValidationToken $customDomain
    if (-not [string]::IsNullOrWhiteSpace([string]$validationToken)) {
      $txtRecordName = if ($relativeRecordName -eq "@") { "_dnsauth" } else { "_dnsauth.$relativeRecordName" }
      if (-not (Test-TxtRecordValueExists $dnsResourceGroupName $dnsZoneName $txtRecordName $validationToken)) {
        Write-Host "Creating TXT '$txtRecordName.$dnsZoneName' for Front Door validation."
        Invoke-AzCli -Arguments @(
          "network", "dns", "record-set", "txt", "add-record",
          "--resource-group", $dnsResourceGroupName,
          "--zone-name", $dnsZoneName,
          "--record-set-name", $txtRecordName,
          "--value", $validationToken,
          "--only-show-errors"
        ) | Out-Null
      }
      else {
        Write-Host "TXT '$txtRecordName.$dnsZoneName' already contains the Front Door validation token."
      }
    }
    else {
      Write-Host "Front Door validation token was not returned by Azure CLI. Inspect the custom domain in Azure and create the _dnsauth TXT record if validation is pending."
    }
  }

  foreach ($api in @($domain.apis.PSObject.Properties)) {
    $routeName = "$($api.Name)-route"
    Write-Host "Binding route '$routeName' to custom domain '$customDomainName'."
    Invoke-AzCli -Arguments @(
      "afd", "route", "update",
      "--resource-group", $ResourceGroupName,
      "--profile-name", $profileName,
      "--endpoint-name", $endpointName,
      "--route-name", $routeName,
      "--custom-domains", $customDomainName,
      "--only-show-errors"
    ) | Out-Null
  }

  $wafPolicyId = Invoke-AzCli -Arguments @(
    "network", "front-door", "waf-policy", "show",
    "--resource-group", $ResourceGroupName,
    "--name", $wafPolicyName,
    "--query", "id",
    "--output", "tsv"
  )

  if ($WhatIf -and [string]::IsNullOrWhiteSpace([string]$wafPolicyId)) {
    $wafPolicyId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Network/frontDoorWebApplicationFirewallPolicies/$wafPolicyName"
  }

  $securityPolicyExists = Test-AzResourceExists -Arguments @(
    "afd", "security-policy", "show",
    "--resource-group", $ResourceGroupName,
    "--profile-name", $profileName,
    "--security-policy-name", $securityPolicyName
  )

  $securityPolicyCommand = if ($securityPolicyExists) { "update" } else { "create" }
  Write-Host "$($securityPolicyCommand.Substring(0,1).ToUpperInvariant())$($securityPolicyCommand.Substring(1)) security policy '$securityPolicyName'."
  Invoke-AzCli -Arguments @(
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
  if (-not $manageDnsRecords) {
    Write-Host "Create/verify DNS: CNAME $hostName -> $endpointHostName"
    Write-Host "If validation is pending, inspect the custom domain in Azure for the required _dnsauth TXT token."
  }
}