<#
.SYNOPSIS
Runs simple OData smoke tests through an Azure Front Door endpoint or custom domain.

.EXAMPLE
./scripts/smoke-odata.ps1 -BaseUrl https://api-a.wafdemo.squintelier.net -Paths odata1,odata2

.EXAMPLE
./scripts/smoke-odata.ps1 -BaseUrl https://api-b.wafdemo.squintelier.net -Paths odata3,odata4
#>
Param(
  [Parameter(Mandatory = $true)]
  [string]$BaseUrl,

  [string[]]$Paths = @("odata1", "odata2")
)

$ErrorActionPreference = "Stop"

if ($BaseUrl -notmatch '^https?://') {
  $BaseUrl = "https://$BaseUrl"
}

$BaseUrl = $BaseUrl.TrimEnd("/")

$queryTemplates = @(
  "Entities?`$filter=contains(Name,'a')&`$orderby=Name",
  "Entities?`$filter=startswith(Name,'I')&`$select=Id,Name"
)

$queries = for ($i = 0; $i -lt $Paths.Count; $i++) {
  $path = $Paths[$i].Trim("/")
  $template = $queryTemplates[$i % $queryTemplates.Count]
  "$BaseUrl/$path/$template"
}

foreach ($url in $queries) {
  Write-Host "Calling $url"
  $resp = Invoke-WebRequest -Uri $url -Method GET -UseBasicParsing
  if ($resp.StatusCode -lt 200 -or $resp.StatusCode -ge 300) {
    throw "Smoke test failed for $url"
  }
}

Write-Host "Smoke tests passed"
