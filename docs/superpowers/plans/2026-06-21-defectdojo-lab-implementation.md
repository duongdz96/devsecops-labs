# DefectDojo Lab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add DefectDojo with Docker Compose and wire `ci-cd` GitLab CI to run Trivy + OWASP Dependency-Check, import reports into DefectDojo, and fail on `HIGH` or `CRITICAL` findings.

**Architecture:** Use a self-contained lab Compose file modeled after upstream DefectDojo: nginx, uwsgi, initializer, celery worker/beat, PostgreSQL, and Valkey. Keep Dojo separate from GitLab and Dependency-Track, exposed on host port `8082`. Extend `ci-cd/.gitlab-ci.yml` with two scanner jobs and one import job using DefectDojo `/api/v2/reimport-scan/` with `auto_create_context=true`.

**Tech Stack:** Docker Compose, DefectDojo Django/nginx images, PostgreSQL, Valkey, GitLab CI, Trivy, OWASP Dependency-Check, curl, jq.

## Global Constraints

- Host has about 8GB RAM and 4 CPU.
- Build one component at a time.
- GitLab already runs at `http://localhost:8929`.
- Dependency-Track already runs at `http://localhost:8081` UI and `http://localhost:8080` API.
- DefectDojo must run separately from GitLab and Dependency-Track so services can be started/stopped independently.
- Documentation must be written under `docs/`.
- Security scan target is existing `ci-cd` WordPress folder.
- Use lab-local Docker Compose files instead of cloning the official DefectDojo repository.
- Keep DefectDojo config aligned with upstream Docker Compose patterns.
- Add severity fail gate: pipeline fails when Trivy or Dependency-Check reports any `HIGH` or `CRITICAL` finding.
- DefectDojo UI/API URL from host: `http://localhost:8082`.
- DefectDojo URL from GitLab CI on Docker Desktop: `http://host.docker.internal:8082`.
- DefectDojo product name: `vinfast-wordpress`.
- DefectDojo engagement name: `gitlab-ci`.
- Workspace is not a git repository; skip commits and record that commits were skipped.

---

## File Structure

- `.env.defectdojo` — image tags, ports, database values, stable Django/credential secrets, admin bootstrap identity, app URLs.
- `docker-compose.defectdojo.yml` — DefectDojo nginx/uwsgi/initializer/celery/postgres/valkey services.
- `ci-cd/.gitlab-ci.yml` — existing Dependency-Track SBOM gate plus new Trivy, Dependency-Check, and DefectDojo import/fail-gate jobs.
- `docs/defectdojo/README.md` — install, start, admin password retrieval, API token, CI variables, scanner/import/fail-gate usage, stop/delete data.

---

### Task 1: Add DefectDojo Docker Compose Stack

**Files:**
- Create: `.env.defectdojo`
- Create: `docker-compose.defectdojo.yml`

**Interfaces:**
- Consumes: Docker Compose plugin and Docker network name `vinfast-cicd-lab`.
- Produces: Compose stack with services `dojo-postgres`, `dojo-valkey`, `dojo-initializer`, `dojo-uwsgi`, `dojo-celeryworker`, `dojo-celerybeat`, and `dojo-nginx`.

- [ ] **Step 1: Create `.env.defectdojo`**

Create `.env.defectdojo` with exact content:

