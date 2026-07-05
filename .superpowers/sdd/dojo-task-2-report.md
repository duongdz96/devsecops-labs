# Dojo Task 2 Report

## STATUS: DONE

## Files Created/Modified
- Modified: `G:\Cyber security\Vinfast\ci-cd\.gitlab-ci.yml`

## Changes
Replaced existing CI file (which only had `dependency-track-sbom`) with merged content adding:
- `DEFECTDOJO_PRODUCT_NAME`, `DEFECTDOJO_ENGAGEMENT_NAME`, `DEFECTDOJO_PRODUCT_TYPE_NAME`, `DEFECTDOJO_MIN_SEVERITY` variables
- `trivy-fs-scan` job (Trivy filesystem scan, generates `trivy-fs-report.json`)
- `dependency-check-scan` job (OWASP Dependency-Check, generates `dependency-check-report.json`)
- `defectdojo-import` job (imports both reports via `reimport-scan` API, then fails on HIGH/CRITICAL)

All four jobs sit in the `security` stage. Scanner jobs use `--exit-code 0` so reports are always produced. `defectdojo-import` depends on both scanner jobs via `needs: ... artifacts: true`.

## Validation Commands and Results

**Test-Path:**
```
PS> Test-Path "ci-cd/.gitlab-ci.yml"
True
```

**Select-String (pattern coverage):**
```
trivy-fs-scan          : True
dependency-check-scan  : True
defectdojo-import      : True
reimport-scan          : True
Trivy Scan             : True
Dependency Check Scan  : True
HIGH                   : True
CRITICAL               : True
```

## Commit Status
Skipped commit: workspace is not a git repository

## Self-Review Notes
- All 8 patterns from Step 2 present in the file
- `dependency-track-sbom` job preserved as-is (Task 2 does not change it)
- DefectDojo variables (`DEFECTDOJO_*`) in `variables` block match exact values from brief
- `defectdojo-import` gate fails after import, matching resolved decision (scanner jobs do not fail before import)
- No other files modified
