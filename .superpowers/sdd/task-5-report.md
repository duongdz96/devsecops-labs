# Task 5 Report: Start GitLab and Verify Boot

## STATUS: DONE

## Commands Run and Results

Command:

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml up -d gitlab
```

Result: exit code 0. Container `vinfast-gitlab` started.

Command:

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml ps
```

Result:

```text
NAME             IMAGE                     COMMAND                  SERVICE   CREATED         STATUS                   PORTS
vinfast-gitlab   gitlab/gitlab-ce:latest   "/assets/init-contai…"   gitlab    9 minutes ago   Up 8 minutes (healthy)   80/tcp, 443/tcp, 0.0.0.0:8929->8929/tcp, 0.0.0.0:2224->22/tcp
```

Command:

```powershell
try { (Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8929/users/sign_in" -TimeoutSec 10).StatusCode } catch { $_.Exception.Message }
```

Result:

```text
HTTP sign-in status: 200
```

Command:

```powershell
.\scripts\gitlab-show-root-password.ps1
```

Result: script printed login URL, username `root`, and initial root password.

## Verification Facts

```text
GitLab URL: http://localhost:8929
GitLab SSH port: 2224
GitLab container: vinfast-gitlab
HTTP sign-in status: 200
```

## Commit Status

Skipped commit: workspace is not a git repository.

## Self-Review Notes

- GitLab service is running and healthy.
- HTTP sign-in endpoint returns 200.
- Initial root password retrieval works.
- Runner was not registered in this task.
