# Test Project Rename Design

Date: 2026-07-17

## Goal

Rename the standalone WordPress test application from `ci-cd` to `test_project` locally and in local GitLab, while preserving its Git history, pipeline configuration, CI/CD variables, runner assignment, and project history.

## Current State

Main DevSecOps repository:

```text
G:\Cyber security\Vinfast
```

Standalone application repository nested locally but ignored by the main repository:

```text
G:\Cyber security\Vinfast\ci-cd
```

Current application remote:

```text
http://localhost:8929/test-cicd/test-cicd-project.git
```

The application repository owns its WordPress source, Dockerfile, and `.gitlab-ci.yml`. The main `Vinfast` repository owns DevSecOps infrastructure, scripts, and documentation.

## Target State

Local application repository:

```text
G:\Cyber security\Vinfast\test_project
```

GitLab group remains:

```text
test-cicd
```

GitLab project name and path become:

```text
test_project
```

New application remote:

```text
http://localhost:8929/test-cicd/test_project.git
```

Target layout:

```text
G:\Cyber security\Vinfast\
  docs\
  infra\
  scripts\
  docker-compose.*.yml
  test_project\
    .git\
    .gitlab-ci.yml
    Dockerfile
    WordPress source
```

`test_project` remains an independent Git repository. It is not tracked as files or a submodule by the parent `Vinfast` repository.

## Migration Order

1. Start GitLab and verify the current project opens.
2. In GitLab, rename project **Name** and **Path** from `test-cicd-project` to `test_project` while keeping namespace `test-cicd`.
3. Verify GitLab exposes the new clone URL:

   ```text
   http://localhost:8929/test-cicd/test_project.git
   ```

4. Update the application repository `origin` remote to the new URL.
5. Verify fetch access through the new remote before renaming the local folder.
6. Rename local folder from `ci-cd` to `test_project`.
7. Replace parent `.gitignore` entry `ci-cd/` with `test_project/`.
8. Update active operator documentation and current Harbor/ArgoCD plans/specs to use `test_project` instead of `ci-cd`.
9. Keep historical implementation reports unchanged where they document commands and paths used at that time.
10. Validate both repository boundaries and remote configuration.

## Files to Modify

Main repository:

- `.gitignore`
- `README.md`
- `docs/dependency-track/README.md`
- `docs/defectdojo/README.md`
- `docs/harbor/README.md`
- `docs/argocd/README.md`
- `docs/superpowers/specs/2026-07-05-harbor-registry-design.md`
- `docs/superpowers/specs/2026-07-05-argocd-gitops-design.md` where the old name appears
- `docs/superpowers/plans/2026-07-05-harbor-registry-implementation.md`
- `docs/superpowers/plans/2026-07-05-argocd-gitops-implementation.md` where the old name appears

Local filesystem:

- Rename `G:\Cyber security\Vinfast\ci-cd` to `G:\Cyber security\Vinfast\test_project`.

Application repository:

- Update Git remote `origin` only.
- Preserve `.gitlab-ci.yml`, source code, commit history, branches, and tags.

GitLab:

- Rename existing project name/path to `test_project` under group `test-cicd`.

## Data and History Preservation

Renaming the existing GitLab project preserves:

- Repository commit history.
- Branches and tags.
- Pipeline history.
- CI/CD variables.
- Runner assignment.
- Issues and project settings.

No new GitLab project is created. No force push or history rewrite is needed.

## Failure Handling

### New GitLab URL is not reachable

Do not rename the local folder yet. Confirm the project path in GitLab and test:

```powershell
git -C .\ci-cd ls-remote http://localhost:8929/test-cicd/test_project.git
```

### Old remote redirects

GitLab may temporarily redirect the old project path. Update `origin` explicitly instead of relying on redirects:

```powershell
git remote set-url origin http://localhost:8929/test-cicd/test_project.git
```

### Local rename fails

Stop processes with working directories inside `ci-cd`, close terminals or editors holding files, then retry. Do not delete the folder.

### Parent repository starts tracking application files

Verify `.gitignore` contains:

```gitignore
test_project/
```

Then run `git status --short` from `Vinfast`. No files under `test_project/` should appear.

## Validation

From the renamed application repository:

```powershell
git status --short
git remote -v
git ls-remote origin
```

Expected remote:

```text
http://localhost:8929/test-cicd/test_project.git
```

From the main repository:

```powershell
git status --short
git check-ignore -v test_project
Test-Path .\ci-cd
Test-Path .\test_project
```

Expected:

```text
test_project is ignored by the parent repository
ci-cd does not exist
test_project exists
```

Search active files for stale references:

```powershell
rg -n "ci-cd|test-cicd-project" README.md .gitignore docs --glob "!docs/superpowers/plans/2026-06-21-*" --glob "!.superpowers/**"
```

Expected: no stale active references requiring migration.

## Success Criteria

- Existing GitLab project is available at `test-cicd/test_project`.
- Local application repository is located at `G:\Cyber security\Vinfast\test_project`.
- Application `origin` uses `http://localhost:8929/test-cicd/test_project.git`.
- Git history, branches, tags, pipeline history, CI/CD variables, and runner assignment remain intact.
- Main `Vinfast` repository ignores `test_project/`.
- Active docs refer to `test_project`, not `ci-cd`.
- Application pipeline remains defined in `test_project/.gitlab-ci.yml`.
- No source files are copied into the parent repository history.
