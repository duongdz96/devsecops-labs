# Harbor Registry Lab

Harbor adds a local container registry to the CI/CD security lab. GitLab CI builds the WordPress image from `ci-cd/Dockerfile` and pushes it to Harbor.

This lab proves:

```text
GitLab CI -> Docker build -> Harbor push -> image visible in Harbor UI
```

This phase uses:

- Harbor UI and registry: `http://localhost:8083`
- Harbor project: `vinfast`
- Harbor image: `wordpress`
- GitLab: `http://localhost:8929`
- GitLab CI target: `ci-cd` WordPress folder
- Harbor config: `infra/harbor/harbor.yml`

## Requirements

- Docker Desktop or Docker Engine with Docker Compose plugin.
- WSL2 Linux shell for the official Harbor installer on Windows.
- GitLab already running at `http://localhost:8929` when testing CI push.
- Port `8083` available on host.
- About 8GB RAM and 4 CPU.

Harbor is an HTTP registry in this lab. It is not production hardened.

## Resource Strategy

This host has about 8GB RAM. Do not run every lab stack at once.

For Harbor UI setup:

- Harbor must run.
- GitLab can be stopped until CI testing starts.
- Dependency-Track and DefectDojo can be stopped.
- k3d and ArgoCD should stay stopped until the next phase.

For CI push testing:

- Harbor must run.
- GitLab and GitLab Runner must run.
- Dependency-Track and DefectDojo can be stopped if memory is tight.

Stop optional stacks:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml down
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml down
```

## Harbor Config

Editable config lives at:

```text
infra/harbor/harbor.yml
```

Important values:

```yaml
hostname: host.docker.internal
http:
  port: 8083
harbor_admin_password: Harbor12345
data_volume: ./data
```

Harbor still listens on host port `8083`, so the browser can open `http://localhost:8083`. `hostname` is `host.docker.internal` so Docker-in-Docker and k3d clients receive a token realm they can reach.

Generated installer output is ignored by Git:

```text
infra/harbor/common/
infra/harbor/data/
infra/harbor/docker-compose.yml
infra/harbor/install.sh
infra/harbor/prepare
```

Do not edit generated `common/` files by hand. Change `harbor.yml`, then rerun the Harbor prepare/install step.

## Install Harbor

Use official Harbor installer. On Windows, run these commands from WSL2 because Harbor installer scripts and `prepare` are Linux executables.

From WSL2 shell, move to this repo. Example if repo is on drive `G:`:

```bash
cd "/mnt/g/Cyber security/Vinfast"
```

Download Harbor offline installer into `infra/harbor`:

```bash
cd infra/harbor
curl -L -o harbor-offline-installer-v2.11.1.tgz https://github.com/goharbor/harbor/releases/download/v2.11.1/harbor-offline-installer-v2.11.1.tgz
tar -xzf harbor-offline-installer-v2.11.1.tgz --strip-components=1
```

Keep repo config as source of truth:

```bash
cp harbor.yml harbor.yml.lab
cp harbor.yml.lab harbor.yml
```

Prepare and install Harbor:

```bash
sudo ./prepare
sudo ./install.sh
```

If `sudo docker` cannot reach Docker Desktop, enable Docker Desktop WSL integration for the WSL distro, then retry.

## Start Harbor

After installer generates `docker-compose.yml`, start Harbor from `infra/harbor`:

```powershell
docker compose -f .\infra\harbor\docker-compose.yml up -d
```

Check containers:

```powershell
docker compose -f .\infra\harbor\docker-compose.yml ps
```

Expected services include:

```text
log
registry
registryctl
postgresql
core
portal
jobservice
redis
proxy
```

Open Harbor:

```text
http://localhost:8083
```

Login:

```text
Username: admin
Password: Harbor12345
```

Change admin password after first login if you want to keep the lab data.

## Create Project

In Harbor UI:

1. Login as `admin`.
2. Open **Projects**.
3. Click **New Project**.
4. Set **Project Name** to `vinfast`.
5. Keep project private unless you deliberately want anonymous pulls.
6. Click **OK**.

## Create Robot Account

In Harbor UI:

1. Open project `vinfast`.
2. Open **Robot Accounts**.
3. Click **New Robot Account**.
4. Name it `gitlab-ci`.
5. Set expiration for lab preference.
6. Grant repository permissions:
   - `Pull`
   - `Push`
7. Save.
8. Copy robot username and token.

Store token only in GitLab CI/CD variables. Do not commit it.

Robot username often looks like:

```text
robot$vinfast+gitlab-ci
```

## Configure Docker Desktop Insecure Registry

Docker host must trust Harbor over HTTP.

In Docker Desktop:

1. Open **Settings**.
2. Open **Docker Engine**.
3. Add insecure registry:

```json
{
  "insecure-registries": [
    "localhost:8083",
    "host.docker.internal:8083"
  ]
}
```

If existing JSON has other keys, keep them and add only `insecure-registries`.

Apply and restart Docker Desktop.

Verify host Docker login:

```powershell
docker login localhost:8083
```

Use Harbor `admin` or robot credentials.

