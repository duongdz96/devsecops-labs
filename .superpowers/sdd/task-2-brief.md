### Task 2: Add GitLab Helper Scripts

**Files:**
- Create: `scripts/gitlab-show-root-password.ps1`
- Create: `scripts/gitlab-register-runner.ps1`

**Interfaces:**
- Consumes: Compose files from Task 1 and a runner token copied from GitLab UI.
- Produces: Repeatable commands for retrieving root password and registering Docker executor runner.

- [ ] **Step 1: Create `scripts/gitlab-show-root-password.ps1`**

Create `scripts/gitlab-show-root-password.ps1` with exact content:

```powershell
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
```

- [ ] **Step 2: Create `scripts/gitlab-register-runner.ps1`**

Create `scripts/gitlab-register-runner.ps1` with exact content:

```powershell
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
```

- [ ] **Step 3: Validate scripts parse**

Run:

```powershell
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content "scripts/gitlab-show-root-password.ps1" -Raw), [ref]$null)
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content "scripts/gitlab-register-runner.ps1" -Raw), [ref]$null)
```

Expected: command exits 0.

- [ ] **Step 4: Commit if repository exists**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If output is `true`, run:

```powershell
git add scripts/gitlab-show-root-password.ps1 scripts/gitlab-register-runner.ps1
git commit -m "feat: add GitLab runner helper scripts"
```

If command fails because workspace is not a git repo, record `Skipped commit: workspace is not a git repository` in final task notes.