```dotenv
DOJO_DJANGO_IMAGE=defectdojo/defectdojo-django:latest
DOJO_NGINX_IMAGE=defectdojo/defectdojo-nginx:latest
DOJO_POSTGRES_IMAGE=postgres:18.4-alpine
DOJO_VALKEY_IMAGE=valkey/valkey:9.0.4-alpine
DOJO_PORT=8082
DOJO_POSTGRES_DIR=./defectdojo/postgres
DOJO_VALKEY_DIR=./defectdojo/valkey
DOJO_MEDIA_DIR=./defectdojo/media
DOJO_DATABASE_NAME=defectdojo
DOJO_DATABASE_USER=defectdojo
DOJO_DATABASE_PASSWORD=defectdojo_lab_password
DD_DATABASE_HOST=dojo-postgres
DD_DATABASE_PORT=5432
DD_DATABASE_URL=postgresql://defectdojo:defectdojo_lab_password@dojo-postgres:5432/defectdojo
DD_CELERY_BROKER_URL=redis://dojo-valkey:6379/0
DD_CELERY_RESULT_BACKEND=redis://dojo-valkey:6379/0
DD_ALLOWED_HOSTS=localhost,127.0.0.1,dojo-nginx
DD_SITE_URL=http://localhost:8082
DD_SECRET_KEY=VF_DEFECTDOJO_LAB_SECRET_KEY_2026_CHANGE_ONLY_BEFORE_FIRST_BOOT
DD_CREDENTIAL_AES_256_KEY=c8tXh6q2JXhz1Csyd0I0m2gdxJQZWyEoJMNpA8Y2k4o=
DD_INITIALIZE=true
DD_ADMIN_USER=admin
DD_ADMIN_MAIL=admin@example.local
DD_ADMIN_FIRST_NAME=Lab
DD_ADMIN_LAST_NAME=Admin
DD_DATABASE_READINESS_TIMEOUT=60
```

- [ ] **Step 2: Create `docker-compose.defectdojo.yml`**

Create `docker-compose.defectdojo.yml` with exact content:

