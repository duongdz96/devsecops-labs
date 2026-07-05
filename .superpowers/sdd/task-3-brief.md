### Task 3: Add Docker-in-Docker Demo Pipeline

**Files:**
- Create: `examples/gitlab-ci-dind/.gitlab-ci.yml`
- Create: `examples/gitlab-ci-dind/Dockerfile`

**Interfaces:**
- Consumes: Registered runner from Task 2.
- Produces: Demo project content that proves GitLab CI can run Docker-in-Docker image builds.

- [ ] **Step 1: Create `examples/gitlab-ci-dind/Dockerfile`**

Create `examples/gitlab-ci-dind/Dockerfile` with exact content:

```dockerfile
FROM alpine:3.20
RUN adduser -D appuser
USER appuser
CMD ["sh", "-c", "echo GitLab CI DinD lab image works"]
```

- [ ] **Step 2: Create `examples/gitlab-ci-dind/.gitlab-ci.yml`**

Create `examples/gitlab-ci-dind/.gitlab-ci.yml` with exact content:

```yaml
stages:
  - test
  - build

variables:
  DOCKER_HOST: tcp://docker:2375
  DOCKER_TLS_CERTDIR: ""
  DOCKER_DRIVER: overlay2

check-docker-client:
  stage: test
  image: docker:24
  services:
    - name: docker:24-dind
      alias: docker
      command: ["--tls=false"]
  script:
    - docker version
    - docker info

build-demo-image:
  stage: build
  image: docker:24
  services:
    - name: docker:24-dind
      alias: docker
      command: ["--tls=false"]
  script:
    - docker build -t vinfast/gitlab-ci-dind-demo:${CI_COMMIT_SHORT_SHA} .
    - docker run --rm vinfast/gitlab-ci-dind-demo:${CI_COMMIT_SHORT_SHA}
```

- [ ] **Step 3: Validate demo files exist**

Run:

```powershell
Test-Path "examples/gitlab-ci-dind/.gitlab-ci.yml"
Test-Path "examples/gitlab-ci-dind/Dockerfile"
```

Expected output:

```text
True
True
```

- [ ] **Step 4: Commit if repository exists**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If output is `true`, run:

```powershell
git add examples/gitlab-ci-dind/.gitlab-ci.yml examples/gitlab-ci-dind/Dockerfile
git commit -m "feat: add GitLab CI Docker-in-Docker demo"
```

If command fails because workspace is not a git repo, record `Skipped commit: workspace is not a git repository` in final task notes.


