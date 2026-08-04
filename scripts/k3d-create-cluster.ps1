param(
  [string]$ClusterName = "devsecops-gitops",
  [string]$HarborEndpoint = "host.docker.internal:8083"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command k3d -ErrorAction SilentlyContinue)) {
  throw "k3d was not found in PATH. Install k3d before running this script."
}

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
  throw "kubectl was not found in PATH. Install kubectl before running this script."
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$k3dDir = Join-Path $repoRoot ".k3d"
$registriesPath = Join-Path $k3dDir "registries.yaml"

if (-not (Test-Path -LiteralPath $k3dDir)) {
  New-Item -ItemType Directory -Path $k3dDir | Out-Null
}

$registriesYaml = @"
mirrors:
  "$HarborEndpoint":
    endpoint:
      - "http://$HarborEndpoint"
configs:
  "$HarborEndpoint":
    tls:
      insecure_skip_verify: true
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($registriesPath, $registriesYaml, $utf8NoBom)

$existingCluster = k3d cluster list --no-headers 2>$null | Where-Object { $_ -match "^$([regex]::Escape($ClusterName))\s" }
if ($existingCluster) {
  Write-Host "k3d cluster '$ClusterName' already exists."
  kubectl config use-context "k3d-$ClusterName"
  kubectl get nodes
  exit 0
}

Write-Host "Creating k3d cluster '$ClusterName' with registry config '$registriesPath'..."
k3d cluster create $ClusterName `
  --servers 1 `
  --agents 0 `
  --registry-config $registriesPath `
  --k3s-arg "--disable=traefik@server:0" `
  --wait

kubectl config use-context "k3d-$ClusterName"
kubectl get nodes

Write-Host ""
Write-Host "Manual Harbor pull test after image exists:"
Write-Host "docker exec k3d-$ClusterName-server-0 crictl pull $HarborEndpoint/devsecops-lab/wordpress@sha256:<digest>"
