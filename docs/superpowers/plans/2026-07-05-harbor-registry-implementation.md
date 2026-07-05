# Harbor Registry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Harbor registry config, documentation, and GitLab CI image push job for the WordPress lab.

**Architecture:** Harbor is installed by official installer under `infra/harbor`; only editable config is committed. GitLab CI builds `ci-cd/Dockerfile` with Docker-in-Docker and pushes commit-SHA plus `latest` tags to Harbor.

**Tech Stack:** Harbor v2.x installer, Docker Compose, GitLab CI, Docker-in-Docker, PowerShell docs.

## Global Constraints

- Host has about 8GB RAM and 4 CPU.
- Build one component at a time.
- GitLab already runs at `http://localhost:8929`.
- Harbor UI/registry endpoint is `http://localhost:8083`.
- Harbor project is `vinfast`.
- Harbor image name is `wordpress`.
- Harbor uses HTTP/insecure registry for local lab convenience.
- Do not require all lab stacks to run simultaneously.
- Preserve existing Dependency-Track and DefectDojo CI jobs.
- ArgoCD and k3d are out of scope for this Harbor task.

---

## File Structure

- `infra/harbor/harbor.yml`: editable Harbor installer config, HTTP on port 8083, local data volume.
- `docs/harbor/README.md`: end-to-end setup, CI variables, verification, cleanup, troubleshooting.
- `ci-cd/.gitlab-ci.yml`: add build stage and `harbor-build-push` job before security jobs.
- `.gitignore`: ignore Harbor runtime data and generated installer output.

---

### Task 1: Harbor installer config

**Files:**
- Create: `infra/harbor/harbor.yml`
- Modify: `.gitignore`

**Interfaces:**
- Produces: Harbor config consumed by official `prepare`/`install.sh` scripts.
- Produces: ignored runtime paths `infra/harbor/data/`, `infra/harbor/common/`, `infra/harbor/docker-compose.yml`.

- [ ] **Step 1: Create Harbor config**

Write `infra/harbor/harbor.yml` with HTTP port 8083, hostname localhost, disabled HTTPS, local data volume, and stable lab defaults.

- [ ] **Step 2: Ignore generated/runtime Harbor files**

Add these entries to `.gitignore`:

```gitignore
infra/harbor/common/
infra/harbor/data/
infra/harbor/docker-compose.yml
infra/harbor/harbor.v*.tar.gz
infra/harbor/LICENSE
infra/harbor/install.sh
infra/harbor/prepare
```

- [ ] **Step 3: Validate YAML parse**

Run:

```powershell
python -c "import pathlib, yaml; yaml.safe_load(pathlib.Path('infra/harbor/harbor.yml').read_text())"
```

Expected: exit code 0 if PyYAML exists. If PyYAML is absent, review indentation manually and continue.

- [ ] **Step 4: Commit**

```powershell
git add .gitignore infra/harbor/harbor.yml docs/superpowers/plans/2026-07-05-harbor-registry-implementation.md
git commit -m "Add Harbor registry installer config"
```

---

### Task 2: GitLab CI Harbor push job

**Files:**
- Modify: `ci-cd/.gitlab-ci.yml`

**Interfaces:**
- Consumes: GitLab CI variables `HARBOR_URL`, `HARBOR_PROJECT`, `HARBOR_IMAGE_NAME`, `HARBOR_ROBOT_USER`, `HARBOR_ROBOT_TOKEN`.
- Produces: image tags `${HARBOR_URL}/${HARBOR_PROJECT}/${HARBOR_IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}` and `latest`.

- [ ] **Step 1: Add build stage before security**

Set stage list:

```yaml
stages:
  - build
  - security
```

- [ ] **Step 2: Add Docker-in-Docker variables**

Add CI defaults:

```yaml
variables:
  DOCKER_HOST: "tcp://docker:2375"
  DOCKER_TLS_CERTDIR: ""
  DOCKER_DRIVER: "overlay2"
  HARBOR_URL: "host.docker.internal:8083"
  HARBOR_PROJECT: "vinfast"
  HARBOR_IMAGE_NAME: "wordpress"
```

Keep existing Dependency-Track and DefectDojo variables.

- [ ] **Step 3: Add `harbor-build-push` job**

Use `docker:24` with `docker:24-dind`, configure insecure registry `host.docker.internal:8083`, login with robot token, build from repo root, push SHA and `latest`.

- [ ] **Step 4: Validate CI file**

Run GitLab CI lint in GitLab UI or use project API after project exists. Expected: config valid.

- [ ] **Step 5: Commit**

```powershell
git add ci-cd/.gitlab-ci.yml
git commit -m "Add Harbor image push CI job"
```

---

### Task 3: Harbor documentation

**Files:**
- Create: `docs/harbor/README.md`

**Interfaces:**
- Consumes: Harbor config from Task 1.
- Consumes: CI behavior from Task 2.
- Produces: operator guide for Harbor setup, robot account, CI variables, verification, stop/delete, troubleshooting.

- [ ] **Step 1: Document requirements and resource strategy**

Include Docker, GitLab, Docker Desktop insecure registry, 8GB RAM warning, and which stacks can be stopped.

- [ ] **Step 2: Document official installer workflow**

Use exact commands to download Harbor offline installer, copy repo `harbor.yml`, run `prepare`, run `install.sh`, and start with generated Docker Compose.

- [ ] **Step 3: Document Harbor UI setup**

Include URL `http://localhost:8083`, admin login, project `vinfast`, robot account push/pull permissions, token handling.

- [ ] **Step 4: Document GitLab CI variables and pipeline**

List exact variables and expected build/push behavior.

- [ ] **Step 5: Document verification and troubleshooting**

Include Docker login/pull, Harbor UI tag check, insecure registry errors, robot login failure, DinD reachability, push denied, port conflict, low memory.

- [ ] **Step 6: Commit**

```powershell
git add docs/harbor/README.md
git commit -m "Document Harbor registry lab"
```
