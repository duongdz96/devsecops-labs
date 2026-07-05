# Dependency-Track Task 4 Report

## STATUS: DONE_WITH_CONCERNS

## Commands Run and Results

Initial command:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml up -d
```

Initial result: exit code 1. `vinfast-dtrack-apiserver` became unhealthy and `dtrack-frontend` dependency failed to start.

Root cause investigation:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml logs --no-color --tail 200 dtrack-apiserver
docker inspect vinfast-dtrack-apiserver --format '{{json .State.Health}}'
docker exec vinfast-dtrack-apiserver sh -lc "command -v wget || true; command -v curl || true; wget -S -O- http://localhost:8080/api/version 2>&1 | head -40"
```

Evidence:

```text
/usr/bin/curl
sh: 1: wget: not found
```

Root cause: `dependencytrack/apiserver:latest` contains `curl` but not `wget`. The Docker healthcheck used `wget`, causing healthcheck failure even though the API server was running.

Fix applied:

- `docker-compose.dependency-track.yml`: changed API healthcheck from `wget -qO- ...` to `curl -fsS ...`.
- `docs/superpowers/plans/2026-06-21-dependency-track-lab-implementation.md`: updated plan to match the working healthcheck.

Retry command:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml up -d
```

Retry result: exit code 0.

Compose status:

```text
vinfast-dtrack-apiserver   dependencytrack/apiserver:latest   Up About a minute (healthy)   0.0.0.0:8080->8080/tcp
vinfast-dtrack-frontend    dependencytrack/frontend:latest    Up About a minute             0.0.0.0:8081->8080/tcp
vinfast-dtrack-postgres    postgres:16-alpine                 Up 35 minutes (healthy)       5432/tcp
```

Endpoint checks:

```text
API status: 200
UI status: 200
```

## Verification Facts

```text
Dependency-Track API URL: http://localhost:8080
Dependency-Track UI URL: http://localhost:8081
Dependency-Track containers: vinfast-dtrack-postgres, vinfast-dtrack-apiserver, vinfast-dtrack-frontend
API status: 200
UI status: 200
```

## Commit Status

Skipped commit: workspace is not a git repository.

## Concerns

- Plan originally specified `wget` healthcheck. Root cause investigation proved that is incompatible with current `dependencytrack/apiserver:latest`. Compose and plan were updated to `curl`.
- Docker Compose status also shows GitLab containers because both compose files use same project directory/project name and shared network. Not blocking; GitLab remains running.
