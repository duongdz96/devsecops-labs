### Task 5: Start GitLab and Verify Boot

**Files:**
- Modify: none

**Interfaces:**
- Consumes: Compose config and README from previous tasks.
- Produces: Running GitLab service reachable at `http://localhost:8929`.

- [ ] **Step 1: Start GitLab service**

Run:

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml up -d gitlab
```

Expected: command exits 0 and creates/runs container `vinfast-gitlab`.

- [ ] **Step 2: Check Compose service status**

Run:

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml ps
```

Expected: `gitlab` service appears with state `running` or `Up`.

- [ ] **Step 3: Wait for GitLab HTTP endpoint**

Run this until it returns an HTTP status code:

```powershell
try { (Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8929/users/sign_in" -TimeoutSec 10).StatusCode } catch { $_.Exception.Message }
```

Expected final output: `200`.

- [ ] **Step 4: Show root password**

Run:

```powershell
.\scripts\gitlab-show-root-password.ps1
```

Expected: script prints password line plus login URL.

- [ ] **Step 5: Record verification result**

Record these facts in final task notes:

```text
GitLab URL: http://localhost:8929
GitLab SSH port: 2224
GitLab container: vinfast-gitlab
HTTP sign-in status: 200
```