```yaml
services:
  dojo-postgres:
    image: ${DOJO_POSTGRES_IMAGE}
    container_name: vinfast-dojo-postgres
    restart: unless-stopped
    environment:
      PGDATA: /var/lib/postgresql/data
      POSTGRES_DB: ${DOJO_DATABASE_NAME}
      POSTGRES_USER: ${DOJO_DATABASE_USER}
      POSTGRES_PASSWORD: ${DOJO_DATABASE_PASSWORD}
    volumes:
      - "${DOJO_POSTGRES_DIR}:/var/lib/postgresql/data"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DOJO_DATABASE_USER} -d ${DOJO_DATABASE_NAME}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - cicd-lab

  dojo-valkey:
    image: ${DOJO_VALKEY_IMAGE}
    container_name: vinfast-dojo-valkey
    restart: unless-stopped
    volumes:
      - "${DOJO_VALKEY_DIR}:/data"
    healthcheck:
      test: ["CMD", "valkey-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - cicd-lab

  dojo-initializer:
    image: ${DOJO_DJANGO_IMAGE}
    container_name: vinfast-dojo-initializer
    restart: "no"
    depends_on:
      - dojo-postgres
    entrypoint:
      - /wait-for-it.sh
      - ${DD_DATABASE_HOST}:${DD_DATABASE_PORT}
      - --
      - /entrypoint-initializer.sh
    environment:
      DD_DATABASE_HOST: ${DD_DATABASE_HOST}
      DD_DATABASE_PORT: ${DD_DATABASE_PORT}
      DD_DATABASE_URL: ${DD_DATABASE_URL}
      DD_SECRET_KEY: ${DD_SECRET_KEY}
      DD_CREDENTIAL_AES_256_KEY: ${DD_CREDENTIAL_AES_256_KEY}
      DD_DATABASE_READINESS_TIMEOUT: ${DD_DATABASE_READINESS_TIMEOUT}
      DD_INITIALIZE: ${DD_INITIALIZE}
      DD_ADMIN_USER: ${DD_ADMIN_USER}
      DD_ADMIN_MAIL: ${DD_ADMIN_MAIL}
      DD_ADMIN_FIRST_NAME: ${DD_ADMIN_FIRST_NAME}
      DD_ADMIN_LAST_NAME: ${DD_ADMIN_LAST_NAME}
    networks:
      - cicd-lab

  dojo-uwsgi:
    image: ${DOJO_DJANGO_IMAGE}
    container_name: vinfast-dojo-uwsgi
    restart: unless-stopped
    depends_on:
      dojo-initializer:
        condition: service_completed_successfully
      dojo-postgres:
        condition: service_healthy
      dojo-valkey:
        condition: service_healthy
    entrypoint:
      - /wait-for-it.sh
      - ${DD_DATABASE_HOST}:${DD_DATABASE_PORT}
      - -t
      - "60"
      - --
      - /entrypoint-uwsgi.sh
    environment:
      DD_DEBUG: "False"
      DD_ALLOWED_HOSTS: ${DD_ALLOWED_HOSTS}
      DD_SITE_URL: ${DD_SITE_URL}
      DD_DATABASE_HOST: ${DD_DATABASE_HOST}
      DD_DATABASE_PORT: ${DD_DATABASE_PORT}
      DD_DATABASE_URL: ${DD_DATABASE_URL}
      DD_CELERY_BROKER_URL: ${DD_CELERY_BROKER_URL}
      DD_CELERY_RESULT_BACKEND: ${DD_CELERY_RESULT_BACKEND}
      DD_SECRET_KEY: ${DD_SECRET_KEY}
      DD_CREDENTIAL_AES_256_KEY: ${DD_CREDENTIAL_AES_256_KEY}
      DD_DATABASE_READINESS_TIMEOUT: ${DD_DATABASE_READINESS_TIMEOUT}
    healthcheck:
      test: ["CMD-SHELL", "python3 -c \"import socket; s=socket.socket(); s.settimeout(3); s.connect(('127.0.0.1',3031)); s.close()\""]
      interval: 30s
      timeout: 10s
      retries: 3
    volumes:
      - "${DOJO_MEDIA_DIR}:/app/media"
    networks:
      - cicd-lab

  dojo-celeryworker:
    image: ${DOJO_DJANGO_IMAGE}
    container_name: vinfast-dojo-celeryworker
    restart: unless-stopped
    depends_on:
      dojo-initializer:
        condition: service_completed_successfully
      dojo-postgres:
        condition: service_healthy
      dojo-valkey:
        condition: service_healthy
    entrypoint:
      - /wait-for-it.sh
      - ${DD_DATABASE_HOST}:${DD_DATABASE_PORT}
      - -t
      - "60"
      - --
      - /entrypoint-celery-worker.sh
    environment:
      DD_DATABASE_HOST: ${DD_DATABASE_HOST}
      DD_DATABASE_PORT: ${DD_DATABASE_PORT}
      DD_DATABASE_URL: ${DD_DATABASE_URL}
      DD_CELERY_BROKER_URL: ${DD_CELERY_BROKER_URL}
      DD_CELERY_RESULT_BACKEND: ${DD_CELERY_RESULT_BACKEND}
      DD_SECRET_KEY: ${DD_SECRET_KEY}
      DD_CREDENTIAL_AES_256_KEY: ${DD_CREDENTIAL_AES_256_KEY}
      DD_DATABASE_READINESS_TIMEOUT: ${DD_DATABASE_READINESS_TIMEOUT}
    volumes:
      - "${DOJO_MEDIA_DIR}:/app/media"
    networks:
      - cicd-lab

  dojo-celerybeat:
    image: ${DOJO_DJANGO_IMAGE}
    container_name: vinfast-dojo-celerybeat
    restart: unless-stopped
    depends_on:
      dojo-initializer:
        condition: service_completed_successfully
      dojo-postgres:
        condition: service_healthy
      dojo-valkey:
        condition: service_healthy
    entrypoint:
      - /wait-for-it.sh
      - ${DD_DATABASE_HOST}:${DD_DATABASE_PORT}
      - -t
      - "60"
      - --
      - /entrypoint-celery-beat.sh
    environment:
      DD_DATABASE_HOST: ${DD_DATABASE_HOST}
      DD_DATABASE_PORT: ${DD_DATABASE_PORT}
      DD_DATABASE_URL: ${DD_DATABASE_URL}
      DD_CELERY_BROKER_URL: ${DD_CELERY_BROKER_URL}
      DD_CELERY_RESULT_BACKEND: ${DD_CELERY_RESULT_BACKEND}
      DD_SECRET_KEY: ${DD_SECRET_KEY}
      DD_CREDENTIAL_AES_256_KEY: ${DD_CREDENTIAL_AES_256_KEY}
      DD_DATABASE_READINESS_TIMEOUT: ${DD_DATABASE_READINESS_TIMEOUT}
    networks:
      - cicd-lab

  dojo-nginx:
    image: ${DOJO_NGINX_IMAGE}
    container_name: vinfast-dojo-nginx
    restart: unless-stopped
    depends_on:
      dojo-uwsgi:
        condition: service_healthy
    environment:
      NGINX_METRICS_ENABLED: "false"
      DD_UWSGI_HOST: dojo-uwsgi
      DD_UWSGI_PORT: "3031"
    ports:
      - "${DOJO_PORT}:8080"
    volumes:
      - "${DOJO_MEDIA_DIR}:/usr/share/nginx/html/media"
    networks:
      - cicd-lab

networks:
  cicd-lab:
    name: vinfast-cicd-lab
```

