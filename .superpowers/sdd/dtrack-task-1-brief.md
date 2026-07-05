### Task 1: Add Dependency-Track Docker Compose Stack

**Files:**
- Create: `.env.dependency-track`
- Create: `docker-compose.dependency-track.yml`

**Interfaces:**
- Consumes: Docker Compose plugin and Docker network name `vinfast-cicd-lab`.
- Produces: Compose stack with services `dtrack-postgres`, `dtrack-apiserver`, and `dtrack-frontend`.

- [ ] **Step 1: Create `.env.dependency-track`**

Create `.env.dependency-track` with exact content:

```dotenv
DTRACK_API_IMAGE=dependencytrack/apiserver:latest
DTRACK_FRONTEND_IMAGE=dependencytrack/frontend:latest
DTRACK_POSTGRES_IMAGE=postgres:16-alpine
DTRACK_API_PORT=8080
DTRACK_FRONTEND_PORT=8081
DTRACK_POSTGRES_USER=dtrack
DTRACK_POSTGRES_PASSWORD=dtrack_lab_password
DTRACK_POSTGRES_DB=dtrack
DTRACK_POSTGRES_DIR=./dependency-track/postgres
DTRACK_API_DATA_DIR=./dependency-track/apiserver
DTRACK_JAVA_OPTIONS=-Xmx2048m
```

- [ ] **Step 2: Create `docker-compose.dependency-track.yml`**

Create `docker-compose.dependency-track.yml` with exact content:

```yaml
services:
  dtrack-postgres:
    image: ${DTRACK_POSTGRES_IMAGE}
    container_name: vinfast-dtrack-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${DTRACK_POSTGRES_USER}
      POSTGRES_PASSWORD: ${DTRACK_POSTGRES_PASSWORD}
      POSTGRES_DB: ${DTRACK_POSTGRES_DB}
    volumes:
      - "${DTRACK_POSTGRES_DIR}:/var/lib/postgresql/data"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DTRACK_POSTGRES_USER} -d ${DTRACK_POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 10
    networks:
      - cicd-lab

  dtrack-apiserver:
    image: ${DTRACK_API_IMAGE}
    container_name: vinfast-dtrack-apiserver
    restart: unless-stopped
    depends_on:
      dtrack-postgres:
        condition: service_healthy
    environment:
      JAVA_OPTIONS: ${DTRACK_JAVA_OPTIONS}
      ALPINE_DATABASE_MODE: external
      ALPINE_DATABASE_DRIVER: org.postgresql.Driver
      ALPINE_DATABASE_URL: jdbc:postgresql://dtrack-postgres:5432/${DTRACK_POSTGRES_DB}
      ALPINE_DATABASE_USERNAME: ${DTRACK_POSTGRES_USER}
      ALPINE_DATABASE_PASSWORD: ${DTRACK_POSTGRES_PASSWORD}
      ALPINE_CORS_ENABLED: "true"
      ALPINE_CORS_ALLOW_ORIGIN: "*"
      ALPINE_CORS_ALLOW_METHODS: "GET, POST, PUT, DELETE, OPTIONS"
      ALPINE_CORS_ALLOW_HEADERS: "Origin, Content-Type, Authorization, X-Requested-With, Content-Length, Accept, X-Api-Key"
    ports:
      - "${DTRACK_API_PORT}:8080"
    volumes:
      - "${DTRACK_API_DATA_DIR}:/data"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:8080/api/version >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 20
      start_period: 120s
    networks:
      - cicd-lab

  dtrack-frontend:
    image: ${DTRACK_FRONTEND_IMAGE}
    container_name: vinfast-dtrack-frontend
    restart: unless-stopped
    depends_on:
      dtrack-apiserver:
        condition: service_healthy
    environment:
      API_BASE_URL: http://localhost:${DTRACK_API_PORT}
    ports:
      - "${DTRACK_FRONTEND_PORT}:8080"
    networks:
      - cicd-lab

networks:
  cicd-lab:
    name: vinfast-cicd-lab
```

- [ ] **Step 3: Validate Compose config**

Run:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml config
```

Expected: command exits 0 and rendered config includes services `dtrack-postgres`, `dtrack-apiserver`, and `dtrack-frontend`.

- [ ] **Step 4: Commit if repository exists**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If output is `true`, run:

```powershell
git add .env.dependency-track docker-compose.dependency-track.yml
git commit -m "feat: add Dependency-Track compose stack"
```

If command fails because workspace is not a git repo, record `Skipped commit: workspace is not a git repository` in final task notes.


