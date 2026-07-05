### Task 1: Add DefectDojo Docker Compose Stack

**Files:**
- Create: `.env.defectdojo`
- Create: `docker-compose.defectdojo.yml`

**Interfaces:**
- Consumes: Docker Compose plugin and Docker network name `vinfast-cicd-lab`.
- Produces: Compose stack with services `dojo-postgres`, `dojo-valkey`, `dojo-initializer`, `dojo-uwsgi`, `dojo-celeryworker`, `dojo-celerybeat`, and `dojo-nginx`.

- [ ] **Step 1: Create `.env.defectdojo`**

Create `.env.defectdojo` with exact content:

```dotenv
DOJO_DJANGO_IMAGE=defectdojo/defectdojo-django:latest
DOJO_NGINX_IMAGE=defectdojo/defectdojo-nginx:latest
DOJO_POSTGRES_IMAGE=postgres:18.4-alpine
DOJO_VALKEY_IMAGE=valkey/valkey:9.0.4-alpine
DOJO_PORT=8082
DOJO_TLS_PORT=8444
DOJO_POSTGRES_DIR=./defectdojo/postgres
DOJO_VALKEY_DIR=./defectdojo/valkey
DOJO_MEDIA_DIR=./defectdojo/media
DOJO_DATABASE_NAME=defectdojo
DOJO_DATABASE_USER=defectdojo
DOJO_DATABASE_PASSWORD=defectdojo_lab_password
DD_DATABASE_HOST=dojo-postgres
DD_DATABASE_PORT=5432
DD_DATABASE_URL=postgresql://defectdojo:defectdojo_lab_password@dojo-postgres:5432/defectdojo
DD_CELERY_BROKER_URL=redis://dojo-valkey:6379/0
DD_CELERY_RESULT_BACKEND=redis://dojo-valkey:6379/0
DD_ALLOWED_HOSTS=localhost,127.0.0.1,dojo-nginx
DD_SITE_URL=http://localhost:8082
DD_SECRET_KEY=VF_DEFECTDOJO_LAB_SECRET_KEY_2026_CHANGE_ONLY_BEFORE_FIRST_BOOT
DD_CREDENTIAL_AES_256_KEY=0123456789abcdef0123456789abcdef
DD_INITIALIZE=true
DD_ADMIN_USER=admin
DD_ADMIN_MAIL=admin@example.local
DD_ADMIN_FIRST_NAME=Lab
DD_ADMIN_LAST_NAME=Admin
DD_DATABASE_READINESS_TIMEOUT=60
```

- [ ] **Step 2: Create `docker-compose.defectdojo.yml`**

Create `docker-compose.defectdojo.yml` with exact content:

```yaml
services:
  dojo-postgres:
    image: ${DOJO_POSTGRES_IMAGE}
    container_name: vinfast-dojo-postgres
    restart: unless-stopped
    environment:
      PGDATA: /var/lib/postgresql/data
      POSTGRES_DB: ${DOJO_DATABASE_NAME}
      POSTGRES_USER: ${DOJO_DATABASE_USER}
      POSTGRES_PASSWORD: ${DOJO_DATABASE_PASSWORD}
    volumes:
      - "${DOJO_POSTGRES_DIR}:/var/lib/postgresql/data"
    networks:
      - cicd-lab

  dojo-valkey:
    image: ${DOJO_VALKEY_IMAGE}
    container_name: vinfast-dojo-valkey
    restart: unless-stopped
    volumes:
      - "${DOJO_VALKEY_DIR}:/data"
    networks:
      - cicd-lab

  dojo-initializer:
    image: ${DOJO_DJANGO_IMAGE}
    container_name: vinfast-dojo-initializer
    depends_on:
      - dojo-postgres
    entrypoint:
      - /wait-for-it.sh
      - ${DD_DATABASE_HOST}:${DD_DATABASE_PORT}
      - --
      - /entrypoint-initializer.sh
    environment:
      DD_DATABASE_HOST: ${DD_DATABASE_HOST}
      DD_DATABASE_PORT: ${DD_DATABASE_PORT}
      DD_DATABASE_URL: ${DD_DATABASE_URL}
      DD_SECRET_KEY: ${DD_SECRET_KEY}
      DD_CREDENTIAL_AES_256_KEY: ${DD_CREDENTIAL_AES_256_KEY}
      DD_DATABASE_READINESS_TIMEOUT: ${DD_DATABASE_READINESS_TIMEOUT}
      DD_INITIALIZE: ${DD_INITIALIZE}
      DD_ADMIN_USER: ${DD_ADMIN_USER}
      DD_ADMIN_MAIL: ${DD_ADMIN_MAIL}
      DD_ADMIN_FIRST_NAME: ${DD_ADMIN_FIRST_NAME}
      DD_ADMIN_LAST_NAME: ${DD_ADMIN_LAST_NAME}
    networks:
      - cicd-lab

  dojo-uwsgi:
    image: ${DOJO_DJANGO_IMAGE}
    container_name: vinfast-dojo-uwsgi
    restart: unless-stopped
    depends_on:
      dojo-initializer:
        condition: service_completed_successfully
      dojo-postgres:
        condition: service_started
      dojo-valkey:
        condition: service_started
    entrypoint:
      - /wait-for-it.sh
      - ${DD_DATABASE_HOST}:${DD_DATABASE_PORT}
      - -t
      - "60"
      - --
      - /entrypoint-uwsgi.sh
    environment:
      DD_DEBUG: "False"
      DD_ALLOWED_HOSTS: ${DD_ALLOWED_HOSTS}
      DD_SITE_URL: ${DD_SITE_URL}
      DD_DATABASE_HOST: ${DD_DATABASE_HOST}
      DD_DATABASE_PORT: ${DD_DATABASE_PORT}
      DD_DATABASE_URL: ${DD_DATABASE_URL}
      DD_CELERY_BROKER_URL: ${DD_CELERY_BROKER_URL}
      DD_CELERY_RESULT_BACKEND: ${DD_CELERY_RESULT_BACKEND}
      DD_SECRET_KEY: ${DD_SECRET_KEY}
      DD_CREDENTIAL_AES_256_KEY: ${DD_CREDENTIAL_AES_256_KEY}
      DD_DATABASE_READINESS_TIMEOUT: ${DD_DATABASE_READINESS_TIMEOUT}
    volumes:
      - "${DOJO_MEDIA_DIR}:/app/media"
    networks:
      - cicd-lab

  dojo-celeryworker:
    image: ${DOJO_DJANGO_IMAGE}
    container_name: vinfast-dojo-celeryworker
    restart: unless-stopped
    depends_on:
      dojo-initializer:
        condition: service_completed_successfully
      dojo-postgres:
        condition: service_started
      dojo-valkey:
        condition: service_started
    entrypoint:
      - /wait-for-it.sh
      - ${DD_DATABASE_HOST}:${DD_DATABASE_PORT}
      - -t
      - "60"
      - --
      - /entrypoint-celery-worker.sh
    environment:
      DD_DATABASE_HOST: ${DD_DATABASE_HOST}
      DD_DATABASE_PORT: ${DD_DATABASE_PORT}
      DD_DATABASE_URL: ${DD_DATABASE_URL}
      DD_CELERY_BROKER_URL: ${DD_CELERY_BROKER_URL}
      DD_CELERY_RESULT_BACKEND: ${DD_CELERY_RESULT_BACKEND}
      DD_SECRET_KEY: ${DD_SECRET_KEY}
      DD_CREDENTIAL_AES_256_KEY: ${DD_CREDENTIAL_AES_256_KEY}
      DD_DATABASE_READINESS_TIMEOUT: ${DD_DATABASE_READINESS_TIMEOUT}
    volumes:
      - "${DOJO_MEDIA_DIR}:/app/media"
    networks:
      - cicd-lab

  dojo-celerybeat:
    image: ${DOJO_DJANGO_IMAGE}
    container_name: vinfast-dojo-celerybeat
    restart: unless-stopped
    depends_on:
      dojo-initializer:
        condition: service_completed_successfully
      dojo-postgres:
        condition: service_started
      dojo-valkey:
        condition: service_started
    entrypoint:
      - /wait-for-it.sh
      - ${DD_DATABASE_HOST}:${DD_DATABASE_PORT}
      - -t
      - "60"
      - --
      - /entrypoint-celery-beat.sh
    environment:
      DD_DATABASE_HOST: ${DD_DATABASE_HOST}
      DD_DATABASE_PORT: ${DD_DATABASE_PORT}
      DD_DATABASE_URL: ${DD_DATABASE_URL}
      DD_CELERY_BROKER_URL: ${DD_CELERY_BROKER_URL}
      DD_CELERY_RESULT_BACKEND: ${DD_CELERY_RESULT_BACKEND}
      DD_SECRET_KEY: ${DD_SECRET_KEY}
      DD_CREDENTIAL_AES_256_KEY: ${DD_CREDENTIAL_AES_256_KEY}
      DD_DATABASE_READINESS_TIMEOUT: ${DD_DATABASE_READINESS_TIMEOUT}
    networks:
      - cicd-lab

  dojo-nginx:
    image: ${DOJO_NGINX_IMAGE}
    container_name: vinfast-dojo-nginx
    restart: unless-stopped
    depends_on:
      dojo-uwsgi:
        condition: service_started
    environment:
      NGINX_METRICS_ENABLED: "false"
      DD_UWSGI_HOST: dojo-uwsgi
      DD_UWSGI_PORT: "3031"
    ports:
      - "${DOJO_PORT}:8080"
      - "${DOJO_TLS_PORT}:8443"
    volumes:
      - "${DOJO_MEDIA_DIR}:/usr/share/nginx/html/media"
    networks:
      - cicd-lab

networks:
  cicd-lab:
    name: vinfast-cicd-lab
```

- [ ] **Step 3: Validate Compose config**

Run:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml config
```

Expected: command exits 0 and rendered config includes all seven `dojo-*` services.

- [ ] **Step 4: Commit if repository exists**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If output is `true`, run:

```powershell
git add .env.defectdojo docker-compose.defectdojo.yml
git commit -m "feat: add DefectDojo compose stack"
```

If command fails because workspace is not a git repo, record `Skipped commit: workspace is not a git repository` in final task notes.


