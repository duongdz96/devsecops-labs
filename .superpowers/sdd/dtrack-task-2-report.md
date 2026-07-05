# Dependency-Track Task 2 Report

## STATUS: DONE

## Files Created/Modified
- Created: `ci-cd/.gitlab-ci.yml`

## Validation Commands and Results

### Step 2: Validate CI file exists
**Command:** `Test-Path "ci-cd/.gitlab-ci.yml"`
**Result:** `True`

### Step 3: Check required variable names are present
**Command:** `Select-String -Path "ci-cd/.gitlab-ci.yml" -Pattern "DTRACK_API_URL|DTRACK_API_KEY|DTRACK_PROJECT_NAME|DTRACK_PROJECT_VERSION|DTRACK_FAIL_ON_SEVERITY"`
**Result:** All 5 variables found (23 matches total)

### Commit Status
**Command:** `git rev-parse --is-inside-work-tree`
**Result:** `fatal: not a git repository (or any of the parent directories): .git`
**Action:** Skipped commit — workspace is not a git repository.

## Self-Review Notes
- File content matches the spec exactly.
- SBOM job creates `gl-sbom.cdx.json`, uploads to Dependency-Track, polls BOM processing token, resolves project UUID, fetches metrics, and fails on CRITICAL or HIGH vulnerabilities.
- `DTRACK_API_URL` and `DTRACK_API_KEY` are declared as GitLab CI variables (not hardcoded).
- Five variables defined: `DTRACK_PROJECT_NAME`, `DTRACK_PROJECT_VERSION`, `DTRACK_FAIL_ON_SEVERITY`, `DTRACK_BOM_POLL_SECONDS`, `DTRACK_BOM_POLL_INTERVAL_SECONDS`.
- Fail gate logic: any CRITICAL triggers exit 1; if `DTRACK_FAIL_ON_SEVERITY=HIGH`, any HIGH also triggers exit 1.
- Artifacts (`gl-sbom.cdx.json`) preserved for 7 days on any outcome.
