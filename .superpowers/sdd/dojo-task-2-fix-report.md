# DefectDojo Task 2 Fix Report

**Date:** 2026-06-21
**Status:** COMPLETE

## Files Changed

| File | Action |
|------|--------|
| `ci-cd/.gitlab-ci.yml` | Modified - removed grep from scanner jobs, replaced with jq in import job |
| `docs/superpowers/plans/2026-06-21-defectdojo-lab-implementation.md` | Modified - plan kept consistent with CI changes |

## Changes Applied

### 1. trivy-fs-scan (lines 104-111)
- Removed grep-based `high_count`/`critical_count` counting block.
- Job now only: run trivy scan, generate artifact, test file exists.
- No `exit 1` before import.

### 2. dependency-check-scan (lines 119-126)
- Removed grep-based `high_count`/`critical_count` counting block.
- Job now only: run dependency-check, generate artifact, test file exists.
- No `exit 1` before import.

### 3. defectdojo-import (lines 134-192)
- Replaced 4 grep-based severity counts with `jq` queries on JSON structure:
  - `trivy_high`: `[.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH")] | length`
  - `trivy_critical`: `[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length`
  - `dc_high`: `[.dependencies[]?.vulnerabilities[]? | select(.severity == "HIGH")] | length`
  - `dc_critical`: `[.dependencies[]?.vulnerabilities[]? | select(.severity == "CRITICAL")] | length`
- Fail gate preserved: `exit 1` if any count > 0.
- Import `reimport-scan` fields unchanged.
- `dependency-track-sbom` job unchanged.

## Validation Commands & Results

| Command | Expected | Result |
|---------|----------|--------|
| `Test-Path "ci-cd/.gitlab-ci.yml"` | True | True |
| `Select-String -Pattern "jq '\[\.Results"` | match | Matched line 175-176 |
| `Select-String -Pattern "jq '\[\.dependencies"` | match | Matched line 177-178 |
| `Select-String -Pattern "DefectDojo fail gate triggered after import"` | match | Matched line 182 |
| `Select-String -Pattern "trivy-fs-scan"` | match | Matched lines 104, 138 |
| `Select-String -Pattern "dependency-check-scan"` | match | Matched lines 119, 140 |
| `Select-String -Pattern "defectdojo-import"` | match | Matched line 134 |
| `Select-String -Pattern "reimport-scan"` | match | Matched line 157 |
| `Select-String -Pattern "grep -o.*Severity\|grep -o.*severity"` | no matches | No output (PASS) |

## Concerns

- OWASP Dependency-Check JSON report uses lowercase `"severity"` (not `"Severity"`). Plan and CI use `.severity` which matches the lowercase field. Verified the jq expression matches the actual JSON field name.
- Trivy JSON report uses uppercase `"Severity"`. Plan and CI use `.Severity` which matches. Verified.
- The `?` optional chaining in jq expressions handles missing/null fields gracefully (returns empty array, length 0).
- `dependency-track-sbom` job was NOT modified per requirements.

## Summary

Scanner jobs simplified to artifact-only; fail gate moved to `defectdojo-import` using jq JSON queries instead of fragile grep substring matching. All validations pass.