- [ ] **Step 3: Validate Compose config**

Run:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml config
```

Expected: command exits 0 and rendered config includes all seven `dojo-*` services.

- [ ] **Step 4: Commit if repository exists**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If output is `true`, run:

```powershell
git add .env.defectdojo docker-compose.defectdojo.yml
git commit -m "feat: add DefectDojo compose stack"
```

If command fails because workspace is not a git repo, record `Skipped commit: workspace is not a git repository` in final task notes.

---

### Task 2: Add DefectDojo Trivy and Dependency-Check CI Jobs

**Files:**
- Modify: `ci-cd/.gitlab-ci.yml`

**Interfaces:**
- Consumes: existing `dependency-track-sbom` job and GitLab CI variables for DefectDojo.
- Produces: `trivy-fs-scan`, `dependency-check-scan`, and `defectdojo-import` jobs plus artifacts `trivy-fs-report.json` and `dependency-check-report.json`.

- [ ] **Step 1: Replace `ci-cd/.gitlab-ci.yml` with merged CI content**

Replace `ci-cd/.gitlab-ci.yml` with exact content:

```yaml
stages:
  - security

variables:
  DTRACK_PROJECT_NAME: "vinfast-wordpress"
  DTRACK_PROJECT_VERSION: "lab"
  DTRACK_FAIL_ON_SEVERITY: "HIGH"
  DTRACK_BOM_POLL_SECONDS: "300"
  DTRACK_BOM_POLL_INTERVAL_SECONDS: "10"
  DEFECTDOJO_PRODUCT_NAME: "vinfast-wordpress"
  DEFECTDOJO_ENGAGEMENT_NAME: "gitlab-ci"
  DEFECTDOJO_PRODUCT_TYPE_NAME: "Research and Development"
  DEFECTDOJO_MIN_SEVERITY: "High"

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

trivy-fs-scan:
  stage: security
  image:
    name: aquasec/trivy:latest
    entrypoint: [""]
  script:
    - trivy --version
    - trivy fs --format json --output trivy-fs-report.json --severity HIGH,CRITICAL --exit-code 0 --no-progress .
    - test -s trivy-fs-report.json
  artifacts:
    when: always
    expire_in: 7 days
    paths:
      - trivy-fs-report.json

dependency-check-scan:
  stage: security
  image:
    name: owasp/dependency-check:latest
    entrypoint: [""]
  script:
    - /usr/share/dependency-check/bin/dependency-check.sh --version
    - /usr/share/dependency-check/bin/dependency-check.sh --project "${DEFECTDOJO_PRODUCT_NAME}" --scan . --format JSON --out . --failOnCVSS 11
    - test -s dependency-check-report.json
  artifacts:
    when: always
    expire_in: 7 days
    paths:
      - dependency-check-report.json

