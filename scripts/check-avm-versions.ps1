Param(
  [string]$RepoRoot = "."
)

$ErrorActionPreference = "Stop"

Write-Host "Checking AVM governance manifest and markers"

$manifestPath = Join-Path $RepoRoot "infra/avm/manifest.json"
if (!(Test-Path $manifestPath)) {
  Write-Error "Missing AVM manifest at infra/avm/manifest.json"
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
if (-not $manifest.entries -or $manifest.entries.Count -eq 0) {
  Write-Error "AVM manifest has no entries."
}

$versionPattern = '^\d+\.\d+\.\d+([\-+].+)?$'
foreach ($entry in $manifest.entries) {
  if (-not $entry.id -or -not $entry.file -or -not $entry.moduleRef -or -not $entry.pinnedVersion) {
    Write-Error "Invalid AVM manifest entry detected."
  }

  if ($entry.pinnedVersion -notmatch $versionPattern) {
    Write-Error "Invalid pinnedVersion '$($entry.pinnedVersion)' for entry '$($entry.id)'."
  }

  $targetFile = Join-Path $RepoRoot $entry.file
  if (!(Test-Path $targetFile)) {
    Write-Error "Manifest entry '$($entry.id)' points to missing file '$($entry.file)'."
  }

  $text = Get-Content $targetFile -Raw
  if ($text -notmatch [regex]::Escape("avm-id: $($entry.id)")) {
    Write-Error "File '$($entry.file)' is missing marker 'avm-id: $($entry.id)'."
  }
}

Write-Host "AVM governance check passed"
