# Dependency-Track Lab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Dependency-Track with PostgreSQL to the local CI/CD lab and wire the `ci-cd` WordPress GitLab CI pipeline to upload SBOMs and fail on `HIGH` or `CRITICAL` findings.

**Architecture:** Run Dependency-Track API, frontend, and PostgreSQL in a separate Docker Compose file that joins the shared `vinfast-cicd-lab` network. Add a GitLab CI job under `ci-cd/.gitlab-ci.yml` that generates a CycloneDX SBOM with Syft, uploads it to Dependency-Track, polls processing completion, then queries project metrics for the fail gate. Add docs under `docs/dependency-track/README.md`.

**Tech Stack:** Docker Compose, Dependency-Track API/frontend containers, PostgreSQL 16 Alpine, GitLab CI, Alpine Linux CI image, Syft, curl, jq, CycloneDX JSON.

## Global Constraints

- Host has about 8GB RAM and 4 CPU.
- Build one component at a time.
- GitLab already runs at `http://localhost:8929`.
- Dependency-Track must run separately from GitLab so services can be started/stopped independently.
- Documentation must be written under `docs/`.
- SBOM target is existing `ci-cd` WordPress folder.
- Add severity fail gate: pipeline fails when Dependency-Track reports any `HIGH` or `CRITICAL` vulnerable component for project `vinfast-wordpress` version `lab`.
- Dependency-Track UI URL: `http://localhost:8081`.
- Dependency-Track API URL from host: `http://localhost:8080`.
- Dependency-Track API URL from GitLab CI on Docker Desktop: `http://host.docker.internal:8080`.
- Default project name: `vinfast-wordpress`.
- Default project version: `lab`.
- Workspace is not a git repository; skip commits and record that commits were skipped.

---

## File Structure

- `.env.dependency-track` — image tags, host ports, database credentials, and local resource values.
- `docker-compose.dependency-track.yml` — Dependency-Track API, frontend, PostgreSQL, shared network, persistent volume mappings.
- `ci-cd/.gitlab-ci.yml` — GitLab CI SBOM generation, upload, poll, metrics query, and `HIGH`/`CRITICAL` fail gate.
- `docs/dependency-track/README.md` — install, start, login, API key, GitLab variables, CI use, fail gate behavior, verification, stop/delete data.

---

### Task 1: Add Dependency-Track Docker Compose Stack

**Files:**
- Create: `.env.dependency-track`
- Create: `docker-compose.dependency-track.yml`

**Interfaces:**
- Consumes: Docker Compose plugin and Docker network name `vinfast-cicd-lab`.
- Produces: Compose stack with services `dtrack-postgres`, `dtrack-apiserver`, and `dtrack-frontend`.

- [ ] **Step 1: Create `.env.dependency-track`**

Create `.env.dependency-track` with exact content:

```dotenv
DTRACK_API_IMAGE=dependencytrack/apiserver:latest
DTRACK_FRONTEND_IMAGE=dependencytrack/frontend:latest
DTRACK_POSTGRES_IMAGE=postgres:16-alpine
DTRACK_API_PORT=8080
DTRACK_FRONTEND_PORT=8081
DTRACK_POSTGRES_USER=dtrack
DTRACK_POSTGRES_PASSWORD=dtrack_lab_password
DTRACK_POSTGRES_DB=dtrack
DTRACK_POSTGRES_DIR=./dependency-track/postgres
DTRACK_API_DATA_DIR=./dependency-track/apiserver
DTRACK_ALPINE_SECRET_KEY=<64 hex chars>
DTRACK_JAVA_OPTIONS=-Xmx2048m
```

- [ ] **Step 2: Create `docker-compose.dependency-track.yml`**

Create `docker-compose.dependency-track.yml` with exact content:

```yaml
services:
  dtrack-postgres:
    image: ${DTRACK_POSTGRES_IMAGE}
    container_name: vinfast-dtrack-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${DTRACK_POSTGRES_USER}
      POSTGRES_PASSWORD: ${DTRACK_POSTGRES_PASSWORD}
      POSTGRES_DB: ${DTRACK_POSTGRES_DB}
    volumes:
      - "${DTRACK_POSTGRES_DIR}:/var/lib/postgresql/data"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DTRACK_POSTGRES_USER} -d ${DTRACK_POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 10
    networks:
      - cicd-lab

  dtrack-apiserver:
    image: ${DTRACK_API_IMAGE}
    container_name: vinfast-dtrack-apiserver
    restart: unless-stopped
    depends_on:
      dtrack-postgres:
        condition: service_healthy
    environment:
      JAVA_OPTIONS: ${DTRACK_JAVA_OPTIONS}
      ALPINE_SECRET_KEY: ${DTRACK_ALPINE_SECRET_KEY}
      ALPINE_DATABASE_MODE: external
      ALPINE_DATABASE_DRIVER: org.postgresql.Driver
      ALPINE_DATABASE_URL: jdbc:postgresql://dtrack-postgres:5432/${DTRACK_POSTGRES_DB}
      ALPINE_DATABASE_USERNAME: ${DTRACK_POSTGRES_USER}
      ALPINE_DATABASE_PASSWORD: ${DTRACK_POSTGRES_PASSWORD}
      ALPINE_CORS_ENABLED: "true"
      ALPINE_CORS_ALLOW_ORIGIN: "http://localhost:${DTRACK_FRONTEND_PORT}"
      ALPINE_CORS_ALLOW_METHODS: "GET, POST, PUT, DELETE, OPTIONS"
      ALPINE_CORS_ALLOW_HEADERS: "Origin, Content-Type, Authorization, X-Requested-With, Content-Length, Accept, X-Api-Key"
    ports:
      - "${DTRACK_API_PORT}:8080"
    volumes:
      - "${DTRACK_API_DATA_DIR}:/data"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:8080/api/version >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 20
      start_period: 120s
    networks:
      - cicd-lab

  dtrack-frontend:
    image: ${DTRACK_FRONTEND_IMAGE}
    container_name: vinfast-dtrack-frontend
    restart: unless-stopped
    depends_on:
      dtrack-apiserver:
        condition: service_healthy
    environment:
      API_BASE_URL: http://localhost:${DTRACK_API_PORT}
    ports:
      - "${DTRACK_FRONTEND_PORT}:8080"
    networks:
      - cicd-lab

networks:
  cicd-lab:
    name: vinfast-cicd-lab
```

- [ ] **Step 3: Validate Compose config**

Run:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml config
```

Expected: command exits 0 and rendered config includes services `dtrack-postgres`, `dtrack-apiserver`, and `dtrack-frontend`.

- [ ] **Step 4: Commit if repository exists**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If output is `true`, run:

```powershell
git add .env.dependency-track docker-compose.dependency-track.yml
git commit -m "feat: add Dependency-Track compose stack"
```

If command fails because workspace is not a git repo, record `Skipped commit: workspace is not a git repository` in final task notes.

---

### Task 2: Add GitLab CI SBOM Upload and Fail Gate

**Files:**
- Create: `ci-cd/.gitlab-ci.yml`

**Interfaces:**
- Consumes: Dependency-Track API URL and API key from GitLab CI variables.
- Produces: `dependency-track-sbom` job that creates `gl-sbom.cdx.json`, uploads it, polls BOM processing, and fails on `HIGH` or `CRITICAL` metrics.

- [ ] **Step 1: Create `ci-cd/.gitlab-ci.yml`**

Create `ci-cd/.gitlab-ci.yml` with exact content:

```yaml
stages:
  - security

variables:
  DTRACK_PROJECT_NAME: "vinfast-wordpress"
  DTRACK_PROJECT_VERSION: "lab"
  DTRACK_FAIL_ON_SEVERITY: "HIGH"
  DTRACK_BOM_POLL_SECONDS: "300"
  DTRACK_BOM_POLL_INTERVAL_SECONDS: "10"