defectdojo-import:
  stage: security
  image: alpine:3.20
  needs:
    - job: trivy-fs-scan
      artifacts: true
    - job: dependency-check-scan
      artifacts: true
  before_script:
    - apk add --no-cache curl jq
  script:
    - |
      set -euo pipefail

      : "${DEFECTDOJO_URL:?Set DEFECTDOJO_URL in GitLab CI variables, for Docker Desktop use http://host.docker.internal:8082}"
      : "${DEFECTDOJO_API_KEY:?Set DEFECTDOJO_API_KEY in GitLab CI variables}"
      : "${DEFECTDOJO_PRODUCT_NAME:?Set DEFECTDOJO_PRODUCT_NAME}"
      : "${DEFECTDOJO_ENGAGEMENT_NAME:?Set DEFECTDOJO_ENGAGEMENT_NAME}"

      import_scan() {
        scan_type="$1"
        report_file="$2"
        echo "Importing ${scan_type}: ${report_file}"
        curl -sS --fail -X POST "${DEFECTDOJO_URL}/api/v2/reimport-scan/" \
          -H "Authorization: Token ${DEFECTDOJO_API_KEY}" \
          -F "scan_type=${scan_type}" \
          -F "file=@${report_file};type=application/json" \
          -F "product_name=${DEFECTDOJO_PRODUCT_NAME}" \
          -F "engagement_name=${DEFECTDOJO_ENGAGEMENT_NAME}" \
          -F "product_type_name=${DEFECTDOJO_PRODUCT_TYPE_NAME}" \
          -F "auto_create_context=true" \
          -F "active=true" \
          -F "verified=false" \
          -F "minimum_severity=${DEFECTDOJO_MIN_SEVERITY}" \
          -F "close_old_findings=true" | jq .
      }

      import_scan "Trivy Scan" "trivy-fs-report.json"
      import_scan "Dependency Check Scan" "dependency-check-report.json"
      echo "DefectDojo imports completed"

      trivy_high="$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH")] | length' trivy-fs-report.json)"
      trivy_critical="$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' trivy-fs-report.json)"
      dc_high="$(jq '[.dependencies[]?.vulnerabilities[]? | select(.severity == "HIGH")] | length' dependency-check-report.json)"
      dc_critical="$(jq '[.dependencies[]?.vulnerabilities[]? | select(.severity == "CRITICAL")] | length' dependency-check-report.json)"
      echo "DefectDojo gate metrics after import: trivy_high=${trivy_high}, trivy_critical=${trivy_critical}, dependency_check_high=${dc_high}, dependency_check_critical=${dc_critical}"

      if [ "${trivy_critical}" -gt 0 ] || [ "${trivy_high}" -gt 0 ] || [ "${dc_critical}" -gt 0 ] || [ "${dc_high}" -gt 0 ]; then
        echo "DefectDojo fail gate triggered after import: HIGH/CRITICAL findings found"
        exit 1
      fi

      echo "DefectDojo fail gate passed after import"
  artifacts:
    when: always
    expire_in: 7 days
    paths:
      - trivy-fs-report.json
      - dependency-check-report.json
```

- [ ] **Step 2: Validate CI file exists and contains new jobs**

Run:

```powershell
Test-Path "ci-cd/.gitlab-ci.yml"
Select-String -Path "ci-cd/.gitlab-ci.yml" -Pattern "trivy-fs-scan|dependency-check-scan|defectdojo-import|reimport-scan|Trivy Scan|Dependency Check Scan|HIGH|CRITICAL"
```

Expected: `Test-Path` prints `True`; `Select-String` output includes all listed patterns.

- [ ] **Step 3: Commit if repository exists**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If output is `true`, run:

```powershell
git add ci-cd/.gitlab-ci.yml
git commit -m "feat: add DefectDojo security scan CI"
```

If command fails because workspace is not a git repo, record `Skipped commit: workspace is not a git repository` in final task notes.

---

### Task 3: Add DefectDojo Documentation

**Files:**
- Create: `docs/defectdojo/README.md`

**Interfaces:**
- Consumes: DefectDojo Compose stack and GitLab CI jobs from Tasks 1-2.
- Produces: User docs for install, admin password retrieval, API token, CI variables, Trivy/Dependency-Check import, fail gate, verification, and cleanup.

- [ ] **Step 1: Create `docs/defectdojo/README.md`**

Create `docs/defectdojo/README.md` with exact content:

```markdown
# DefectDojo Lab

