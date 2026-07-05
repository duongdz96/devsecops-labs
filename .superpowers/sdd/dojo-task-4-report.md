# DefectDojo Task 4 Report

## STATUS: DONE

## Commands Run and Results

Command:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml up -d
```

Result: exit code 0. DefectDojo stack started.

Command:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml ps
```

Result:

```text
vinfast-dojo-celerybeat     defectdojo/defectdojo-django:latest   Up 10 minutes
vinfast-dojo-celeryworker   defectdojo/defectdojo-django:latest   Up 10 minutes
vinfast-dojo-nginx          defectdojo/defectdojo-nginx:latest    Up 9 minutes              0.0.0.0:8082->8080/tcp
vinfast-dojo-postgres       postgres:18.4-alpine                  Up 12 minutes (healthy)   5432/tcp
vinfast-dojo-uwsgi          defectdojo/defectdojo-django:latest   Up 10 minutes (healthy)
vinfast-dojo-valkey         valkey/valkey:9.0.4-alpine            Up 12 minutes (healthy)   6379/tcp
```

Command:

```powershell
Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8082" -TimeoutSec 10
```

Result:

```text
UI status: 200
```

Command:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml logs dojo-initializer | Select-String "Admin password:"
```

Result:

```text
vinfast-dojo-initializer  | Admin password: 4jRCSlpbLzT0zcpU0QR1SI
```

## Verification Facts

```text
DefectDojo URL: http://localhost:8082
DefectDojo containers: vinfast-dojo-postgres, vinfast-dojo-valkey, vinfast-dojo-uwsgi, vinfast-dojo-celeryworker, vinfast-dojo-celerybeat, vinfast-dojo-nginx
UI status: 200
Admin password retrieval: logs contain Admin password
```

## Commit Status

Skipped commit: workspace is not a git repository.

## Self-Review Notes

- Long-running DefectDojo services are up.
- Postgres, Valkey, and uWSGI healthchecks report healthy.
- DefectDojo UI responds with HTTP 200.
- Admin password can be retrieved from initializer logs.
