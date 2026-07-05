### Task 2: Add DefectDojo Trivy and Dependency-Check CI Jobs

**Files:**
- Modify: `ci-cd/.gitlab-ci.yml`

**Interfaces:**
- Consumes: existing `dependency-track-sbom` job and GitLab CI variables for DefectDojo.
- Produces: `trivy-fs-scan`, `dependency-check-scan`, and `defectdojo-import` jobs plus artifacts `trivy-fs-report.json` and `dependency-check-report.json`.

- [ ] **Step 1: Replace `ci-cd/.gitlab-ci.yml` with merged CI content**

Replace `ci-cd/.gitlab-ci.yml` with exact content:

```yaml
stages:
  - security

variables:
  DTRACK_PROJECT_NAME: "vinfast-wordpress"
  DTRACK_PROJECT_VERSION: "lab"
  DTRACK_FAIL_ON_SEVERITY: "HIGH"
  DTRACK_BOM_POLL_SECONDS: "300"
  DTRACK_BOM_POLL_INTERVAL_SECONDS: "10"
  DEFECTDOJO_PRODUCT_NAME: "vinfast-wordpress"
  DEFECTDOJO_ENGAGEMENT_NAME: "gitlab-ci"
  DEFECTDOJO_PRODUCT_TYPE_NAME: "Research and Development"
  DEFECTDOJO_MIN_SEVERITY: "High"

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
      upload_response="$(curl -sS --fail -X POST "${DTRACK_API_URL}/api/v1/bom" \
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
        token_response="$(curl -sS --fail "${DTRACK_API_URL}/api/v1/bom/token/${bom_token}" \
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

      project_json="$(curl -sS --fail -G "${DTRACK_API_URL}/api/v1/project/lookup" \
        -H "X-Api-Key: ${DTRACK_API_KEY}" \
        --data-urlencode "name=${DTRACK_PROJECT_NAME}" \
        --data-urlencode "version=${DTRACK_PROJECT_VERSION}")"
      project_uuid="$(echo "${project_json}" | jq -r '.uuid // empty')"
      if [ -z "${project_uuid}" ]; then
        echo "Could not resolve Dependency-Track project UUID"
        echo "${project_json}" | jq .
        exit 1
      fi

      metrics_json="$(curl -sS --fail "${DTRACK_API_URL}/api/v1/metrics/project/${project_uuid}/current" \
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

trivy-fs-scan:
  stage: security
  image:
    name: aquasec/trivy:latest
    entrypoint: [""]
  script:
    - trivy --version
    - trivy fs --format json --output trivy-fs-report.json --severity HIGH,CRITICAL --exit-code 0 --no-progress .
    - test -s trivy-fs-report.json
    - |
      high_count="$(grep -o '"Severity":"HIGH"' trivy-fs-report.json | wc -l | tr -d ' ')"
      critical_count="$(grep -o '"Severity":"CRITICAL"' trivy-fs-report.json | wc -l | tr -d ' ')"
      echo "Trivy gate metrics captured for DefectDojo import: high=${high_count}, critical=${critical_count}"
  artifacts:
    when: always
    expire_in: 7 days
    paths:
      - trivy-fs-report.json

dependency-check-scan:
  stage: security
  image:
    name: owasp/dependency-check:latest
    entrypoint: [""]
  script:
    - /usr/share/dependency-check/bin/dependency-check.sh --version
    - /usr/share/dependency-check/bin/dependency-check.sh --project "${DEFECTDOJO_PRODUCT_NAME}" --scan . --format JSON --out . --failOnCVSS 11
    - test -s dependency-check-report.json
    - |
      high_count="$(grep -o '"severity" : "HIGH"' dependency-check-report.json | wc -l | tr -d ' ')"
      critical_count="$(grep -o '"severity" : "CRITICAL"' dependency-check-report.json | wc -l | tr -d ' ')"
      echo "Dependency-Check gate metrics captured for DefectDojo import: high=${high_count}, critical=${critical_count}"
  artifacts:
    when: always
    expire_in: 7 days
    paths:
      - dependency-check-report.json

defectdojo-import:
  stage: security
  image: alpine:3.20
  needs:
    - job: trivy-fs-scan
      artifacts: true
    - job: dependency-check-scan
      artifacts: true
  before_script:
    - apk add --no-cache curl jq
  script:
    - |
      set -euo pipefail

      : "${DEFECTDOJO_URL:?Set DEFECTDOJO_URL in GitLab CI variables, for Docker Desktop use http://host.docker.internal:8082}"
      : "${DEFECTDOJO_API_KEY:?Set DEFECTDOJO_API_KEY in GitLab CI variables}"
      : "${DEFECTDOJO_PRODUCT_NAME:?Set DEFECTDOJO_PRODUCT_NAME}"
      : "${DEFECTDOJO_ENGAGEMENT_NAME:?Set DEFECTDOJO_ENGAGEMENT_NAME}"

      import_scan() {
        scan_type="$1"
        report_file="$2"
        echo "Importing ${scan_type}: ${report_file}"
        curl -sS --fail -X POST "${DEFECTDOJO_URL}/api/v2/reimport-scan/" \
          -H "Authorization: Token ${DEFECTDOJO_API_KEY}" \
          -F "scan_type=${scan_type}" \
          -F "file=@${report_file};type=application/json" \
          -F "product_name=${DEFECTDOJO_PRODUCT_NAME}" \
          -F "engagement_name=${DEFECTDOJO_ENGAGEMENT_NAME}" \
          -F "product_type_name=${DEFECTDOJO_PRODUCT_TYPE_NAME}" \
          -F "auto_create_context=true" \
          -F "active=true" \
          -F "verified=false" \
          -F "minimum_severity=${DEFECTDOJO_MIN_SEVERITY}" \
          -F "close_old_findings=true" | jq .
      }

      import_scan "Trivy Scan" "trivy-fs-report.json"
      import_scan "Dependency Check Scan" "dependency-check-report.json"
      echo "DefectDojo imports completed"

      trivy_high="$(grep -o '"Severity":"HIGH"' trivy-fs-report.json | wc -l | tr -d ' ')"
      trivy_critical="$(grep -o '"Severity":"CRITICAL"' trivy-fs-report.json | wc -l | tr -d ' ')"
      dc_high="$(grep -o '"severity" : "HIGH"' dependency-check-report.json | wc -l | tr -d ' ')"
      dc_critical="$(grep -o '"severity" : "CRITICAL"' dependency-check-report.json | wc -l | tr -d ' ')"
      echo "DefectDojo gate metrics after import: trivy_high=${trivy_high}, trivy_critical=${trivy_critical}, dependency_check_high=${dc_high}, dependency_check_critical=${dc_critical}"

      if [ "${trivy_critical}" -gt 0 ] || [ "${trivy_high}" -gt 0 ] || [ "${dc_critical}" -gt 0 ] || [ "${dc_high}" -gt 0 ]; then
        echo "DefectDojo fail gate triggered after import: HIGH/CRITICAL findings found"
        exit 1
      fi

      echo "DefectDojo fail gate passed after import"
  artifacts:
    when: always
    expire_in: 7 days
    paths:
      - trivy-fs-report.json
      - dependency-check-report.json
```

- [ ] **Step 2: Validate CI file exists and contains new jobs**

Run:

```powershell
Test-Path "ci-cd/.gitlab-ci.yml"
Select-String -Path "ci-cd/.gitlab-ci.yml" -Pattern "trivy-fs-scan|dependency-check-scan|defectdojo-import|reimport-scan|Trivy Scan|Dependency Check Scan|HIGH|CRITICAL"
```

Expected: `Test-Path` prints `True`; `Select-String` output includes all listed patterns.

- [ ] **Step 3: Commit if repository exists**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If output is `true`, run:

```powershell
git add ci-cd/.gitlab-ci.yml
git commit -m "feat: add DefectDojo security scan CI"
```

If command fails because workspace is not a git repo, record `Skipped commit: workspace is not a git repository` in final task notes.


