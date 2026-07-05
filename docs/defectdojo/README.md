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
3. Saves report as artifact.
4. Does not fail before import, so DefectDojo receives the report.

Dependency-Check job:

1. Runs OWASP Dependency-Check against repository contents.
2. Writes `dependency-check-report.json`.
3. Saves report as artifact.
4. Does not fail before import, so DefectDojo receives the report.

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
