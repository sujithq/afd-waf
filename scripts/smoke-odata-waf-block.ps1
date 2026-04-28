<#
.SYNOPSIS
Runs one OData request that is expected to be blocked by Azure Front Door WAF.

.EXAMPLE
./scripts/smoke-odata-waf-block.ps1 -BaseUrl https://api-a.wafdemo.squintelier.net -Path odata1 -QueryString '$filter=contains(Name,''a'')'
#>
Param(
  [Parameter(Mandatory = $true)]
  [string]$BaseUrl,

  [string]$Path = "odata1",

  [string]$QueryString = "`$filter=contains(Name,'a')",

  [int[]]$ExpectedStatusCodes = @(403)
)

$ErrorActionPreference = "Stop"

if ($BaseUrl -notmatch '^https?://') {
  $BaseUrl = "https://$BaseUrl"
}

$BaseUrl = $BaseUrl.TrimEnd("/")
$Path = $Path.Trim("/")
$QueryString = $QueryString.TrimStart("?")
$url = "$BaseUrl/$Path/Entities?$QueryString"

Write-Host "Calling $url"

$statusCode = $null
$headers = $null
try {
  $response = Invoke-WebRequest -Uri $url -Method GET -UseBasicParsing
  $statusCode = [int]$response.StatusCode
  $headers = $response.Headers
}
catch {
  if ($null -eq $_.Exception.Response) {
    throw
  }

  $statusCode = [int]$_.Exception.Response.StatusCode
  $headers = $_.Exception.Response.Headers
}

$trackingReference = @(
  $headers["x-azure-ref"],
  $headers["X-Azure-Ref"]
) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 1

Write-Host "Status: $statusCode"
if (-not [string]::IsNullOrWhiteSpace([string]$trackingReference)) {
  Write-Host "x-azure-ref: $trackingReference"
}

if ($ExpectedStatusCodes -notcontains $statusCode) {
  throw "Expected status code $($ExpectedStatusCodes -join ', ') but received $statusCode. If this environment is in Detection mode, check WAF logs instead of expecting an HTTP block."
}

Write-Host "Expected WAF response observed"
