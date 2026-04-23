Param(
  [Parameter(Mandatory = $true)]
  [string]$BaseUrl
)

$ErrorActionPreference = "Stop"

$queries = @(
  "$BaseUrl/odata1/Entities?`$filter=contains(Name,'a')&`$orderby=Name",
  "$BaseUrl/odata2/Entities?`$filter=startswith(Name,'I')&`$select=Id,Name"
)

foreach ($url in $queries) {
  Write-Host "Calling $url"
  $resp = Invoke-WebRequest -Uri $url -Method GET -UseBasicParsing
  if ($resp.StatusCode -lt 200 -or $resp.StatusCode -ge 300) {
    throw "Smoke test failed for $url"
  }
}

Write-Host "Smoke tests passed"
