# Dependency-Track Lab Design

Date: 2026-06-21

## Goal

Add Dependency-Track to the local CI/CD security lab using Docker Compose, then connect GitLab CI for the existing `ci-cd` WordPress folder so pipelines generate and upload SBOMs.

## Constraints

- Host has about 8GB RAM and 4 CPU.
- Build one component at a time.
- GitLab already runs at `http://localhost:8929`.
- Dependency-Track must run separately from GitLab so services can be started/stopped independently.
- Documentation must be written under `docs/`.
- SBOM target is existing `ci-cd` WordPress folder.
- Add severity fail gate: pipeline fails when Dependency-Track reports any `HIGH` or `CRITICAL` vulnerable component for project `vinfast-wordpress` version `lab`.

## Recommended Approach

Use the official Dependency-Track split deployment with PostgreSQL:

1. `dtrack-postgres`
   - Image: `postgres:16-alpine`.
   - Persistent volume: `dependency-track/postgres`.
   - Stores Dependency-Track database.

2. `dtrack-apiserver`
   - Image: `dependencytrack/apiserver`.
   - Host port: `8080`.
   - Depends on PostgreSQL.
   - Exposes REST API for GitLab CI SBOM upload.

3. `dtrack-frontend`
   - Image: `dependencytrack/frontend`.
   - Host port: `8081`.
   - Points to API server.
   - Web UI for project, vulnerability, and policy review.

All services join Docker network `vinfast-cicd-lab` so GitLab Runner jobs can reach the API by service name `dtrack-apiserver` when runner containers join that network or when CI uses host-accessible URL.

## Data Flow

1. User starts Dependency-Track stack with Docker Compose.
2. User opens UI at `http://localhost:8081`.
3. User logs in with default admin credentials, changes password, and creates API key.
4. GitLab project for `ci-cd` runs pipeline.
5. CI job uses Syft to generate CycloneDX SBOM from the repo contents.
6. CI job uploads SBOM to Dependency-Track API.
7. Dependency-Track creates/updates project `vinfast-wordpress` version `lab`.
8. CI gate queries Dependency-Track findings for project `vinfast-wordpress` version `lab`.
9. Pipeline fails if any `HIGH` or `CRITICAL` vulnerable component exists; otherwise it passes.
10. User reviews components and vulnerabilities in Dependency-Track UI.

## GitLab CI Integration

Add a Dependency-Track SBOM upload job for the `ci-cd` WordPress folder.

Required GitLab CI variables:

- `DTRACK_API_URL` — API endpoint. For host-mapped access use `http://host.docker.internal:8080`. For shared Docker network access use `http://dtrack-apiserver:8080`.
- `DTRACK_API_KEY` — Dependency-Track API key with BOM upload/project creation permissions.
- `DTRACK_PROJECT_NAME` — `vinfast-wordpress`.
- `DTRACK_PROJECT_VERSION` — `lab`.

Pipeline behavior:

- Generate CycloneDX JSON SBOM as `gl-sbom.cdx.json`.
- Upload SBOM to `/api/v1/bom` with `autoCreate=true`.
- Save SBOM as pipeline artifact.
- Poll Dependency-Track until BOM processing finishes or timeout is reached.
- Query project findings/metrics after upload.
- Fail pipeline if any `HIGH` or `CRITICAL` vulnerable component exists.
- Pass pipeline only when upload succeeds and severity gate passes.
- Allow gate threshold to be changed later with a CI variable, but default threshold is `HIGH`.

## Documentation

Create `docs/dependency-track/README.md` with:

- Docker prerequisites.
- Start commands.
- UI/API URLs.
- Default login and password-change instructions.
- API key creation instructions.
- GitLab CI variables.
- SBOM upload pipeline explanation.
- Severity fail gate behavior for `HIGH` and `CRITICAL` findings.
- Verification steps.
- Stop and data-delete commands.
- 8GB RAM notes.

## Files to Create or Modify

- Create `.env.dependency-track` — local ports, database user/password, image tags.
- Create `docker-compose.dependency-track.yml` — Dependency-Track API, frontend, PostgreSQL.
- Create `docs/dependency-track/README.md` — install and usage guide.
- Modify or create `ci-cd/.gitlab-ci.yml` — SBOM generation and upload job.

## Success Criteria

- `docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml config` passes.
- Dependency-Track UI reachable at `http://localhost:8081`.
- Dependency-Track API reachable at `http://localhost:8080`.
- `ci-cd` GitLab CI job generates `gl-sbom.cdx.json`.
- CI job uploads SBOM to Dependency-Track.
- Dependency-Track UI shows project `vinfast-wordpress` version `lab`.
- CI pipeline fails when Dependency-Track reports `HIGH` or `CRITICAL` vulnerable components.
- CI pipeline passes when upload succeeds and no `HIGH` or `CRITICAL` vulnerable components are reported.
- Documentation under `docs/dependency-track/README.md` explains install and usage.

## Resource Strategy

Because host has 8GB RAM:

- Keep Dependency-Track in its own Compose file.
- Start Dependency-Track only when scanning SBOMs.
- Stop unused services when memory pressure appears.
- Avoid running future Harbor, ArgoCD, DefectDojo, and Dependency-Track all at once unless host resources are increased.

## Risks and Mitigations

- Dependency-Track first NVD/data sync can take time.
  - Mitigation: docs explain initial sync delay; SBOM upload can succeed before all vulnerability data is ready.
- GitLab Runner may not reach `dtrack-apiserver` by Docker service name if runner job containers are not attached to `vinfast-cicd-lab`.
  - Mitigation: default docs use `http://host.docker.internal:8080` on Docker Desktop; also document `http://dtrack-apiserver:8080` if runner network is adjusted.
- CI API key is sensitive.
  - Mitigation: docs instruct storing it as masked/protected GitLab CI variable, not committing it.
- WordPress folder may contain many vendored dependencies, so gate may fail on real vulnerable components.
  - Mitigation: docs explain how to inspect findings in Dependency-Track and temporarily lower enforcement only by changing CI variables deliberately.
- Dependency-Track analysis may not finish immediately after BOM upload.
  - Mitigation: CI polls processing/metrics with timeout before deciding gate result; timeout fails pipeline so missing scan data is not treated as pass.
