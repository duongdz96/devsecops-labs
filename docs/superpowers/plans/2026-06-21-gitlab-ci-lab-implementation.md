# GitLab CI Lab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build local GitLab CE plus GitLab Runner lab that can run GitLab CI jobs with Docker-in-Docker image builds.

**Architecture:** Use Docker Compose to run GitLab CE Omnibus and GitLab Runner as separate services on one Docker network. Persist GitLab and runner state in local folders. Register runner after GitLab boots, using Docker executor with privileged mode for Docker-in-Docker.

**Tech Stack:** Docker Compose, GitLab CE Omnibus container, GitLab Runner container, PowerShell helper scripts, GitLab CI YAML, Docker-in-Docker.

## Global Constraints

- Host has about 8GB RAM and 4 CPU.
- Build one component at a time.
- GitLab URL: `http://localhost:8929`.
- Git over SSH exposed on host port `2224`.
- Runner must support Docker image builds with Docker-in-Docker.
- GitLab image: `gitlab/gitlab-ce`.
- GitLab Runner image: `gitlab/gitlab-runner`.
- GitLab ports: `8929:8929`, `2224:22`.
- GitLab persistent volumes: `gitlab/config`, `gitlab/logs`, `gitlab/data`.
- GitLab Runner persistent volume: `gitlab-runner/config`.
- Runner executor: `docker`.
- Runner default image: `docker:24`.
- Runner privileged mode: `true`.
- Runner volumes: `/certs/client`, `/cache`.
- CI Docker variables: `DOCKER_HOST=tcp://docker:2375`, `DOCKER_TLS_CERTDIR=""`.
- CI Docker service: `docker:24-dind`.
- Out of scope: Harbor, ArgoCD, Kubernetes, Dependency-Track, DefectDojo, production TLS certificates, external domain/DNS.

---

## File Structure

- `docker-compose.gitlab.yml` — defines `gitlab` and `gitlab-runner` services, volumes, ports, and GitLab Omnibus settings.
- `.env.gitlab` — centralizes image tags, ports, and host paths for Compose.
- `scripts/gitlab-register-runner.ps1` — registers runner with token supplied by user after GitLab boot.
- `scripts/gitlab-show-root-password.ps1` — prints initial root password from GitLab container.
- `examples/gitlab-ci-dind/.gitlab-ci.yml` — demo pipeline proving Docker-in-Docker works.
- `examples/gitlab-ci-dind/Dockerfile` — tiny image build target for CI.
- `README.md` — operational runbook: start, wait, login, register runner, create demo project, run pipeline, stop.

---

### Task 1: Compose GitLab and Runner Services

**Files:**
- Create: `.env.gitlab`
- Create: `docker-compose.gitlab.yml`

**Interfaces:**
- Consumes: Docker Compose on host.
- Produces: Compose project with service names `gitlab` and `gitlab-runner`; later scripts call `docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml ...`.

- [ ] **Step 1: Create `.env.gitlab`**

Create `.env.gitlab` with exact content:

```dotenv
GITLAB_IMAGE=gitlab/gitlab-ce:latest
GITLAB_RUNNER_IMAGE=gitlab/gitlab-runner:latest
GITLAB_HTTP_PORT=8929
GITLAB_SSH_PORT=2224
GITLAB_HOSTNAME=localhost
GITLAB_CONFIG_DIR=./gitlab/config
GITLAB_LOGS_DIR=./gitlab/logs
GITLAB_DATA_DIR=./gitlab/data
GITLAB_RUNNER_CONFIG_DIR=./gitlab-runner/config
```

- [ ] **Step 2: Create `docker-compose.gitlab.yml`**

Create `docker-compose.gitlab.yml` with exact content:

```yaml
services:
  gitlab:
    image: ${GITLAB_IMAGE}
    container_name: vinfast-gitlab
    restart: unless-stopped
    hostname: ${GITLAB_HOSTNAME}
    shm_size: "256m"
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'http://${GITLAB_HOSTNAME}:${GITLAB_HTTP_PORT}'
        gitlab_rails['gitlab_shell_ssh_port'] = ${GITLAB_SSH_PORT}
        puma['worker_processes'] = 2
        sidekiq['max_concurrency'] = 10
        prometheus_monitoring['enable'] = false
    ports:
      - "${GITLAB_HTTP_PORT}:${GITLAB_HTTP_PORT}"
      - "${GITLAB_SSH_PORT}:22"
    volumes:
      - "${GITLAB_CONFIG_DIR}:/etc/gitlab"
      - "${GITLAB_LOGS_DIR}:/var/log/gitlab"
      - "${GITLAB_DATA_DIR}:/var/opt/gitlab"
    networks:
      - cicd-lab

  gitlab-runner:
    image: ${GITLAB_RUNNER_IMAGE}
    container_name: vinfast-gitlab-runner
    restart: unless-stopped
    depends_on:
      - gitlab
    volumes:
      - "${GITLAB_RUNNER_CONFIG_DIR}:/etc/gitlab-runner"
    networks:
      - cicd-lab

networks:
  cicd-lab:
    name: vinfast-cicd-lab
```

- [ ] **Step 3: Validate Compose config**

Run:

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml config
```

Expected: command exits 0 and rendered config includes services `gitlab` and `gitlab-runner`.

- [ ] **Step 4: Commit if repository exists**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If output is `true`, run:

```powershell
git add .env.gitlab docker-compose.gitlab.yml
git commit -m "feat: add GitLab CI lab compose config"
```

If command fails because workspace is not a git repo, record `Skipped commit: workspace is not a git repository` in final task notes.

---

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

---

### Task 3: Add Docker-in-Docker Demo Pipeline

**Files:**
- Create: `examples/gitlab-ci-dind/.gitlab-ci.yml`
- Create: `examples/gitlab-ci-dind/Dockerfile`

**Interfaces:**
- Consumes: Registered runner from Task 2.
- Produces: Demo project content that proves GitLab CI can run Docker-in-Docker image builds.

- [ ] **Step 1: Create `examples/gitlab-ci-dind/Dockerfile`**

Create `examples/gitlab-ci-dind/Dockerfile` with exact content:

```dockerfile
FROM alpine:3.20
RUN adduser -D appuser
USER appuser
CMD ["sh", "-c", "echo GitLab CI DinD lab image works"]
```

- [ ] **Step 2: Create `examples/gitlab-ci-dind/.gitlab-ci.yml`**

Create `examples/gitlab-ci-dind/.gitlab-ci.yml` with exact content:

```yaml
stages:
  - test
  - build

variables:
  DOCKER_HOST: tcp://docker:2375
  DOCKER_TLS_CERTDIR: ""
  DOCKER_DRIVER: overlay2

check-docker-client:
  stage: test
  image: docker:24
  services:
    - name: docker:24-dind
      alias: docker
      command: ["--tls=false"]
  script:
    - docker version
    - docker info

build-demo-image:
  stage: build
  image: docker:24
  services:
    - name: docker:24-dind
      alias: docker
      command: ["--tls=false"]
  script:
    - docker build -t vinfast/gitlab-ci-dind-demo:${CI_COMMIT_SHORT_SHA} .
    - docker run --rm vinfast/gitlab-ci-dind-demo:${CI_COMMIT_SHORT_SHA}
```

- [ ] **Step 3: Validate demo files exist**

Run:

```powershell
Test-Path "examples/gitlab-ci-dind/.gitlab-ci.yml"
Test-Path "examples/gitlab-ci-dind/Dockerfile"
```

Expected output:

```text
True
True
```

- [ ] **Step 4: Commit if repository exists**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If output is `true`, run:

```powershell
git add examples/gitlab-ci-dind/.gitlab-ci.yml examples/gitlab-ci-dind/Dockerfile
git commit -m "feat: add GitLab CI Docker-in-Docker demo"
```

If command fails because workspace is not a git repo, record `Skipped commit: workspace is not a git repository` in final task notes.

---

### Task 4: Add Runbook Documentation

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: Compose config from Task 1, helper scripts from Task 2, demo pipeline from Task 3.
- Produces: Human runbook for operating and verifying GitLab CI lab.

- [ ] **Step 1: Create `README.md`**

Create `README.md` with exact content:

```markdown
# Vinfast CI/CD Security Lab