DefectDojo adds vulnerability aggregation and reporting to this local CI/CD security lab.

This lab uses:

- DefectDojo UI/API: `http://localhost:8082`
- PostgreSQL: container-only, persistent data under `defectdojo/postgres`
- Valkey: Redis-compatible broker/result backend under `defectdojo/valkey`
- GitLab CI target: `ci-cd` WordPress folder
- Default product: `vinfast-wordpress`
- Default engagement: `gitlab-ci`

## References

- Official DefectDojo Docker Compose: <https://raw.githubusercontent.com/DefectDojo/django-DefectDojo/master/docker-compose.yml>
- Official DefectDojo README: <https://raw.githubusercontent.com/DefectDojo/django-DefectDojo/master/README.md>
- Official DefectDojo configuration docs: <https://docs.defectdojo.com/get_started/open_source/configuration/>
- Import from API docs: <https://docs.defectdojo.com/import_data/import_scan_files/api_pipeline_modelling/>

## Requirements

- Docker Desktop or Docker Engine with Docker Compose plugin.
- About 8GB RAM and 4 CPU.
- GitLab already running at `http://localhost:8929`.
- Ports available on host:
  - DefectDojo HTTP: `8082`

## Environment Configuration

`.env.defectdojo` contains the stack configuration. Key variables:

| Variable | Purpose |
| --- | --- |
| `DD_SECRET_KEY` | Stable Django secret key. Keep unchanged after first boot. |
| `DD_CREDENTIAL_AES_256_KEY` | Stable encryption key for credentials. Keep unchanged after first boot. |
| `DD_DATABASE_URL` | PostgreSQL connection string. |
| `DD_CELERY_BROKER_URL` | Valkey broker URL. |
| `DD_CELERY_RESULT_BACKEND` | Valkey result backend URL. |
| `DD_SITE_URL` | Public URL, default `http://localhost:8082`. |
| `DD_ADMIN_USER` | Initial admin username, default `admin`. |

Do not change `DD_SECRET_KEY` or `DD_CREDENTIAL_AES_256_KEY` after first boot unless you intentionally reset the lab data.

## Start DefectDojo

From repository root:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml up -d
```

Check status:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml ps
```

Follow initializer logs:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml logs -f dojo-initializer
```

First boot can take several minutes while migrations and initialization run.

## Get Admin Password

DefectDojo generates the admin password during initialization.

Run:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml logs dojo-initializer | Select-String "Admin password:"
```

Login:

```text
URL: http://localhost:8082
Username: admin
Password: value printed in initializer logs
```

Change admin password after first login.

## Create API Token

In DefectDojo UI:

1. Login as `admin`.
2. Open user menu.
3. Open **API v2 Key** or user API token page.
4. Copy API token.

Store API token only in GitLab CI/CD variables. Do not commit API tokens into repo files.

## GitLab CI Variables

In GitLab project for `ci-cd`, open **Settings > CI/CD > Variables** and add:

| Variable | Value |
| --- | --- |
| `DEFECTDOJO_URL` | `http://host.docker.internal:8082` |
| `DEFECTDOJO_API_KEY` | API token from DefectDojo |
| `DEFECTDOJO_PRODUCT_NAME` | `vinfast-wordpress` |
| `DEFECTDOJO_ENGAGEMENT_NAME` | `gitlab-ci` |
| `DEFECTDOJO_MIN_SEVERITY` | `High` |

Use `http://host.docker.internal:8082` on Docker Desktop so GitLab Runner job containers can reach the host-published DefectDojo port.

If runner job containers are attached to Docker network `vinfast-cicd-lab`, `DEFECTDOJO_URL` may be set to:

```text
http://dojo-nginx:8080
```

## CI Behavior

File `ci-cd/.gitlab-ci.yml` contains these DefectDojo jobs:

- `trivy-fs-scan`
- `dependency-check-scan`
- `defectdojo-import`

Trivy job:

1. Runs filesystem scan against repository contents.
2. Writes `trivy-fs-report.json`.
3. Records `HIGH` and `CRITICAL` counts.
4. Saves report as artifact.
5. Does not fail before import, so DefectDojo receives the report.

Dependency-Check job:

1. Runs OWASP Dependency-Check against repository contents.
2. Writes `dependency-check-report.json`.
3. Records `HIGH` and `CRITICAL` counts.
4. Saves report as artifact.
5. Does not fail before import, so DefectDojo receives the report.

DefectDojo import job:

1. Downloads scanner artifacts.
2. Calls `POST /api/v2/reimport-scan/`.
3. Imports Trivy report as scan type `Trivy Scan`.
4. Imports Dependency-Check report as scan type `Dependency Check Scan`.
5. Uses `auto_create_context=true` to create product/engagement if missing.
6. Fails after imports if either report contains `HIGH` or `CRITICAL` findings.

## Fail Gate

Pipeline imports reports into DefectDojo first, then fails when either scanner reports any:

- `CRITICAL` finding
- `HIGH` finding

Reports are kept as artifacts even when the gate fails, and DefectDojo receives reports before failure.

## Verify Locally

Validate Compose config:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml config
```

Check UI:

```powershell
Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8082"
```

Expected:

- Compose config command exits 0.
- UI request returns HTTP 200.
- Browser can open `http://localhost:8082`.

## Verify from GitLab CI

1. Push or copy `ci-cd/.gitlab-ci.yml` into GitLab project for `ci-cd`.
2. Configure GitLab CI variables listed above.
3. Run pipeline.
4. Confirm artifacts exist:
   - `trivy-fs-report.json`
   - `dependency-check-report.json`
5. Open DefectDojo UI.
6. Open product `vinfast-wordpress`.
7. Open engagement `gitlab-ci`.
8. Confirm imported tests/findings exist.
9. Confirm pipeline gate result matches `HIGH` and `CRITICAL` findings.

## Stop DefectDojo

Stop containers but keep data:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml down
```

Delete all DefectDojo data:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml down
Remove-Item -Recurse -Force .\defectdojo
```

## Resource Notes

This host has about 8GB RAM. Keep DefectDojo separate from GitLab and Dependency-Track so it can be stopped when not importing findings.

Dependency-Check can be slow and memory-heavy. First run downloads vulnerability data and may take significant time.

If memory pressure appears:

1. Stop unused services.
2. Start only GitLab and DefectDojo for import testing.
3. Avoid running Harbor, ArgoCD, DefectDojo, and Dependency-Track all at once until host resources are increased.

## Troubleshooting

### UI cannot open

Check status:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml ps
```

Follow logs:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml logs -f dojo-uwsgi dojo-nginx
```

### Admin password not visible

Read initializer logs:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml logs dojo-initializer | Select-String "Admin password:"
```

If data was already initialized, password may not print again. Use DefectDojo password reset flow or reset lab data.

### GitLab CI cannot reach DefectDojo

Use this GitLab CI variable on Docker Desktop:

```text
DEFECTDOJO_URL=http://host.docker.internal:8082
```

If using shared Docker network access, attach runner job containers to `vinfast-cicd-lab` and use:

```text
DEFECTDOJO_URL=http://dojo-nginx:8080
```

### Import fails

Check:

- `DEFECTDOJO_API_KEY` is correct.
- `DEFECTDOJO_URL` is reachable from CI job container.
- Scan type names are exactly `Trivy Scan` and `Dependency Check Scan`.
- API token has permission to import scans.

### Pipeline fails on HIGH or CRITICAL findings

Open DefectDojo UI:

1. Open product `vinfast-wordpress`.
2. Open engagement `gitlab-ci`.
3. Review findings.
4. Fix vulnerable components or mark findings false positive only after validation.
```

- [ ] **Step 2: Validate docs file exists and mentions required topics**

Run:

