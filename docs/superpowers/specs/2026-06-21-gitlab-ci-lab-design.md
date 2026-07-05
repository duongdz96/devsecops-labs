# GitLab CI Lab Design

Date: 2026-06-21

## Goal

Build first phase of local CI/CD security lab: GitLab CE with GitLab CI runner, using Docker Compose. Later phases add Harbor, ArgoCD, Dependency-Track, and DefectDojo.

## Constraints

- Host has about 8GB RAM and 4 CPU.
- Build one component at a time.
- GitLab URL: `http://localhost:8929`.
- Git over SSH exposed on host port `2224`.
- Runner must support Docker image builds with Docker-in-Docker.

## Recommended Approach

Use GitLab CE Omnibus container plus GitLab Runner container in Docker Compose.

Services:

1. `gitlab`
   - Image: `gitlab/gitlab-ce`.
   - Ports: `8929:8929`, `2224:22`.
   - Persistent volumes: `gitlab/config`, `gitlab/logs`, `gitlab/data`.
   - `external_url` set to `http://localhost:8929`.
   - SSH port configured as `2224`.

2. `gitlab-runner`
   - Image: `gitlab/gitlab-runner`.
   - Persistent volume: `gitlab-runner/config`.
   - Depends on GitLab service.
   - Registered after GitLab boots and runner token is available.
   - Docker executor, privileged mode enabled for Docker-in-Docker.

## Data Flow

1. User accesses GitLab at `http://localhost:8929`.
2. User creates project/repo in GitLab.
3. Project contains `.gitlab-ci.yml`.
4. GitLab schedules CI job.
5. GitLab Runner picks job through GitLab API.
6. Runner starts Docker job container.
7. Job uses `docker:dind` service to build container images.
8. Later phases push images to Harbor, scan SBOM/vulnerabilities with Dependency-Track, report findings to DefectDojo, and deploy through ArgoCD.

## Bootstrapping Steps

1. Create Compose file for GitLab and GitLab Runner.
2. Start GitLab.
3. Wait until GitLab health endpoint responds.
4. Read initial root password from GitLab container or mounted config.
5. Login as `root`.
6. Create or copy runner token from GitLab UI.
7. Register runner using Docker executor:
   - URL: `http://gitlab:8929` from Docker network, or `http://localhost:8929` from host command depending registration method.
   - Executor: `docker`.
   - Default image: `docker:24`.
   - Privileged: `true`.
   - Volumes: `/certs/client`, `/cache`.
8. Run sample pipeline that executes Docker-in-Docker build.

## Sample CI Success Criteria

A demo project pipeline must pass with stages:

- `test`: print environment and Docker client version.
- `build`: start Docker-in-Docker and build a tiny image.

Required job variables:

- `DOCKER_HOST=tcp://docker:2375`
- `DOCKER_TLS_CERTDIR=""`

Required service:

- `docker:24-dind`

## Resource Strategy

Because host has 8GB RAM:

- Start GitLab phase only first.
- Avoid running Harbor, ArgoCD, Dependency-Track, and DefectDojo at same time until GitLab is stable.
- Use Docker Compose profiles or separate compose files for later phases.
- Stop unused components when testing another phase if memory pressure appears.

## Out of Scope for This Phase

- Harbor installation.
- ArgoCD installation.
- Kubernetes cluster setup.
- Dependency-Track installation.
- DefectDojo installation.
- Production TLS certificates.
- External domain/DNS.

## Risks and Mitigations

- GitLab Omnibus is memory-heavy on 8GB RAM.
  - Mitigation: run only GitLab phase first, avoid parallel stacks.
- Runner privileged mode is unsafe for shared environments.
  - Mitigation: lab-only local runner, not for untrusted jobs.
- Docker-in-Docker needs correct runner config.
  - Mitigation: register runner with `privileged = true` and test with minimal `.gitlab-ci.yml`.

## Files to Create

- `docker-compose.gitlab.yml` — GitLab and runner services.
- `.env.gitlab` — port and image settings if useful.
- `scripts/gitlab-register-runner.ps1` — optional helper to register runner after token exists.
- `examples/gitlab-ci-dind/.gitlab-ci.yml` — sample pipeline for verification.
- `README.md` — runbook for start, login, runner register, test pipeline.
