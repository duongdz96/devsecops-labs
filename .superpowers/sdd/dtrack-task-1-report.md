# Task 1 Report: Add Dependency-Track Docker Compose Stack

## STATUS: DONE

## Files Created
- `g:\Cyber security\Vinfast\.env.dependency-track`
- `g:\Cyber security\Vinfast\docker-compose.dependency-track.yml`

## Validation
Command run:
```
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml config
```
Result: exit 0. Rendered config includes all 3 services (`dtrack-postgres`, `dtrack-apiserver`, `dtrack-frontend`) with correct environment variables, healthchecks, ports, volumes, and network (`vinfast-cicd-lab`).

## Commit
Skipped. `git rev-parse --is-inside-work-tree` failed (exit 128): workspace is not a git repository.

## Self-Review Notes
- All variable references in compose file match keys defined in `.env.dependency-track`.
- Network `cicd-lab` uses external name `vinfast-cicd-lab` as specified.
- Postgres healthcheck uses `pg_isready` with correct user/db from env vars.
- API server healthcheck uses `wget` against `/api/version` with start_period 120s.
- Frontend depends on apiserver being healthy before starting.
- Data directories use relative paths `./dependency-track/postgres` and `./dependency-track/apiserver` — Docker will auto-create these on first run.
