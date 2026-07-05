$ErrorActionPreference = "Stop"

$composeArgs = @(
  "compose",
  "--env-file", ".env.gitlab",
  "-f", "docker-compose.gitlab.yml"
)

Write-Host "Reading initial root password from vinfast-gitlab..."
docker @composeArgs exec gitlab bash -lc "test -f /etc/gitlab/initial_root_password && sed -n 's/^Password: //p' /etc/gitlab/initial_root_password"

Write-Host ""
Write-Host "Login URL: http://localhost:8929"
Write-Host "Username: root"
Write-Host "Note: GitLab removes initial_root_password after first reconfigure/24 hours. If empty, reset root password manually in GitLab container."