Local lab for building a CI/CD security workflow. Phase 1 runs GitLab CE and GitLab Runner with Docker-in-Docker support.

## Requirements

- Docker Desktop or Docker Engine with Docker Compose plugin.
- About 8GB RAM and 4 CPU.
- Ports available on host:
  - GitLab HTTP: `8929`
  - GitLab SSH: `2224`

## Phase 1 Services

- GitLab CE: `http://localhost:8929`
- GitLab SSH: `ssh://git@localhost:2224/...`
- GitLab Runner: Docker executor, privileged mode enabled, default image `docker:24`

## Start GitLab

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml up -d gitlab
```

GitLab first boot can take 5-15 minutes on an 8GB RAM host.

Check status:

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml ps
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml logs -f gitlab
```

Open:

```text
http://localhost:8929
```

## Get Initial Root Password

```powershell
.\scripts\gitlab-show-root-password.ps1
```

Login:

- Username: `root`
- Password: output from script

If password is empty, GitLab already removed the initial password. Reset it manually inside the container.

## Start Runner Container

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml up -d gitlab-runner
```

## Create Runner Token

In GitLab UI:

1. Open `http://localhost:8929`.
2. Login as `root`.
3. Go to **Admin Area > CI/CD > Runners**.
4. Create a new instance runner.
5. Copy runner authentication token.

## Register Runner

Replace `<TOKEN>` with token from GitLab UI:

```powershell
.\scripts\gitlab-register-runner.ps1 -Token "<TOKEN>"
```

Verify runner appears online in GitLab UI.

## Test Docker-in-Docker CI

1. Create new blank project in GitLab.
2. Copy files from `examples/gitlab-ci-dind/` into project root:
   - `.gitlab-ci.yml`
   - `Dockerfile`
3. Commit files.
4. Open **Build > Pipelines**.
5. Confirm pipeline passes:
   - `check-docker-client`
   - `build-demo-image`

Successful build proves GitLab Runner can run Docker-in-Docker jobs.

## Stop Lab

Stop containers but keep data:

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml down
```

Delete all GitLab and runner data:

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml down
Remove-Item -Recurse -Force .\gitlab, .\gitlab-runner
```

## Resource Notes

This host has about 8GB RAM. Run GitLab phase first. Do not run Harbor, ArgoCD, Dependency-Track, and DefectDojo at the same time until GitLab is stable.

## Next Phases

- Harbor registry for CI image push.
- Dependency-Track for SBOM and component risk.
- DefectDojo for vulnerability aggregation.
- ArgoCD for GitOps deployment.
```

- [ ] **Step 2: Validate README references existing files**

Run:

```powershell
Test-Path ".env.gitlab"
Test-Path "docker-compose.gitlab.yml"
Test-Path "scripts/gitlab-show-root-password.ps1"
Test-Path "scripts/gitlab-register-runner.ps1"
Test-Path "examples/gitlab-ci-dind/.gitlab-ci.yml"
Test-Path "examples/gitlab-ci-dind/Dockerfile"
```

Expected output:

```text
True
True
True
True
True
True
```

- [ ] **Step 3: Commit if repository exists**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If output is `true`, run:

```powershell
git add README.md
git commit -m "docs: add GitLab CI lab runbook"
```

If command fails because workspace is not a git repo, record `Skipped commit: workspace is not a git repository` in final task notes.

---

### Task 5: Start GitLab and Verify Boot

**Files:**
- Modify: none

**Interfaces:**
- Consumes: Compose config and README from previous tasks.
- Produces: Running GitLab service reachable at `http://localhost:8929`.

- [ ] **Step 1: Start GitLab service**

