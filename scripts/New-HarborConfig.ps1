param(
  [string]$EnvFile,
  [string]$TemplateFile,
  [string]$OutputFile
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $EnvFile) { $EnvFile = Join-Path $repoRoot ".env.harbor" }
if (-not $TemplateFile) { $TemplateFile = Join-Path $repoRoot "infra/harbor/harbor.yml.tmpl" }
if (-not $OutputFile) { $OutputFile = Join-Path $repoRoot "infra/harbor/harbor.yml" }

function Read-DotEnv {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Environment file not found: $Path. Copy .env.harbor.example to .env.harbor first."
  }

  $values = @{}
  foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }

    $separator = $trimmed.IndexOf("=")
    if ($separator -lt 1) { throw "Invalid environment line in ${Path}: $line" }

    $key = $trimmed.Substring(0, $separator).Trim()
    $value = $trimmed.Substring($separator + 1)
    if ($values.ContainsKey($key)) { throw "Duplicate environment key in ${Path}: $key" }
    $values[$key] = $value
  }

  return $values
}

function Assert-SafeValue {
  param([string]$Key, [string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) { throw "$Key must not be empty." }
  if ($Value -match "CHANGE_ME") { throw "$Key still contains CHANGE_ME." }
  if ($Value -match "[`r`n]" -or $Value -match "[\x00-\x1F]") {
    throw "$Key contains a control character."
  }
  if ($Value.Contains("'")) { throw "$Key must not contain a single quote because YAML values are single-quoted." }
}

$required = @(
  "HARBOR_HOSTNAME",
  "HARBOR_HTTP_PORT",
  "HARBOR_ADMIN_PASSWORD",
  "HARBOR_DB_PASSWORD",
  "HARBOR_DATA_DIR"
)

$values = Read-DotEnv -Path $EnvFile
foreach ($key in $required) {
  if (-not $values.ContainsKey($key)) { throw "Missing required key in ${EnvFile}: $key" }
  Assert-SafeValue -Key $key -Value $values[$key]
}

$port = 0
if (-not [int]::TryParse($values["HARBOR_HTTP_PORT"], [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
  throw "HARBOR_HTTP_PORT must be an integer from 1 through 65535."
}
if (-not $values["HARBOR_DATA_DIR"].StartsWith("/")) {
  throw "HARBOR_DATA_DIR must be an absolute Linux path because Harbor prepare passes it to Docker as a bind mount."
}

if (-not (Test-Path -LiteralPath $TemplateFile -PathType Leaf)) {
  throw "Harbor template not found: $TemplateFile"
}

$config = [System.IO.File]::ReadAllText($TemplateFile)
foreach ($key in $required) {
  $token = "__${key}__"
  if (-not $config.Contains($token)) { throw "Template token missing: $token" }
  $config = $config.Replace($token, $values[$key])
}

if ($config -match "__[A-Z0-9_]+__") {
  throw "Generated Harbor configuration still contains template tokens."
}

$outputDirectory = Split-Path -Parent $OutputFile
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
  throw "Output directory not found: $outputDirectory"
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($OutputFile, $config, $utf8NoBom)

Write-Host "Generated Harbor runtime configuration: $OutputFile"
Write-Host "Next manual step: copy the Harbor installer and this file to a WSL path without spaces, then run prepare/install."
