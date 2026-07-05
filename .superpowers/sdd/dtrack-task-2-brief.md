### Task 2: Add GitLab CI SBOM Upload and Fail Gate

**Files:**
- Create: `ci-cd/.gitlab-ci.yml`

**Interfaces:**
- Consumes: Dependency-Track API URL and API key from GitLab CI variables.
- Produces: `dependency-track-sbom` job that creates `gl-sbom.cdx.json`, uploads it, polls BOM processing, and fails on `HIGH` or `CRITICAL` metrics.

- [ ] **Step 1: Create `ci-cd/.gitlab-ci.yml`**

Create `ci-cd/.gitlab-ci.yml` with exact content:

```yaml
stages:
  - security

variables:
  DTRACK_PROJECT_NAME: "vinfast-wordpress"
  DTRACK_PROJECT_VERSION: "lab"
  DTRACK_FAIL_ON_SEVERITY: "HIGH"
  DTRACK_BOM_POLL_SECONDS: "300"
  DTRACK_BOM_POLL_INTERVAL_SECONDS: "10"

dependency-track-sbom:
  stage: security
  image: alpine:3.20
  before_script:
    - apk add --no-cache bash curl jq
    - curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
    - syft version
  script:
    - |
      set -euo pipefail

      : "${DTRACK_API_URL:?Set DTRACK_API_URL in GitLab CI variables, for Docker Desktop use http://host.docker.internal:8080}"
      : "${DTRACK_API_KEY:?Set DTRACK_API_KEY in GitLab CI variables}"
      : "${DTRACK_PROJECT_NAME:?Set DTRACK_PROJECT_NAME}"
      : "${DTRACK_PROJECT_VERSION:?Set DTRACK_PROJECT_VERSION}"

      echo "Generating CycloneDX SBOM for ${DTRACK_PROJECT_NAME}:${DTRACK_PROJECT_VERSION}"
      syft dir:. -o cyclonedx-json=gl-sbom.cdx.json
      test -s gl-sbom.cdx.json

      echo "Uploading SBOM to Dependency-Track at ${DTRACK_API_URL}"
      upload_response="$(curl -sS -X POST "${DTRACK_API_URL}/api/v1/bom" \
        -H "X-Api-Key: ${DTRACK_API_KEY}" \
        -F "autoCreate=true" \
        -F "projectName=${DTRACK_PROJECT_NAME}" \
        -F "projectVersion=${DTRACK_PROJECT_VERSION}" \
        -F "bom=@gl-sbom.cdx.json")"

      echo "${upload_response}" | jq .
      bom_token="$(echo "${upload_response}" | jq -r '.token // empty')"
      if [ -z "${bom_token}" ]; then
        echo "Dependency-Track upload did not return BOM token"
        exit 1
      fi

      deadline=$(( $(date +%s) + ${DTRACK_BOM_POLL_SECONDS} ))
      processing="true"
      while [ "$(date +%s)" -lt "${deadline}" ]; do
        token_response="$(curl -sS "${DTRACK_API_URL}/api/v1/bom/token/${bom_token}" \
          -H "X-Api-Key: ${DTRACK_API_KEY}")"
        processing="$(echo "${token_response}" | jq -r '.processing // false')"
        echo "BOM processing: ${processing}"
        if [ "${processing}" = "false" ]; then
          break
        fi
        sleep "${DTRACK_BOM_POLL_INTERVAL_SECONDS}"
      done

      if [ "${processing}" != "false" ]; then
        echo "Timed out waiting for Dependency-Track BOM processing"
        exit 1
      fi

      project_json="$(curl -sS -G "${DTRACK_API_URL}/api/v1/project/lookup" \
        -H "X-Api-Key: ${DTRACK_API_KEY}" \
        --data-urlencode "name=${DTRACK_PROJECT_NAME}" \
        --data-urlencode "version=${DTRACK_PROJECT_VERSION}")"
      project_uuid="$(echo "${project_json}" | jq -r '.uuid // empty')"
      if [ -z "${project_uuid}" ]; then
        echo "Could not resolve Dependency-Track project UUID"
        echo "${project_json}" | jq .
        exit 1
      fi

      metrics_json="$(curl -sS "${DTRACK_API_URL}/api/v1/metrics/project/${project_uuid}/current" \
        -H "X-Api-Key: ${DTRACK_API_KEY}")"
      echo "${metrics_json}" | jq .

      critical="$(echo "${metrics_json}" | jq -r '.critical // 0')"
      high="$(echo "${metrics_json}" | jq -r '.high // 0')"
      echo "Dependency-Track gate metrics: critical=${critical}, high=${high}, threshold=${DTRACK_FAIL_ON_SEVERITY}"

      if [ "${critical}" -gt 0 ]; then
        echo "Fail gate triggered: CRITICAL vulnerable components found"
        exit 1
      fi

      if [ "${DTRACK_FAIL_ON_SEVERITY}" = "HIGH" ] && [ "${high}" -gt 0 ]; then
        echo "Fail gate triggered: HIGH vulnerable components found"
        exit 1
      fi

      echo "Dependency-Track fail gate passed"
  artifacts:
    when: always
    expire_in: 7 days
    paths:
      - gl-sbom.cdx.json
```

- [ ] **Step 2: Validate CI file exists**

Run:

```powershell
Test-Path "ci-cd/.gitlab-ci.yml"
```

Expected output:

```text
True
```

- [ ] **Step 3: Check required variable names are present**

Run:

```powershell
Select-String -Path "ci-cd/.gitlab-ci.yml" -Pattern "DTRACK_API_URL|DTRACK_API_KEY|DTRACK_PROJECT_NAME|DTRACK_PROJECT_VERSION|DTRACK_FAIL_ON_SEVERITY"
```

Expected: output contains all five variable names.

- [ ] **Step 4: Commit if repository exists**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If output is `true`, run:

```powershell
git add ci-cd/.gitlab-ci.yml
git commit -m "feat: add Dependency-Track SBOM gate to CI"
```

If command fails because workspace is not a git repo, record `Skipped commit: workspace is not a git repository` in final task notes.


