param(
  [ValidateSet("config", "gitlab", "security", "gitops", "all")]
  [string]$Phase = "config",

  [switch]$AllowOccupiedPorts
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-Failure([string]$Message) { $script:failures.Add($Message) }
function Add-Warning([string]$Message) { $script:warnings.Add($Message) }

function Test-Command([string]$Name, [bool]$Required) {
  if (Get-Command $Name -ErrorAction SilentlyContinue) {
    Write-Host "[PASS] command: $Name"
  } elseif ($Required) {
    Add-Failure "Required command not found: $Name"
  } else {
    Add-Warning "Optional command not found for this phase: $Name"
  }
}

function Test-EnvFile([string]$RelativePath) {
  $path = Join-Path $repoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    Add-Failure "Missing runtime environment file: $RelativePath"
    return
  }

  foreach ($line in [IO.File]::ReadAllLines($path)) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }
    if ($trimmed -notmatch '^[A-Z0-9_]+=') { Add-Failure "$RelativePath contains an invalid assignment: $line"; continue }
    $value = $trimmed.Substring($trimmed.IndexOf("=") + 1)
    if ([string]::IsNullOrWhiteSpace($value) -or $value -match "CHANGE_ME") {
      Add-Failure "$RelativePath contains an empty or placeholder value"
    }
  }
  Write-Host "[PASS] environment file: $RelativePath"
}

function Test-Compose([string]$ComposeFile, [string]$EnvFile, [string]$ExpectedProject) {
  $composePath = Join-Path $repoRoot $ComposeFile
  $envPath = Join-Path $repoRoot $EnvFile
  if (-not (Test-Path -LiteralPath $composePath -PathType Leaf) -or -not (Test-Path -LiteralPath $envPath -PathType Leaf)) { return }

  $config = & docker compose --env-file $envPath -f $composePath config 2>&1
  if ($LASTEXITCODE -ne 0) {
    Add-Failure "Compose validation failed for ${ComposeFile}: $($config -join ' ')"
    return
  }

  $rendered = $config -join "`n"
  if ($rendered -notmatch "(?m)^name:\s+$([regex]::Escape($ExpectedProject))\s*$") {
    Add-Failure "$ComposeFile does not resolve project name $ExpectedProject"
  }
  if ($rendered -notmatch "name:\s+devsecops-labs-cicd") {
    Add-Failure "$ComposeFile does not use shared network devsecops-labs-cicd"
  }
  if ($rendered -match "(?i)G:\\Cyber security\\Vinfast|/mnt/g/Cyber security/Vinfast") {
    Add-Failure "$ComposeFile resolves a stale Vinfast bind path"
  }
  if ($rendered -match "container_name:") {
    Add-Failure "$ComposeFile still uses fixed container_name"
  }

  Write-Host "[PASS] compose config: $ComposeFile"
}

function Test-Port([int]$Port, [string]$Purpose) {
  $listeners = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
  if ($listeners -and $AllowOccupiedPorts) { Add-Warning "Port $Port ($Purpose) is already listening." }
  elseif ($listeners) { Add-Failure "Port $Port ($Purpose) is already listening. Stop the owning process or use -AllowOccupiedPorts for read-only checks against a running lab." }
  else { Write-Host "[PASS] port available: $Port ($Purpose)" }
}

Set-Location $repoRoot
Test-Command -Name "docker" -Required $true
Test-EnvFile ".env.gitlab"
Test-EnvFile ".env.dependency-track"
Test-EnvFile ".env.defectdojo"
Test-EnvFile ".env.harbor"
Test-Compose "docker-compose.gitlab.yml" ".env.gitlab" "devsecops-labs-gitlab"
Test-Compose "docker-compose.dependency-track.yml" ".env.dependency-track" "devsecops-labs-dtrack"
Test-Compose "docker-compose.defectdojo.yml" ".env.defectdojo" "devsecops-labs-dojo"

$networkExists = & docker network inspect devsecops-labs-cicd 2>$null
if ($LASTEXITCODE -ne 0) {
  Add-Failure "External network devsecops-labs-cicd does not exist. Create it once with: docker network create devsecops-labs-cicd"
} else {
  Write-Host "[PASS] external network: devsecops-labs-cicd"
}

Test-Port 8929 "GitLab HTTP"
Test-Port 3224 "GitLab SSH"
Test-Port 8080 "Dependency-Track API"
Test-Port 8081 "Dependency-Track UI"
Test-Port 8082 "DefectDojo"
Test-Port 8083 "Harbor"

if ($Phase -in @("gitops", "all")) {
  Test-Command -Name "wsl" -Required $true
  Test-Command -Name "k3d" -Required $true
  Test-Command -Name "kubectl" -Required $true
}

foreach ($warning in $warnings) { Write-Warning $warning }
if ($failures.Count -gt 0) {
  foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
  throw "Lab configuration preflight failed with $($failures.Count) error(s)."
}

Write-Host "Lab configuration preflight passed for phase '$Phase'."
