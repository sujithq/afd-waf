Param(
  [string]$RepoRoot = "."
)

$ErrorActionPreference = "Stop"

Write-Host "Checking AVM governance markers"

$bicepFiles = Get-ChildItem -Path $RepoRoot -Recurse -Filter *.bicep | Select-Object -ExpandProperty FullName
$tfFiles = Get-ChildItem -Path $RepoRoot -Recurse -Filter *.tf | Select-Object -ExpandProperty FullName

$hits = @()
foreach ($file in $bicepFiles + $tfFiles) {
  $text = Get-Content $file -Raw
  if ($text -match "AVM") {
    $hits += $file
  }
}

if ($hits.Count -eq 0) {
  Write-Error "No AVM markers were found. Add AVM composition notes or module references."
}

Write-Host "AVM marker check passed"
