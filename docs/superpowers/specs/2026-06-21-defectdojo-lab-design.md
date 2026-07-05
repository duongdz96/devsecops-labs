# DefectDojo Lab Design

Date: 2026-06-21

## Goal

Add DefectDojo to the local CI/CD security lab using Docker Compose, then connect GitLab CI for the existing `ci-cd` WordPress folder so pipelines run Trivy and OWASP Dependency-Check, import reports into DefectDojo, and fail on `HIGH` or `CRITICAL` findings.

## Constraints

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

## References

- Official DefectDojo Docker Compose: `https://raw.githubusercontent.com/DefectDojo/django-DefectDojo/master/docker-compose.yml`
- Official DefectDojo configuration docs: `https://docs.defectdojo.com/get_started/open_source/configuration/`

## Recommended Approach

Use a self-contained Docker Compose file in the lab repo, modeled after upstream DefectDojo Compose service layout.

Services:

1. `dojo-postgres`
   - PostgreSQL database for DefectDojo.
   - Persistent volume under `defectdojo/postgres`.

2. `dojo-valkey`
   - Valkey service for Celery broker/result backend.
   - Upstream DefectDojo uses Valkey as Redis-compatible service.

3. `dojo-initializer`
   - Runs DefectDojo initialization/migrations/admin bootstrap before app workers start.
   - Uses same Django image as app services.

4. `dojo-uwsgi`
   - DefectDojo Django/uWSGI app service.

5. `dojo-celeryworker`
   - Background import/task worker.

6. `dojo-celerybeat`
   - Scheduled background tasks.

7. `dojo-nginx`
   - Frontend reverse proxy exposed on host port `8082`.

All services join Docker network `vinfast-cicd-lab`.

## Required DefectDojo Environment

Create `.env.defectdojo` with stable lab values:

- `DD_SECRET_KEY` — stable Django secret key.
- `DD_CREDENTIAL_AES_256_KEY` — stable credential encryption key.
- `DD_DATABASE_URL` — PostgreSQL connection string.
- `DD_CELERY_BROKER_URL` — `redis://dojo-valkey:6379/0`.
- `DD_CELERY_RESULT_BACKEND` — `redis://dojo-valkey:6379/0`.
- `DD_ALLOWED_HOSTS` — `localhost,127.0.0.1,dojo-nginx`.
- `DD_SITE_URL` — `http://localhost:8082`.
- `DD_ADMIN_USER` — `admin`.
- `DD_ADMIN_MAIL` — lab admin email.
- Admin password is generated during initialization and must be read from initializer logs; do not assume `DD_ADMIN_PASSWORD` works.

`DD_SECRET_KEY` and `DD_CREDENTIAL_AES_256_KEY` must remain stable across restarts. Changing them can invalidate sessions or encrypted credentials/API tokens.

## Data Flow

1. User starts DefectDojo stack with Docker Compose.
2. Initializer runs migrations/bootstrap.
3. User opens DefectDojo UI at `http://localhost:8082`.
4. User logs in as admin and creates API token.
5. GitLab project for `ci-cd` runs pipeline.
6. CI job runs Trivy filesystem scan and outputs JSON report.
7. CI job runs OWASP Dependency-Check and outputs JSON report.
8. CI job imports both reports to DefectDojo via API.
9. CI job fails if either scanner reports any `HIGH` or `CRITICAL` finding.
10. User reviews product, engagement, tests, and findings in DefectDojo UI.

## GitLab CI Integration

Update `ci-cd/.gitlab-ci.yml` to include DefectDojo import jobs while preserving the existing Dependency-Track SBOM job.

Required GitLab CI variables:

- `DEFECTDOJO_URL` — `http://host.docker.internal:8082` for Docker Desktop runner job containers.
- `DEFECTDOJO_API_KEY` — DefectDojo API token.
- `DEFECTDOJO_PRODUCT_NAME` — `vinfast-wordpress`.
- `DEFECTDOJO_ENGAGEMENT_NAME` — `gitlab-ci`.
- `DEFECTDOJO_MIN_SEVERITY` — `High`.

