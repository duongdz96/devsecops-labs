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
