# Harbor Registry Lab Design

Date: 2026-07-05
Branch: `feature/harbor-argocd-gitops`

## Goal

Add Harbor as a container image registry to the local CI/CD security lab using Docker Compose, then connect GitLab CI for the existing `ci-cd` WordPress folder so pipelines build a Docker image and push it to Harbor.

## Constraints

- Host has about 8GB RAM and 4 CPU.
- Build one component at a time; do not run Harbor together with GitLab, Dependency-Track, and DefectDojo unless needed for a specific test.
- GitLab already runs at `http://localhost:8929`.
- Dependency-Track already runs at `http://localhost:8081` UI / `http://localhost:8080` API.
- DefectDojo already runs at `http://localhost:8082`.
- Work happens on branch `feature/harbor-argocd-gitops`; do not merge into or modify `main`.
- Documentation must be written under `docs/`.
- Harbor runs over plain HTTP (insecure registry) — no TLS/self-signed cert setup for this lab phase.
- Push target is the existing `ci-cd` WordPress folder (built from its existing `Dockerfile`).

## References

- Official Harbor installer Docker Compose layout: `https://github.com/goharbor/harbor/blob/main/make/photon/prepare/templates/`
- Harbor docs — installation and configuration: `https://goharbor.io/docs/latest/install-config/`

## Recommended Approach

Self-contained Docker Compose file in the lab repo, modeled after Harbor's own service layout, trimmed to what a single-node HTTP lab install needs.

Services:

1. `harbor-log`
   - Centralized log driver container other Harbor services depend on for logging.

2. `harbor-postgres`
   - PostgreSQL database for Harbor core/clair metadata.
   - Persistent volume under `harbor/database`.

3. `harbor-redis`
   - Redis cache used by core and jobservice.
   - Persistent volume under `harbor/redis`.

4. `harbor-registry`
   - Docker Distribution registry storing image layers.
   - Persistent volume under `harbor/registry`.

5. `harbor-registryctl`
   - Sidecar controlling registry lifecycle actions.

6. `harbor-core`
   - Harbor core API/business logic.

7. `harbor-portal`
   - Harbor web UI.

8. `harbor-jobservice`
   - Async job runner (scanning, replication, retention).
   - Persistent volume under `harbor/job_logs`.

9. `harbor-proxy` (nginx)
   - Single entrypoint reverse-proxying to portal/core/registry.
   - Host port `8083` for UI + registry access (`docker login localhost:8083`).

All services join Docker network `vinfast-cicd-lab`.

