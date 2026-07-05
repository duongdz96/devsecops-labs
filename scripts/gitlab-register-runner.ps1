param(
  [Parameter(Mandatory = $true)]
  [string]$Token,

  [string]$RunnerName = "vinfast-dind-runner"
)

$ErrorActionPreference = "Stop"

$composeArgs = @(
  "compose",
  "--env-file", ".env.gitlab",
  "-f", "docker-compose.gitlab.yml"
)

Write-Host "Registering GitLab Runner '$RunnerName' for Docker-in-Docker jobs..."

docker @composeArgs exec gitlab-runner gitlab-runner register `
  --non-interactive `
  --url "http://gitlab:8929" `
  --token "$Token" `
  --executor "docker" `
  --docker-image "docker:24" `
  --docker-privileged `
  --docker-volumes "/certs/client" `
  --docker-volumes "/cache" `
  --description "$RunnerName"

Write-Host ""
Write-Host "Runner registered. Current runner list:"
docker @composeArgs exec gitlab-runner gitlab-runner list