Run:

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml up -d gitlab
```

Expected: command exits 0 and creates/runs container `vinfast-gitlab`.

- [ ] **Step 2: Check Compose service status**

Run:

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml ps
```

Expected: `gitlab` service appears with state `running` or `Up`.

- [ ] **Step 3: Wait for GitLab HTTP endpoint**

Run this until it returns an HTTP status code:

```powershell
try { (Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8929/users/sign_in" -TimeoutSec 10).StatusCode } catch { $_.Exception.Message }
```

Expected final output: `200`.

- [ ] **Step 4: Show root password**

Run:

```powershell
.\scripts\gitlab-show-root-password.ps1
```

Expected: script prints password line plus login URL.

- [ ] **Step 5: Record verification result**

Record these facts in final task notes:

```text
GitLab URL: http://localhost:8929
GitLab SSH port: 2224
GitLab container: vinfast-gitlab
HTTP sign-in status: 200
```

---

### Task 6: Register Runner and Verify Docker-in-Docker Pipeline

**Files:**
- Modify: none

**Interfaces:**
- Consumes: running GitLab from Task 5, runner token from GitLab UI, demo files from Task 3.
- Produces: registered runner and passing demo pipeline.

- [ ] **Step 1: Start runner service**

Run:

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml up -d gitlab-runner
```

Expected: command exits 0 and creates/runs container `vinfast-gitlab-runner`.

- [ ] **Step 2: Register runner with token**

Run with token copied from GitLab UI:

```powershell
.\scripts\gitlab-register-runner.ps1 -Token "<TOKEN_FROM_GITLAB_UI>"
```

Expected: output includes `Runner registered successfully` or runner appears in `gitlab-runner list`.

- [ ] **Step 3: Verify runner config contains privileged Docker executor**

Run:

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml exec gitlab-runner cat /etc/gitlab-runner/config.toml
```

Expected config contains:

```toml
executor = "docker"
privileged = true
image = "docker:24"
```

- [ ] **Step 4: Create demo project manually in GitLab UI**

In browser:

1. Open `http://localhost:8929`.
2. Create blank project named `gitlab-ci-dind-demo`.
3. Add `examples/gitlab-ci-dind/.gitlab-ci.yml` to project root.
4. Add `examples/gitlab-ci-dind/Dockerfile` to project root.
5. Commit files to default branch.

Expected: GitLab creates a pipeline automatically.

- [ ] **Step 5: Verify pipeline passes**

In GitLab UI:

1. Open project `gitlab-ci-dind-demo`.
2. Open **Build > Pipelines**.
3. Wait for latest pipeline.

Expected:

```text
Pipeline status: passed
Jobs passed: check-docker-client, build-demo-image
```

- [ ] **Step 6: Capture final verification notes**

Record:

```text
Runner name: vinfast-dind-runner
Runner executor: docker
Runner privileged: true
Demo pipeline: passed
Docker-in-Docker image build: passed
```

---

## Self-Review

Spec coverage:

- GitLab CE Omnibus container: Task 1.
- GitLab Runner container: Task 1.
- URL `http://localhost:8929`: Tasks 1, 4, 5.
- SSH host port `2224`: Tasks 1, 4, 5.
- Persistent volumes: Task 1.
- Registration after GitLab boot: Tasks 2, 5, 6.
- Docker executor, privileged mode, `docker:24`: Tasks 2, 3, 6.
- Docker-in-Docker variables and service: Task 3.
- 8GB RAM phased strategy: README in Task 4 and no later services in scope.
- Later Harbor/ArgoCD/Dependency-Track/DefectDojo excluded from this phase: Global Constraints and README next phases.

Placeholder scan:

- No `TBD`, `TODO`, or unspecified implementation steps.
- `<TOKEN_FROM_GITLAB_UI>` is an operator-supplied runtime secret, not a placeholder in generated files.

Type/interface consistency:

- Compose command path and env file names match across all tasks.
- Service names `gitlab` and `gitlab-runner` match scripts and README.
- Container names match verification notes.
