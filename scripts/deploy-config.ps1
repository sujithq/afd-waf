Param(
  [ValidateSet("dev", "test", "prod")]
  [string]$Environment,
  [ValidateSet("Detection", "Prevention")]
  [string]$Mode = "Detection"
)

$ErrorActionPreference = "Stop"

Write-Host "Applying WAF config for environment: $Environment in mode: $Mode"

$exclusionsPath = "config/waf/$Environment/exclusions.json"
$overridesPath = "config/waf/$Environment/rule-overrides.json"

if (!(Test-Path $exclusionsPath)) { throw "Missing exclusions file: $exclusionsPath" }
if (!(Test-Path $overridesPath)) { throw "Missing overrides file: $overridesPath" }

Write-Host "This skeleton validates payload presence. Add az rest update command for your WAF policy id and API version."
