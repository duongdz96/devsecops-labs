param(
  [switch]$Force
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function New-RandomBytes {
  param([int]$Length)
  $bytes = New-Object byte[] $Length
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
  return $bytes
}

function ConvertTo-Hex {
  param([byte[]]$Bytes)
  return (($Bytes | ForEach-Object { $_.ToString("x2") }) -join "")
}

function New-Password {
  $base64 = [Convert]::ToBase64String((New-RandomBytes -Length 32))
  return $base64.TrimEnd("=").Replace("+", "A").Replace("/", "B")
}

function Set-TemplateValues {
  param(
    [string]$TemplateName,
    [string]$OutputName,
    [hashtable]$Values
  )

  $templatePath = Join-Path $repoRoot $TemplateName
  $outputPath = Join-Path $repoRoot $OutputName

  if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
    throw "Template not found: $templatePath"
  }
  if ((Test-Path -LiteralPath $outputPath) -and -not $Force) {
    throw "$outputPath already exists. Re-run with -Force only when intentionally rotating a clean lab."
  }

  $lines = [System.IO.File]::ReadAllLines($templatePath)
  $rendered = foreach ($line in $lines) {
    if ($line -match '^([A-Z0-9_]+)=') {
      $key = $Matches[1]
      if ($Values.ContainsKey($key)) { "${key}=$($Values[$key])" } else { $line }
    } else {
      $line
    }
  }

  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllLines($outputPath, $rendered, $utf8NoBom)
  Write-Host "Generated local environment file: $outputPath"
}

$outputs = @(
  ".env.gitlab",
  ".env.dependency-track",
  ".env.defectdojo",
  ".env.harbor"
)
if (-not $Force) {
  $existing = $outputs | Where-Object { Test-Path -LiteralPath (Join-Path $repoRoot $_) }
  if ($existing) {
    throw "Refusing partial secret rotation. Existing runtime file(s): $($existing -join ', '). Remove the complete clean-lab set first, or use -Force intentionally."
  }
}

$dtrackPassword = New-Password
$dojoPassword = New-Password
$created = New-Object System.Collections.Generic.List[string]
try {
  Set-TemplateValues -TemplateName ".env.gitlab.example" -OutputName ".env.gitlab" -Values @{}
  $created.Add((Join-Path $repoRoot ".env.gitlab"))
  Set-TemplateValues -TemplateName ".env.dependency-track.example" -OutputName ".env.dependency-track" -Values @{
    DTRACK_POSTGRES_PASSWORD = $dtrackPassword
    DTRACK_ADMIN_PASSWORD = New-Password
    DTRACK_ALPINE_SECRET_KEY = ConvertTo-Hex (New-RandomBytes -Length 32)
  }
  $created.Add((Join-Path $repoRoot ".env.dependency-track"))
  Set-TemplateValues -TemplateName ".env.defectdojo.example" -OutputName ".env.defectdojo" -Values @{
    DOJO_DATABASE_PASSWORD = $dojoPassword
    DD_ADMIN_PASSWORD = New-Password
    DD_SECRET_KEY = ConvertTo-Hex (New-RandomBytes -Length 48)
    DD_CREDENTIAL_AES_256_KEY = [Convert]::ToBase64String((New-RandomBytes -Length 32))
  }
  $created.Add((Join-Path $repoRoot ".env.defectdojo"))
  Set-TemplateValues -TemplateName ".env.harbor.example" -OutputName ".env.harbor" -Values @{
    HARBOR_ADMIN_PASSWORD = New-Password
    HARBOR_DB_PASSWORD = New-Password
  }
  $created.Add((Join-Path $repoRoot ".env.harbor"))
} catch {
  if (-not $Force) {
    $created | ForEach-Object { Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue }
  }
  throw
}

Write-Host "Secrets were written only to gitignored local environment files. Keep these values stable after first boot."
Write-Host "Run scripts/New-HarborConfig.ps1 next to render infra/harbor/harbor.yml."