dependency-track-sbom:
  stage: security
  image: alpine:3.20
  before_script:
    - apk add --no-cache bash curl jq
    - curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
    - syft version
  script:
    - |
      set -euo pipefail

      : "${DTRACK_API_URL:?Set DTRACK_API_URL in GitLab CI variables, for Docker Desktop use http://host.docker.internal:8080}"
      : "${DTRACK_API_KEY:?Set DTRACK_API_KEY in GitLab CI variables}"
      : "${DTRACK_PROJECT_NAME:?Set DTRACK_PROJECT_NAME}"
      : "${DTRACK_PROJECT_VERSION:?Set DTRACK_PROJECT_VERSION}"

      echo "Generating CycloneDX SBOM for ${DTRACK_PROJECT_NAME}:${DTRACK_PROJECT_VERSION}"
      syft dir:. -o cyclonedx-json=gl-sbom.cdx.json
      test -s gl-sbom.cdx.json

      echo "Uploading SBOM to Dependency-Track at ${DTRACK_API_URL}"
      upload_response="$(curl -sS --fail -X POST "${DTRACK_API_URL}/api/v1/bom" \
        -H "X-Api-Key: ${DTRACK_API_KEY}" \
        -F "autoCreate=true" \
        -F "projectName=${DTRACK_PROJECT_NAME}" \
        -F "projectVersion=${DTRACK_PROJECT_VERSION}" \
        -F "bom=@gl-sbom.cdx.json")"

      echo "${upload_response}" | jq .
      bom_token="$(echo "${upload_response}" | jq -r '.token // empty')"
      if [ -z "${bom_token}" ]; then
        echo "Dependency-Track upload did not return BOM token"
        exit 1
      fi

      deadline=$(( $(date +%s) + ${DTRACK_BOM_POLL_SECONDS} ))
      processing="true"
      while [ "$(date +%s)" -lt "${deadline}" ]; do
        token_response="$(curl -sS --fail "${DTRACK_API_URL}/api/v1/bom/token/${bom_token}" \
          -H "X-Api-Key: ${DTRACK_API_KEY}")"
        processing="$(echo "${token_response}" | jq -r '.processing // false')"
        echo "BOM processing: ${processing}"
        if [ "${processing}" = "false" ]; then
          break
        fi
        sleep "${DTRACK_BOM_POLL_INTERVAL_SECONDS}"
      done

      if [ "${processing}" != "false" ]; then
        echo "Timed out waiting for Dependency-Track BOM processing"
        exit 1
      fi

      project_json="$(curl -sS --fail -G "${DTRACK_API_URL}/api/v1/project/lookup" \
        -H "X-Api-Key: ${DTRACK_API_KEY}" \
        --data-urlencode "name=${DTRACK_PROJECT_NAME}" \
        --data-urlencode "version=${DTRACK_PROJECT_VERSION}")"
      project_uuid="$(echo "${project_json}" | jq -r '.uuid // empty')"
      if [ -z "${project_uuid}" ]; then
        echo "Could not resolve Dependency-Track project UUID"
        echo "${project_json}" | jq .
        exit 1
      fi

      metrics_json="$(curl -sS --fail "${DTRACK_API_URL}/api/v1/metrics/project/${project_uuid}/current" \
        -H "X-Api-Key: ${DTRACK_API_KEY}")"
      echo "${metrics_json}" | jq .

      critical="$(echo "${metrics_json}" | jq -r '.critical // 0')"
      high="$(echo "${metrics_json}" | jq -r '.high // 0')"
      echo "Dependency-Track gate metrics: critical=${critical}, high=${high}, threshold=${DTRACK_FAIL_ON_SEVERITY}"

      if [ "${critical}" -gt 0 ]; then
        echo "Fail gate triggered: CRITICAL vulnerable components found"
        exit 1
      fi

      if [ "${DTRACK_FAIL_ON_SEVERITY}" = "HIGH" ] && [ "${high}" -gt 0 ]; then
        echo "Fail gate triggered: HIGH vulnerable components found"
        exit 1
      fi

      echo "Dependency-Track fail gate passed"
  artifacts:
    when: always
    expire_in: 7 days
    paths:
      - gl-sbom.cdx.json