Trivy scanning inside Harbor (Harbor's own built-in scanner) is out of scope — the lab already covers Trivy/Dependency-Check scanning through the DefectDojo pipeline. Harbor's Trivy adapter service is not included to keep the service count down.

## Required Harbor Environment

Create `.env.harbor` with stable lab values:

- `HARBOR_HOSTNAME` — `localhost`.
- `HARBOR_PORT` — `8083`.
- `HARBOR_ADMIN_PASSWORD` — stable lab admin password (default Harbor account is `admin`).
- `HARBOR_DB_PASSWORD` — Postgres password for Harbor's internal database.
- `HARBOR_SECRET` / core secret keys — used for JWT/registry token signing between core and registry; must stay stable across restarts.
- Registry storage/auth config embedded in a generated `config.yml`-equivalent set of env vars (core token service, registry htpasswd, etc.), or via mounted config files under `harbor/config/` — exact mechanism to be worked out at plan time based on Harbor's Compose template, since Harbor (unlike GitLab/Dependency-Track/DefectDojo) requires several generated config files (registry auth cert, core token cert) rather than pure env vars.

A `.env.harbor.example` file with placeholders will be committed; the real `.env.harbor` stays local per the lab's existing `.gitignore` pattern.

## Data Flow

1. User starts Harbor stack with Docker Compose.
2. User opens Harbor UI at `http://localhost:8083`.
3. User logs in as `admin`, creates a project (e.g. `vinfast`) and a robot account with push/pull permission.
4. User configures Docker daemon (and later k3d, in the ArgoCD phase) to treat `localhost:8083` as an insecure registry.
5. GitLab project for `ci-cd` runs pipeline.
6. CI job builds the Docker image from `ci-cd/Dockerfile`.
7. CI job logs into Harbor using the robot account credentials (stored as masked GitLab CI variables).
8. CI job tags and pushes the image to `localhost:8083/vinfast/wordpress:<tag>` (or `host.docker.internal:8083/...` depending on how the GitLab Runner job container reaches Harbor — same pattern as the DefectDojo/Dependency-Track `host.docker.internal` note).
9. User verifies the pushed image and tag in the Harbor UI under project `vinfast`.

## GitLab CI Integration

Add a Harbor build-and-push job to `ci-cd/.gitlab-ci.yml`, in a new `build` stage that runs before the existing `security` stage (so a scan can target the freshly built image in a later phase if desired — not required now).

Required GitLab CI variables:

- `HARBOR_URL` — `host.docker.internal:8083` for Docker Desktop runner job containers.
- `HARBOR_ROBOT_USER` — robot account username (e.g. `robot$ci-cd+push`).
- `HARBOR_ROBOT_TOKEN` — robot account token (masked/protected CI variable).
- `HARBOR_PROJECT` — `vinfast`.
- `HARBOR_IMAGE_NAME` — `wordpress`.

Pipeline behavior:

- Use Docker-in-Docker (same pattern already proven in `examples/gitlab-ci-dind/`) to build the image from `ci-cd/Dockerfile`.
- Tag image as `${HARBOR_URL}/${HARBOR_PROJECT}/${HARBOR_IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}` and `:latest`.
- Configure the DinD daemon to trust `HARBOR_URL` as an insecure registry (`--insecure-registry` flag or `daemon.json` equivalent inside the `docker:24-dind` service).
- Log into Harbor with the robot account.
- Push both tags.
- No fail gate in this job — Harbor push success/failure is the only pass/fail signal. Vulnerability gating stays with the existing Trivy/Dependency-Check/DefectDojo jobs.

## Documentation

Create `docs/harbor/README.md` with:

- Docker prerequisites.
- Service overview.
- Environment configuration and which secrets must stay stable.
- Start commands.
- UI URL and admin login.
- Steps to create a project and a robot account.
- Insecure-registry configuration for Docker daemon (and a forward note that the ArgoCD phase will need the same for k3d).
- GitLab CI variables.
- Build-and-push pipeline explanation.
- Verification steps (confirm image appears in Harbor UI).
- Stop and data-delete commands.
- 8GB RAM notes — do not run Harbor at the same time as GitLab, Dependency-Track, and DefectDojo unless actively testing the full chain.
- Troubleshooting for startup, insecure-registry, and CI push failures.

## Files to Create or Modify

- Create `.env.harbor` (local only) and `.env.harbor.example` — ports, images, generated secrets/certs config.
- Create `docker-compose.harbor.yml` — Harbor services modeled after upstream Compose template.
- Create `docs/harbor/README.md` — install and usage guide.
- Modify `ci-cd/.gitlab-ci.yml` — add a `build` stage with the Harbor build-and-push job, ahead of the existing `security` stage jobs.

## Success Criteria

- `docker compose --env-file .env.harbor -f docker-compose.harbor.yml config` passes.
- Harbor UI reachable at `http://localhost:8083`.
- Admin login works with username `admin` and the configured lab password.
- User can create project `vinfast` and a robot account with push/pull scope.
- Docker daemon (and GitLab Runner's DinD job containers) can push/pull against Harbor over HTTP without TLS errors, once configured as an insecure registry.
- `ci-cd` GitLab CI pipeline builds the WordPress image and pushes it to Harbor under project `vinfast`.
- Harbor UI shows the pushed image with both the commit-SHA tag and `latest`.
- Documentation under `docs/harbor/README.md` explains install, usage, and insecure-registry setup.

## Resource Strategy

Because host has 8GB RAM:

- Keep Harbor in its own Compose file, started independently of the other three stacks.
- Start Harbor only when building/pushing images or testing the CI build job.
- Stop unused services when memory pressure appears.
- Harbor has more services (9) than any prior phase — expect it to be the heaviest single stack so far after GitLab; plan to stop GitLab or the DefectDojo stack while testing Harbor push if RAM is tight.

## Risks and Mitigations

- Harbor's official Compose template generates TLS certs and htpasswd files via a `prepare` script that this lab is not using verbatim.
  - Mitigation: at plan/implementation time, adapt the minimum config Harbor's core/registry/portal need for HTTP-only operation (registry auth cert pair is still required internally by Harbor even without external TLS); document any deviation from upstream in `docs/harbor/README.md`.
- Insecure registry configuration is easy to get wrong (different mechanism for Docker Desktop daemon vs. DinD service container vs. later k3d).
  - Mitigation: document each surface explicitly and verify each with a manual `docker login`/`docker push` test before wiring CI.
- Robot account token is sensitive.
  - Mitigation: docs instruct storing it as a masked/protected GitLab CI variable, not committing it.
- Running Harbor alongside GitLab/Dependency-Track/DefectDojo may exceed 8GB RAM.
  - Mitigation: docs repeat the one-stack-at-a-time guidance; success criteria only require the CI build/push job to pass, not all four stacks running simultaneously.
