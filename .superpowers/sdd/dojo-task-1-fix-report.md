# DefectDojo Task 1 -- Fix Report

**STATUS: PASS** -- All 9 review findings fixed. Compose config validates successfully. All Select-String checks positive.

**Date:** 2026-06-21
**Workspace:** `g:\Cyber security\Vinfast`

---

## Files Changed

| File | Changes |
| --- | --- |
| `g:\Cyber security\Vinfast\.env.defectdojo` | Fernet key replaced, DOJO_TLS_PORT removed |
| `g:\Cyber security\Vinfast\docker-compose.defectdojo.yml` | restart policy, 3 healthchecks, service_healthy deps, TLS port removed |
| `g:\Cyber security\Vinfast\docs\superpowers\plans\2026-06-21-defectdojo-lab-implementation.md` | Updated .env and compose YAML blocks + removed HTTPS port ref |

---

## Fix Details

### 1. DD_CREDENTIAL_AES_256_KEY -- FIXED

- **Before:** `0123456789abcdef0123456789abcdef` (32 hex chars, invalid Fernet key)
- **After:** `c8tXh6q2JXhz1Csyd0I0m2gdxJQZWyEoJMNpA8Y2k4o=` (44 char URL-safe base64, valid Fernet key)

### 2. dojo-initializer restart policy -- FIXED

- Added `restart: "no"` to `dojo-initializer` service. Initializer is a one-shot migration task; restart loop would be harmful.

### 3. Postgres healthcheck -- ADDED

```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U ${DOJO_DATABASE_USER} -d ${DOJO_DATABASE_NAME}"]
  interval: 10s
  timeout: 5s
  retries: 5
```

### 4. Valkey healthcheck -- ADDED

```yaml
healthcheck:
  test: ["CMD", "valkey-cli", "ping"]
  interval: 10s
  timeout: 5s
  retries: 5
```

### 5. uWSGI healthcheck -- ADDED

```yaml
healthcheck:
  test: ["CMD-SHELL", "python3 -c \"import socket; s=socket.socket(); s.settimeout(3); s.connect(('127.0.0.1',3031)); s.close()\""]
  interval: 30s
  timeout: 10s
  retries: 3
```

### 6. Backend dependency conditions -- FIXED

- `dojo-uwsgi`, `dojo-celeryworker`, `dojo-celerybeat` dependencies on `dojo-postgres` and `dojo-valkey` changed from `condition: service_started` to `condition: service_healthy`.
- This ensures backends only start when Postgres accepts connections and Valkey responds to pings.

### 7. Nginx dependency condition -- FIXED

- `dojo-nginx` dependency on `dojo-uwsgi` changed from `condition: service_started` to `condition: service_healthy`.
- This ensures nginx only starts when uWSGI is actually listening on port 3031.

### 8. TLS port mapping -- REMOVED

- Removed `"${DOJO_TLS_PORT}:8443"` from `dojo-nginx` ports.
- Removed `DOJO_TLS_PORT=8444` from `.env.defectdojo`.
- No TLS cert configuration present; exposing TLS port without cert config is misleading.

### 9. Postgres 18.4 -- PRESERVED

- `DOJO_POSTGRES_IMAGE=postgres:18.4-alpine` kept unchanged. Upstream DefectDojo compose uses it.

---

## Validation Results

### Command: `docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml config`

**Exit code: 0.** Rendered config includes all 7 services with healthchecks, correct deps, and single port mapping.

Key rendered highlights:
- `dojo-postgres`: healthcheck `pg_isready -U defectdojo -d defectdojo` present
- `dojo-valkey`: healthcheck `valkey-cli ping` present
- `dojo-initializer`: `restart: "no"` present
- `dojo-uwsgi`: healthcheck `python3 -c ... socket ... 127.0.0.1:3031` present; deps on postgres/valkey show `condition: service_healthy`
- `dojo-nginx`: dep on uwsgi shows `condition: service_healthy`; only port `8082:8080` mapped (no TLS port)
- `DD_CREDENTIAL_AES_256_KEY: c8tXh6q2JXhz1Csyd0I0m2gdxJQZWyEoJMNpA8Y2k4o=` in all services that consume it

### Select-String: `.env.defectdojo`

| Pattern | Result |
| --- | --- |
| `DD_CREDENTIAL_AES_256_KEY` | Found: valid Fernet key on line 20 |
| `DOJO_TLS_PORT` | **NOT found** (correctly removed) |

### Select-String: `docker-compose.defectdojo.yml`

| Pattern | Result |
| --- | --- |
| `restart: "no"` | Found: line 38 (dojo-initializer) |
| `pg_isready` | Found: line 14 (dojo-postgres healthcheck) |
| `valkey-cli ping` | Found (dojo-valkey healthcheck) |
| `service_healthy` | Found: 8 occurrences (deps on postgres, valkey, and nginx dep on uwsgi) |
| `3031` | Found: lines 92 (healthcheck), 186 (DD_UWSGI_PORT) |
| `DOJO_TLS_PORT` | **NOT found** (correctly removed) |

---

## Concerns

None. All 9 fixes applied cleanly, compose config validates, and plan docs stay consistent with actual files.

---

## Plan Consistency

`docs/superpowers/plans/2026-06-21-defectdojo-lab-implementation.md` updated:

- `.env.defectdojo` code block: Fernet key changed, `DOJO_TLS_PORT` removed
- `docker-compose.defectdojo.yml` code block: all 9 fixes reflected
- HTTPS passthrough port reference `8444` removed from requirements section