```

- [ ] **Step 2: Validate CI file exists**

Run:

```powershell
Test-Path "ci-cd/.gitlab-ci.yml"
```

Expected output:

```text
True
```

- [ ] **Step 3: Check required variable names are present**

Run:

```powershell
Select-String -Path "ci-cd/.gitlab-ci.yml" -Pattern "DTRACK_API_URL|DTRACK_API_KEY|DTRACK_PROJECT_NAME|DTRACK_PROJECT_VERSION|DTRACK_FAIL_ON_SEVERITY"
```

Expected: output contains all five variable names.

- [ ] **Step 4: Commit if repository exists**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If output is `true`, run:

```powershell
git add ci-cd/.gitlab-ci.yml
git commit -m "feat: add Dependency-Track SBOM gate to CI"
```

If command fails because workspace is not a git repo, record `Skipped commit: workspace is not a git repository` in final task notes.

---

### Task 3: Add Dependency-Track Documentation

**Files:**
- Create: `docs/dependency-track/README.md`

**Interfaces:**
- Consumes: Compose stack from Task 1 and CI job from Task 2.
- Produces: User documentation for install, use, GitLab CI variables, fail gate, verification, stop, and data cleanup.

- [ ] **Step 1: Create `docs/dependency-track/README.md`**

Create `docs/dependency-track/README.md` with exact content:

```markdown
# Dependency-Track Lab

Dependency-Track adds SBOM ingestion, component inventory, vulnerability analysis, and CI fail gates to this local CI/CD security lab.

This lab uses:

- Dependency-Track API: `http://localhost:8080`
- Dependency-Track UI: `http://localhost:8081`
- PostgreSQL: container-only, persistent data under `dependency-track/postgres`
- GitLab CI target: `ci-cd` WordPress folder
- Default Dependency-Track project: `vinfast-wordpress`
- Default Dependency-Track version: `lab`

## Requirements

- Docker Desktop or Docker Engine with Docker Compose plugin.
- About 8GB RAM and 4 CPU.
- GitLab already running at `http://localhost:8929`.
- Ports available on host:
  - Dependency-Track API: `8080`
  - Dependency-Track UI: `8081`

## Start Dependency-Track

From repository root:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml up -d
```

Check status:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml ps
```

Follow API logs:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml logs -f dtrack-apiserver
```

First boot can take several minutes. Vulnerability intelligence sync can take longer after first login.

## Login

Open UI:

```text
http://localhost:8081
```

Default credentials:

```text
Username: admin
Password: admin
```

Change admin password immediately after first login.

## Create API Key

In Dependency-Track UI:

1. Open **Administration > Access Management > Teams**.
2. Select team used for automation, or create a CI team.
3. Add permissions needed for BOM upload and project access.
4. Generate API key.
5. Copy API key.

Store API key only in GitLab CI/CD variables. Do not commit API keys into repo files.

## GitLab CI Variables

In GitLab project for `ci-cd`, open **Settings > CI/CD > Variables** and add:

| Variable | Value |
| --- | --- |
| `DTRACK_API_URL` | `http://host.docker.internal:8080` |
| `DTRACK_API_KEY` | API key from Dependency-Track |
| `DTRACK_PROJECT_NAME` | `vinfast-wordpress` |
| `DTRACK_PROJECT_VERSION` | `lab` |
| `DTRACK_FAIL_ON_SEVERITY` | `HIGH` |

Use `http://host.docker.internal:8080` on Docker Desktop so GitLab Runner job containers can reach the host-published API port.

If runner job containers are attached to Docker network `vinfast-cicd-lab`, `DTRACK_API_URL` may be set to:

```text
http://dtrack-apiserver:8080
```

## CI Behavior

File `ci-cd/.gitlab-ci.yml` runs job `dependency-track-sbom`.