## GitLab CI Variables

In GitLab project for `ci-cd`, open **Settings > CI/CD > Variables** and add:

| Variable | Value |
| --- | --- |
| `HARBOR_URL` | `host.docker.internal:8083` |
| `HARBOR_PROJECT` | `vinfast` |
| `HARBOR_IMAGE_NAME` | `wordpress` |
| `HARBOR_ROBOT_USER` | Robot username from Harbor |
| `HARBOR_ROBOT_TOKEN` | Robot token from Harbor |

Mark `HARBOR_ROBOT_TOKEN` as masked if GitLab accepts the token format. If masked value rules reject it, keep it protected from logs and never echo it.

Use `host.docker.internal:8083` so GitLab Runner job containers and Docker-in-Docker can reach Harbor through Docker Desktop host networking.

## CI Behavior

File `ci-cd/.gitlab-ci.yml` contains job `harbor-build-push`.

Job behavior:

1. Starts Docker-in-Docker with insecure registry `host.docker.internal:8083`.
2. Logs in to Harbor with robot credentials.
3. Builds the Docker image from the `ci-cd` project root.
4. Tags the image:

   ```text
   host.docker.internal:8083/vinfast/wordpress:${CI_COMMIT_SHORT_SHA}
   host.docker.internal:8083/vinfast/wordpress:latest
   ```

5. Pushes both tags.
6. Fails if login, build, or push fails.

Existing security jobs stay in stage `security` after the build stage:

- `dependency-track-sbom`
- `trivy-fs-scan`
- `dependency-check-scan`
- `defectdojo-import`

## Run Pipeline

1. Ensure Harbor is running.
2. Ensure GitLab and GitLab Runner are running:

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml up -d gitlab gitlab-runner
```

3. Push or copy `ci-cd/.gitlab-ci.yml` into the GitLab `ci-cd` project.
4. Configure GitLab CI variables listed above.
5. Run pipeline.
6. Confirm `harbor-build-push` passes.

## Verify Image in Harbor

In Harbor UI:

1. Open `http://localhost:8083`.
2. Login.
3. Open project `vinfast`.
4. Open repository `wordpress`.
5. Confirm tags exist:
   - commit SHA tag
   - `latest`

Verify pull from host:

```powershell
docker pull localhost:8083/vinfast/wordpress:latest
```

If the image was pushed by CI as `host.docker.internal:8083/vinfast/wordpress:latest`, pull from host with `localhost:8083/vinfast/wordpress:latest`; Harbor stores repository path and tag, not the client hostname.

## Stop Harbor

Stop containers but keep Harbor data:

```powershell
docker compose -f .\infra\harbor\docker-compose.yml down
```

Start again:

```powershell
docker compose -f .\infra\harbor\docker-compose.yml up -d
```

## Delete Harbor Data

This deletes projects, robot accounts, images, database, and registry blobs.

```powershell
docker compose -f .\infra\harbor\docker-compose.yml down
Remove-Item -Recurse -Force .\infra\harbor\data
```

Run installer again if generated config was removed.

## Troubleshooting

### Port 8083 already in use

Check port owner:

```powershell
netstat -ano | Select-String ":8083"
```

Stop the conflicting service or change `http.port` in `infra/harbor/harbor.yml`, then rerun Harbor prepare/install.

### Browser cannot open Harbor UI

Check containers:

```powershell
docker compose -f .\infra\harbor\docker-compose.yml ps
```

Follow logs:

```powershell
docker compose -f .\infra\harbor\docker-compose.yml logs -f proxy core portal
```

### Docker reports HTTP registry error

Typical error:

```text
server gave HTTP response to HTTPS client
```

Fix Docker Desktop insecure registry config for both `localhost:8083` and `host.docker.internal:8083`, restart Docker Desktop, then retry:

```powershell
docker login localhost:8083
docker login host.docker.internal:8083
```

### GitLab CI cannot reach Harbor

Use this GitLab CI variable:

```text
HARBOR_URL=host.docker.internal:8083
```

The CI job's Docker-in-Docker service starts with:

```text
--insecure-registry=host.docker.internal:8083
```

If using a non-Docker Desktop Linux host, replace `host.docker.internal` with an address reachable from GitLab Runner job containers, then update both `HARBOR_URL` and the DinD insecure registry command in `.gitlab-ci.yml`.

### Robot login fails

Check:

- `HARBOR_ROBOT_USER` matches exact robot username.
- `HARBOR_ROBOT_TOKEN` is copied exactly.
- Robot account is not expired.
- Robot account has `Pull` and `Push` permissions in project `vinfast`.
- Project name is exactly `vinfast`.

### Push denied

Check project and permissions:

1. Harbor project `vinfast` exists.
2. Robot account belongs to project `vinfast`.
3. Robot account has push permission.
4. CI pushes to `host.docker.internal:8083/vinfast/wordpress`.

### Low memory

Symptoms:

- Harbor services restart.
- GitLab Runner jobs hang.
- Docker Desktop becomes slow.

Reduce load:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml down
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml down
```

Run only Harbor + GitLab + GitLab Runner for CI push testing.
