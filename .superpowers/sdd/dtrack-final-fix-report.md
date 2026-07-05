# Dependency-Track Lab Final Fix Report

**Date:** 2026-06-21
**Workspace:** `g:\Cyber security\Vinfast`

---

## Finding 1: Add Stable ALPINE_SECRET_KEY

**Severity:** Medium. Missing secret key causes API key instability across restarts.

**Files changed:**
- `.env.dependency-track` — added `DTRACK_ALPINE_SECRET_KEY=296FB973E5852C49668F38215FF6F25233A6BDE7BE16534A02A6AC844A1A5F4A`
- `docker-compose.dependency-track.yml` — added `ALPINE_SECRET_KEY: ${DTRACK_ALPINE_SECRET_KEY}` under `dtrack-apiserver.environment`
- `docs/dependency-track/README.md` — added `## Environment Configuration` section documenting that `DTRACK_ALPINE_SECRET_KEY` must remain stable and changing it invalidates all existing API keys
- `docs/superpowers/plans/2026-06-21-dependency-track-lab-implementation.md` — updated env block and compose block for consistency

**Verification:**
- `Select-String` confirms `DTRACK_ALPINE_SECRET_KEY` in `.env.dependency-track` (line 11)
- `Select-String` confirms `ALPINE_SECRET_KEY` in compose (line 34)
- `docker compose config` renders `ALPINE_SECRET_KEY: 296FB973E5852C49668F38215FF6F25233A6BDE7BE16534A02A6AC844A1A5F4A`

---

## Finding 2: Restrict CORS Origin

**Severity:** Medium. Wildcard `*` CORS origin exposes API to any origin.

**Files changed:**
- `docker-compose.dependency-track.yml` — changed `ALPINE_CORS_ALLOW_ORIGIN` from `"*"` to `"http://localhost:${DTRACK_FRONTEND_PORT}"`
- `docs/dependency-track/README.md` — documented CORS restriction in Environment Configuration section
- `docs/superpowers/plans/2026-06-21-dependency-track-lab-implementation.md` — updated compose block for consistency

**Verification:**
- `Select-String` confirms `ALPINE_CORS_ALLOW_ORIGIN: "http://localhost:${DTRACK_FRONTEND_PORT}"` (line 36)
- `docker compose config` renders `ALPINE_CORS_ALLOW_ORIGIN: http://localhost:8081`

---

## Finding 3: Fix CI BOM Polling False-Pass Bug

**Severity:** High. `curl -sS` without `--fail` treats HTTP 4xx/5xx error JSON response bodies as valid data. When an error response lacks `.processing`, `jq -r '.processing // false'` returns `"false"`, making the poll loop exit as if processing completed successfully. The job then proceeds to metrics query on an unprocessed project, potentially passing the gate with zero findings when processing was never finished.

**Files changed:**
- `ci-cd/.gitlab-ci.yml` — added `--fail` to all four API curl calls:
  - Line 32: `curl -sS --fail -X POST .../api/v1/bom` (upload)
  - Line 49: `curl -sS --fail .../api/v1/bom/token/${bom_token}` (poll)
  - Line 64: `curl -sS --fail -G .../api/v1/project/lookup` (project UUID)
  - Line 75: `curl -sS --fail .../api/v1/metrics/project/${project_uuid}/current` (metrics)
- `docs/superpowers/plans/2026-06-21-dependency-track-lab-implementation.md` — updated all four curl invocations with `--fail` for consistency

Shell compatibility: `--fail` is POSIX, valid in Alpine. `-sS` flag combos are `-sS --fail`, which is valid. No bashisms introduced.

**Verification:**
- `Select-String` confirms four `--fail` occurrences in `ci-cd/.gitlab-ci.yml` (lines 32, 49, 64, 75)

---

## Finding 4: No Runner Tags

**Action:** Skipped. Local runner tag is unknown; adding arbitrary tags would break job matching. No changes.

---

## Finding 5: Image Version Pinning

**Action:** Not changed. Could not verify current valid Dependency-Track image tags without web access. Images remain `latest`. Mentioned in report.

Affected variables: `DTRACK_API_IMAGE=dependencytrack/apiserver:latest`, `DTRACK_FRONTEND_IMAGE=dependencytrack/frontend:latest`.

---

## Validation Commands Run

### 1. Docker Compose config validation
```
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml config
```
**Result:** Exit 0. Rendered config shows all three services (`dtrack-postgres`, `dtrack-apiserver`, `dtrack-frontend`), all expected environment variables including `ALPINE_SECRET_KEY` and `ALPINE_CORS_ALLOW_ORIGIN=http://localhost:8081`, joined to network `vinfast-cicd-lab`.

### 2. Select-String DTRACK_ALPINE_SECRET_KEY
```
Select-String -Path ".env.dependency-track" -Pattern "DTRACK_ALPINE_SECRET_KEY"
```
**Result:** Found at line 11: `DTRACK_ALPINE_SECRET_KEY=296FB973E5852C49668F38215FF6F25233A6BDE7BE16534A02A6AC844A1A5F4A`

### 3. Select-String ALPINE_SECRET_KEY
```
Select-String -Path "docker-compose.dependency-track.yml" -Pattern "ALPINE_SECRET_KEY"
```
**Result:** Found at line 34: `ALPINE_SECRET_KEY: ${DTRACK_ALPINE_SECRET_KEY}`

### 4. Select-String ALPINE_CORS_ALLOW_ORIGIN
```
Select-String -Path "docker-compose.dependency-track.yml" -Pattern "ALPINE_CORS_ALLOW_ORIGIN"
```
**Result:** Found at line 36: `ALPINE_CORS_ALLOW_ORIGIN: "http://localhost:${DTRACK_FRONTEND_PORT}"`

### 5. Select-String --fail
```
Select-String -Path "ci-cd/.gitlab-ci.yml" -Pattern "--fail"
```
**Result:** Found 4 occurrences (lines 32, 49, 64, 75) — one per API curl call

### 6. Select-String HIGH|CRITICAL
```
Select-String -Path "ci-cd/.gitlab-ci.yml" -Pattern "HIGH|CRITICAL"
```
**Result:** Found `DTRACK_FAIL_ON_SEVERITY: "HIGH"`, `critical=`/`high=` extraction, and both fail-gate conditionals intact (8 total matches)

---

## Concerns

1. **Image tags pinned to `latest`:** Not locked to known-good versions. A future breaking Dependency-Track release could break the lab. Recommend pinning when version tags can be verified.
2. **Secret key in plain text:** The lab secret key is committed in `.env.dependency-track`. This is acceptable for a local lab but production environments should use a secrets manager or vault.
3. **`--fail` behavior with redirects:** `--fail` combined with `-G` (project lookup) works correctly. `--fail` does not follow redirects silently — if Dependency-Track ever issues a 3xx redirect, the job fails. This is acceptable fail-safe behavior for this pipeline.
4. **No runner tags:** GitLab CI job has no `tags:` key. It will only execute on runners that pick up untagged jobs, or fail if all available runners require tags.