Job behavior:

1. Installs Syft in an Alpine CI container.
2. Generates CycloneDX JSON SBOM:

   ```text
   gl-sbom.cdx.json
   ```

3. Uploads SBOM to Dependency-Track endpoint:

   ```text
   POST /api/v1/bom
   ```

4. Uses `autoCreate=true` so project `vinfast-wordpress` version `lab` is created if missing.
5. Polls BOM processing token until processing finishes or timeout occurs.
6. Looks up project UUID.
7. Queries current project metrics.
8. Fails pipeline if `critical > 0`.
9. Fails pipeline if `DTRACK_FAIL_ON_SEVERITY=HIGH` and `high > 0`.
10. Saves `gl-sbom.cdx.json` as pipeline artifact for 7 days.

## Fail Gate

Default gate threshold is `HIGH`.

Pipeline fails when Dependency-Track reports any:

- `CRITICAL` vulnerable component
- `HIGH` vulnerable component

Pipeline passes only when:

- SBOM generation succeeds
- SBOM upload succeeds
- BOM processing finishes before timeout
- project metrics are readable
- no `HIGH` or `CRITICAL` vulnerable components are reported

To fail only on `CRITICAL`, set GitLab CI variable:

```text
DTRACK_FAIL_ON_SEVERITY=CRITICAL
```

Use this only when deliberately lowering enforcement for lab troubleshooting.

## Verify Locally

Validate Compose config:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml config
```

Check API:

```powershell
Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8080/api/version"
```

Check UI:

```powershell
Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8081"
```

Expected:

- API request returns HTTP 200.
- UI request returns HTTP 200.
- Browser can open `http://localhost:8081`.

## Verify from GitLab CI

1. Push or copy `ci-cd/.gitlab-ci.yml` into GitLab project for `ci-cd`.
2. Configure GitLab CI variables listed above.
3. Run pipeline.
4. Confirm job creates artifact `gl-sbom.cdx.json`.
5. Open Dependency-Track UI.
6. Open project `vinfast-wordpress` version `lab`.
7. Confirm components appear.
8. Confirm pipeline gate result matches Dependency-Track `HIGH` and `CRITICAL` metrics.

## Stop Dependency-Track

Stop containers but keep data:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml down
```

Delete all Dependency-Track data:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml down
Remove-Item -Recurse -Force .\dependency-track
```

## Resource Notes

This host has about 8GB RAM. Keep Dependency-Track separate from GitLab so it can be stopped when not scanning.

If memory pressure appears:

1. Stop unused services.
2. Start only GitLab and Dependency-Track for SBOM testing.
3. Avoid running Harbor, ArgoCD, DefectDojo, and Dependency-Track all at once until host resources are increased.

## Troubleshooting

### UI cannot reach API

Check API is reachable from host:

```powershell
Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8080/api/version"
```

If API is not ready, follow logs:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml logs -f dtrack-apiserver
```

### GitLab CI cannot reach Dependency-Track

Use this GitLab CI variable on Docker Desktop:

```text
DTRACK_API_URL=http://host.docker.internal:8080
```

If using shared Docker network access, attach runner job containers to `vinfast-cicd-lab` and use:

```text
DTRACK_API_URL=http://dtrack-apiserver:8080
```

### Pipeline fails on HIGH or CRITICAL findings

Open Dependency-Track UI:

1. Open project `vinfast-wordpress`.
2. Open version `lab`.
3. Review vulnerabilities.
4. Fix vulnerable components or suppress findings only if verified false positive.

### BOM processing timeout

Dependency-Track may still be processing or syncing vulnerability data. Re-run pipeline after API is stable. Timeout fails closed so missing scan data is not treated as pass.
```

- [ ] **Step 2: Validate docs file exists**

Run:

```powershell
Test-Path "docs/dependency-track/README.md"
```

Expected output:

```text
True
```

- [ ] **Step 3: Verify docs mention fail gate**

Run:

```powershell
Select-String -Path "docs/dependency-track/README.md" -Pattern "Fail Gate|HIGH|CRITICAL|DTRACK_FAIL_ON_SEVERITY"
```

Expected: output contains all four patterns.

- [ ] **Step 4: Commit if repository exists**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If output is `true`, run:

```powershell
git add docs/dependency-track/README.md
git commit -m "docs: add Dependency-Track lab guide"
```

If command fails because workspace is not a git repo, record `Skipped commit: workspace is not a git repository` in final task notes.

---

### Task 4: Start Dependency-Track and Verify Endpoints

**Files:**
- Modify: none

**Interfaces:**
- Consumes: Compose stack from Task 1.
- Produces: Running Dependency-Track API at `http://localhost:8080` and UI at `http://localhost:8081`.

- [ ] **Step 1: Start Dependency-Track stack**

Run:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml up -d
```

Expected: command exits 0 and starts containers `vinfast-dtrack-postgres`, `vinfast-dtrack-apiserver`, and `vinfast-dtrack-frontend`.

- [ ] **Step 2: Check Compose status**

Run:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml ps
```

Expected: all three services are `running` or `Up`.

- [ ] **Step 3: Wait for API**

Run this until it returns HTTP 200 or timeout after 10 minutes:

```powershell
$deadline = (Get-Date).AddMinutes(10)
$last = $null
while ((Get-Date) -lt $deadline) {
  try {
    $status = (Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8080/api/version" -TimeoutSec 10).StatusCode
    if ($status -eq 200) { "API status: $status"; break }
    $last = "API status: $status"
  } catch {
    $last = $_.Exception.Message
  }
  Start-Sleep -Seconds 15
}
if ($last -and $last -notmatch "API status: 200") { "Last API result: $last" }
```

Expected final output includes:

```text
API status: 200
```

- [ ] **Step 4: Wait for UI**

Run this until it returns HTTP 200 or timeout after 5 minutes:

```powershell
$deadline = (Get-Date).AddMinutes(5)
$last = $null
while ((Get-Date) -lt $deadline) {
  try {
    $status = (Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8081" -TimeoutSec 10).StatusCode
    if ($status -eq 200) { "UI status: $status"; break }
    $last = "UI status: $status"
  } catch {
    $last = $_.Exception.Message
  }
  Start-Sleep -Seconds 10
}
if ($last -and $last -notmatch "UI status: 200") { "Last UI result: $last" }
```

Expected final output includes:

```text
UI status: 200
```

- [ ] **Step 5: Record verification result**

Record these facts in final task notes:

```text
Dependency-Track API URL: http://localhost:8080
Dependency-Track UI URL: http://localhost:8081
Dependency-Track containers: vinfast-dtrack-postgres, vinfast-dtrack-apiserver, vinfast-dtrack-frontend
API status: 200
UI status: 200
```

---

## Self-Review

Spec coverage:

- Docker Compose Dependency-Track API/frontend/PostgreSQL: Task 1.
- Separate compose file and shared network: Task 1.
- Docs under `docs/`: Task 3.
- SBOM target `ci-cd` WordPress folder: Task 2.
- GitLab CI SBOM generation with Syft: Task 2.
- SBOM upload to `/api/v1/bom` with `autoCreate=true`: Task 2.
- `vinfast-wordpress` version `lab`: Tasks 2 and 3.
- Poll BOM processing and query metrics: Task 2.
- Fail on `HIGH` or `CRITICAL`: Tasks 2 and 3.
- UI/API reachable verification: Task 4.
- 8GB RAM notes: Task 3.

Placeholder scan:

- No `TBD`, `TODO`, or unspecified implementation steps.
- `DTRACK_API_KEY` is intentionally a runtime GitLab CI secret, not committed.

Type/interface consistency:

- Service names match compose/docs: `dtrack-postgres`, `dtrack-apiserver`, `dtrack-frontend`.
- Container names match verification notes.
- GitLab CI variable names match docs and spec.
- Project name/version match spec exactly.
