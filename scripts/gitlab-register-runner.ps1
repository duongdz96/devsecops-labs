param(
  [Parameter(Mandatory = $true)]
  [string]$Token,

  [string]$RunnerName = "devsecops-dind-runner"
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
  --clone-url "http://gitlab:8929" `
  --token "$Token" `
  --executor "docker" `
  --docker-image "docker:24" `
  --docker-privileged `
  --docker-network-mode "devsecops-labs-cicd" `
  --docker-volumes "/certs/client" `
  --docker-volumes "/cache" `
  --description "$RunnerName"

Write-Host "Runner registered. Verify status in GitLab Settings > CI/CD > Runners."
