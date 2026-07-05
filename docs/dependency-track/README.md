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

## Environment Configuration

`.env.dependency-track` contains the stack configuration. Key variables:

| Variable | Purpose |
| --- | --- |
| `DTRACK_ALPINE_SECRET_KEY` | 64-char hex secret for API key encryption. Must remain stable across restarts. Changing it invalidates all existing API keys. |
| `DTRACK_API_PORT` | Host port for Dependency-Track API (default `8080`). |
| `DTRACK_FRONTEND_PORT` | Host port for Dependency-Track UI (default `8081`). |
| `DTRACK_POSTGRES_PASSWORD` | PostgreSQL password for the `dtrack` database. |

CORS is restricted to `http://localhost:${DTRACK_FRONTEND_PORT}` (the frontend origin). Wildcard `*` is not used.

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
