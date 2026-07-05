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


