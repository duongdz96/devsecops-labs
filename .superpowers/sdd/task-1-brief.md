### Task 1: Compose GitLab and Runner Services

**Files:**
- Create: `.env.gitlab`
- Create: `docker-compose.gitlab.yml`

**Interfaces:**
- Consumes: Docker Compose on host.
- Produces: Compose project with service names `gitlab` and `gitlab-runner`; later scripts call `docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml ...`.

- [ ] **Step 1: Create `.env.gitlab`**

Create `.env.gitlab` with exact content:

```dotenv
GITLAB_IMAGE=gitlab/gitlab-ce:latest
GITLAB_RUNNER_IMAGE=gitlab/gitlab-runner:latest
GITLAB_HTTP_PORT=8929
GITLAB_SSH_PORT=2224
GITLAB_HOSTNAME=localhost
GITLAB_CONFIG_DIR=./gitlab/config
GITLAB_LOGS_DIR=./gitlab/logs
GITLAB_DATA_DIR=./gitlab/data
GITLAB_RUNNER_CONFIG_DIR=./gitlab-runner/config
```

- [ ] **Step 2: Create `docker-compose.gitlab.yml`**

Create `docker-compose.gitlab.yml` with exact content:

```yaml
services:
  gitlab:
    image: ${GITLAB_IMAGE}
    container_name: vinfast-gitlab
    restart: unless-stopped
    hostname: ${GITLAB_HOSTNAME}
    shm_size: "256m"
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'http://${GITLAB_HOSTNAME}:${GITLAB_HTTP_PORT}'
        gitlab_rails['gitlab_shell_ssh_port'] = ${GITLAB_SSH_PORT}
        puma['worker_processes'] = 2
        sidekiq['max_concurrency'] = 10
        prometheus_monitoring['enable'] = false
    ports:
      - "${GITLAB_HTTP_PORT}:${GITLAB_HTTP_PORT}"
      - "${GITLAB_SSH_PORT}:22"
    volumes:
      - "${GITLAB_CONFIG_DIR}:/etc/gitlab"
      - "${GITLAB_LOGS_DIR}:/var/log/gitlab"
      - "${GITLAB_DATA_DIR}:/var/opt/gitlab"
    networks:
      - cicd-lab

  gitlab-runner:
    image: ${GITLAB_RUNNER_IMAGE}
    container_name: vinfast-gitlab-runner
    restart: unless-stopped
    depends_on:
      - gitlab
    volumes:
      - "${GITLAB_RUNNER_CONFIG_DIR}:/etc/gitlab-runner"
    networks:
      - cicd-lab

networks:
  cicd-lab:
    name: vinfast-cicd-lab
```

- [ ] **Step 3: Validate Compose config**

Run:

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml config
```

Expected: command exits 0 and rendered config includes services `gitlab` and `gitlab-runner`.

- [ ] **Step 4: Commit if repository exists**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If output is `true`, run:

```powershell
git add .env.gitlab docker-compose.gitlab.yml
git commit -m "feat: add GitLab CI lab compose config"
```

If command fails because workspace is not a git repo, record `Skipped commit: workspace is not a git repository` in final task notes.