Pipeline behavior:

- Run Trivy filesystem scan against project contents.
- Save Trivy JSON report as `trivy-fs-report.json`.
- Run OWASP Dependency-Check against project contents.
- Save Dependency-Check JSON report as `dependency-check-report.json`.
- Import Trivy report into DefectDojo scan type `Trivy Scan`.
- Import Dependency-Check report into DefectDojo scan type `Dependency Check Scan`.
- Save both reports as CI artifacts.
- Fail pipeline if Trivy finds `HIGH` or `CRITICAL` vulnerabilities.
- Fail pipeline if Dependency-Check JSON contains `HIGH` or `CRITICAL` severity vulnerabilities.

## Documentation

Create `docs/defectdojo/README.md` with:

- Docker prerequisites.
- Service overview.
- Environment configuration and secret stability notes.
- Start commands.
- UI URL and login instructions.
- API token creation instructions.
- GitLab CI variables.
- Trivy + Dependency-Check pipeline explanation.
- DefectDojo import behavior.
- HIGH/CRITICAL fail gate behavior.
- Verification steps.
- Stop and data-delete commands.
- 8GB RAM notes.
- Troubleshooting for startup, API, and CI import failures.

## Files to Create or Modify

- Create `.env.defectdojo` — ports, images, database credentials, Django secrets, admin bootstrap values.
- Create `docker-compose.defectdojo.yml` — DefectDojo services modeled after upstream compose.
- Create `docs/defectdojo/README.md` — install and usage guide.
- Modify `ci-cd/.gitlab-ci.yml` — add Trivy and Dependency-Check scan/import/fail-gate jobs while keeping Dependency-Track SBOM job.

## Success Criteria

- `docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml config` passes.
- DefectDojo UI reachable at `http://localhost:8082`.
- Admin login works with username `admin` and password read from initializer logs.
- User can create/copy API token.
- `ci-cd` GitLab CI jobs generate:
  - `trivy-fs-report.json`
  - `dependency-check-report.json`
- CI imports both reports into DefectDojo.
- DefectDojo UI shows product `vinfast-wordpress` and engagement `gitlab-ci` with imported findings.
- CI pipeline fails when Trivy or Dependency-Check reports `HIGH` or `CRITICAL` findings.
- CI pipeline passes when both scanner imports succeed and no `HIGH` or `CRITICAL` findings are reported.
- Documentation under `docs/defectdojo/README.md` explains install and usage.

## Resource Strategy

Because host has 8GB RAM:

- Keep DefectDojo in its own Compose file.
- Start DefectDojo only when importing/scanning findings.
- Stop unused services when memory pressure appears.
- Dependency-Check can be slow and memory-heavy; CI docs must warn that first run downloads vulnerability data and may take time.
- Avoid running future Harbor, ArgoCD, DefectDojo, and Dependency-Track all at once unless host resources are increased.

## Risks and Mitigations

- Self-contained DefectDojo Compose can drift from upstream.
  - Mitigation: base service layout and critical environment variables on official upstream Compose and configuration docs; document references.
- DefectDojo initializer/migrations may take time.
  - Mitigation: docs explain first boot delay and log commands.
- `DD_SECRET_KEY` or `DD_CREDENTIAL_AES_256_KEY` changes can invalidate credentials.
  - Mitigation: store stable lab values in `.env.defectdojo` and document not to change them after first start.
- Dependency-Check can be slow and network-heavy.
  - Mitigation: keep reports as artifacts, document first-run delay, and keep fail gate explicit.
- GitLab Runner may not reach DefectDojo service by Docker service name.
  - Mitigation: default docs use `http://host.docker.internal:8082` on Docker Desktop; document service-name URL only if runner job containers join `vinfast-cicd-lab`.
- API token is sensitive.
  - Mitigation: docs instruct storing it as masked/protected GitLab CI variable, not committing it.