```powershell
Test-Path "docs/defectdojo/README.md"
Select-String -Path "docs/defectdojo/README.md" -Pattern "Admin password|DEFECTDOJO_API_KEY|Trivy Scan|Dependency Check Scan|HIGH|CRITICAL|reimport-scan"
```

Expected: `Test-Path` prints `True`; `Select-String` output includes all listed patterns.

- [ ] **Step 3: Commit if repository exists**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If output is `true`, run:

```powershell
git add docs/defectdojo/README.md
git commit -m "docs: add DefectDojo lab guide"
```

If command fails because workspace is not a git repo, record `Skipped commit: workspace is not a git repository` in final task notes.

---

### Task 4: Start DefectDojo and Verify UI

**Files:**
- Modify: none

**Interfaces:**
- Consumes: Compose stack from Task 1.
- Produces: Running DefectDojo UI at `http://localhost:8082` and admin password retrieval process.

- [ ] **Step 1: Start DefectDojo stack**

Run:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml up -d
```

Expected: command exits 0 and starts containers `vinfast-dojo-postgres`, `vinfast-dojo-valkey`, `vinfast-dojo-uwsgi`, `vinfast-dojo-celeryworker`, `vinfast-dojo-celerybeat`, `vinfast-dojo-nginx`. `vinfast-dojo-initializer` exits 0 after initialization.

- [ ] **Step 2: Check Compose status**

Run:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml ps
```

Expected: long-running services are `running` or `Up`; initializer is completed/exited 0.

- [ ] **Step 3: Wait for UI**

Run this until it returns HTTP 200 or timeout after 10 minutes:

```powershell
$deadline = (Get-Date).AddMinutes(10)
$last = $null
while ((Get-Date) -lt $deadline) {
  try {
    $status = (Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8082" -TimeoutSec 10).StatusCode
    if ($status -eq 200) { "UI status: $status"; break }
    $last = "UI status: $status"
  } catch {
    $last = $_.Exception.Message
  }
  Start-Sleep -Seconds 15
}
if ($last -and $last -notmatch "UI status: 200") { "Last UI result: $last" }
```

Expected final output includes:

```text
UI status: 200
```

- [ ] **Step 4: Read admin password from initializer logs**

Run:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml logs dojo-initializer | Select-String "Admin password:"
```

Expected: output includes `Admin password:`.

- [ ] **Step 5: Record verification result**

Record these facts in final task notes:

```text
DefectDojo URL: http://localhost:8082
DefectDojo containers: vinfast-dojo-postgres, vinfast-dojo-valkey, vinfast-dojo-uwsgi, vinfast-dojo-celeryworker, vinfast-dojo-celerybeat, vinfast-dojo-nginx
UI status: 200
Admin password retrieval: logs contain Admin password
```

---

## Self-Review

Spec coverage:

- Self-contained lab Docker Compose: Task 1.
- Upstream service layout alignment: Task 1 uses nginx/uwsgi/initializer/celery/postgres/valkey and upstream entrypoints.
- Docs under `docs/`: Task 3.
- Security target `ci-cd`: Task 2.
- Trivy filesystem scan: Task 2.
- OWASP Dependency-Check scan: Task 2.
- DefectDojo API import: Task 2 uses `/api/v2/reimport-scan/` with `auto_create_context=true`.
- HIGH/CRITICAL fail gate: Task 2 and docs Task 3.
- Admin password from initializer logs: Task 3 and Task 4.
- UI verification: Task 4.
- 8GB RAM notes: Task 3.

Placeholder scan:

- No `TBD`, `TODO`, or unspecified implementation steps.
- Runtime secrets `DEFECTDOJO_API_KEY` and API tokens are not committed.
- `.env.defectdojo` includes lab-local stable secrets because this is a local lab.

Type/interface consistency:

- Service names match across compose/docs: `dojo-postgres`, `dojo-valkey`, `dojo-initializer`, `dojo-uwsgi`, `dojo-celeryworker`, `dojo-celerybeat`, `dojo-nginx`.
- Container names match verification notes.
- GitLab CI variable names match docs and spec.
- DefectDojo product and engagement names match spec exactly.
