# DevSecOps Labs

A local lab that models a controlled software supply chain for a WordPress application, from source code to a workload running on Kubernetes.

Lab objectives:

- build CI/CD with GitLab;
- store and separate candidate and release artifacts with Harbor;
- scan source code, dependencies, and container images;
- generate and manage SBOMs;
- aggregate security findings;
- block releases that fail policy;
- deploy releases through GitOps with ArgoCD and k3d;
- trace a running image back to its Git commit.

> This is a learning environment on a personal machine, not a production-ready configuration.

## Architecture overview

```text
Developer pushes source
        │
        ▼
GitLab CI/CD + GitLab Runner
        │
        ├── Validate source, secrets, and policy
        ├── Run unit tests
        └── Build the Docker image once
                 │
                 ▼
        Harbor: devsecops-candidate
                 │
                 ├── Semgrep SAST
                 ├── Gitleaks secret scan
                 ├── Trivy image scan
                 ├── Dependency-Check
                 ├── Syft generates a CycloneDX SBOM
                 ├── Dependency-Track stores and analyzes the SBOM
                 └── DefectDojo aggregates scanner reports
                              │
                              ▼
                    Security policy gate
                       │               │
                     fail             pass
                       │               │
                block release          ▼
                              Harbor: devsecops-lab
                              preserves the image digest
                                       │
                                       ▼
                              GitOps repository
                                       │
                                       ▼
                                    ArgoCD
                                       │
                                       ▼
                              k3d / Kubernetes
                                       │
                                       ▼
                               WordPress + MySQL
```

## Repositories in the lab

| Repository/directory | Role |
| --- | --- |
| `DevSecOps-labs` | Contains infrastructure configuration, Compose stacks, scripts, documentation, and Kubernetes manifests. |
| `test_project/` | Contains the WordPress source, Dockerfile, scanner scripts, policy tests, and `.gitlab-ci.yml`. It is an independent Git repository; its GitLab path is `test-cicd/test_project`. |
| `devsecops-gitops/` | Contains the desired Kubernetes state and ArgoCD Application. Its contents are pushed to the GitLab project `gitops/devsecops-gitops`. |

Separation of responsibilities:

```text
test_project       produces the artifact
Harbor             stores candidate and release artifacts
devsecops-gitops   selects the artifact and describes how to run it
ArgoCD             syncs GitOps state into Kubernetes
Kubernetes         runs WordPress and MySQL
```

## Components and purpose

| Component | Purpose |
| --- | --- |
| **GitLab CE** | Stores source repositories, pipeline history, variables, and the audit trail. |
| **GitLab Runner** | Executes CI jobs in containers, including Docker-in-Docker for image builds. |
| **Harbor** | Stores OCI images and separates unapproved candidates from deployable releases. |
| **Gitleaks** | Detects secrets or credentials committed to source code. |
| **Semgrep** | Performs static source analysis with PHP and OWASP rules. |
| **Trivy** | Scans the exact candidate container image by immutable digest. |
| **OWASP Dependency-Check** | Detects CVEs associated with source dependencies. |
| **Syft** | Generates a CycloneDX Software Bill of Materials from the candidate image. |
| **Dependency-Track** | Stores SBOMs, maintains a component inventory, and continuously analyzes software supply-chain risk. |
| **DefectDojo** | Aggregates Trivy, Dependency-Check, and Semgrep reports for centralized finding management. |
| **Policy engine** | Normalizes findings and blocks HIGH/CRITICAL issues without a valid risk acceptance. |
| **Crane** | Copies an approved candidate image to the release project without rebuilding it. |
| **k3d** | Runs a lightweight local Kubernetes cluster inside Docker. |
| **ArgoCD** | Watches the GitOps repository and automatically syncs, prunes, and self-heals Kubernetes resources. |

## How the pipeline works

The pipeline in `test_project/.gitlab-ci.yml` has five stages:

```text
validate → test → build-candidate → security → promote
```

### `validate`

- validates the risk-acceptance policy;
- lints all PHP source files;
- scans for secrets with Gitleaks;
- runs Semgrep and stores the SAST report.

### `test`

Runs unit tests for the finding normalizer and policy engine, including valid acceptances, forbidden wildcards, and expired acceptances.

### `build-candidate`

GitLab Runner checks out the exact `test_project` commit, builds the Docker image once, and pushes it to:

```text
host.docker.internal:8083/devsecops-candidate/wordpress:<CI_COMMIT_SHA>
```

After the push, the pipeline resolves the manifest digest and passes an immutable candidate reference to downstream jobs.

### `security`

Security jobs operate on the same candidate artifact:

- Trivy scans the container image;
- Syft creates an SBOM and uploads it to Dependency-Track;
- Dependency-Check creates JSON and XML reports;
- DefectDojo receives scanner reports;
- the policy engine normalizes findings from Trivy, Dependency-Check, and Semgrep.

Dependency-Track and DefectDojo store, analyze, and manage security data. The deterministic pass/fail decision belongs to `security-policy-gate` in the pipeline.

### `promote`

When all mandatory controls succeed, Crane copies the image to:

```text
host.docker.internal:8083/devsecops-lab/wordpress:<CI_COMMIT_SHA>
```

The image is not rebuilt. The pipeline verifies:

```text
candidate digest == release digest
```

The artifact that was scanned is therefore the artifact that gets released.

## Security policy gate

In normal mode, the gate blocks every `HIGH` or `CRITICAL` finding without an exact risk acceptance.

A risk acceptance must include:

- scanner;
- finding ID;
- component;
- severity;
- owner;
- reason;
- ticket/reference;
- expiration date.

Normal flow:

```text
HIGH/CRITICAL finding remains unaddressed or unaccepted
→ security-policy-gate fails
→ promote-release does not run
```

The pipeline supports `LAB_PROMOTION_BYPASS=true` so the promotion and ArgoCD mechanics can be tested with an intentionally vulnerable image. With this bypass, the gate still runs and still reports failure, but the pipeline may continue.

> An artifact promoted through the lab bypass has not satisfied the security policy and must not be considered production-approved.

## Candidate and release artifacts

Harbor uses two projects:

| Project | Meaning |
| --- | --- |
| `devsecops-candidate` | A newly built image that has not passed every control. |
| `devsecops-lab` | An image promoted so that GitOps can select it for deployment. |

Each function uses a separate least-privilege robot account:

- candidate robot: Pull + Push on the candidate project;
- release promoter: Pull on candidate, Pull + Push on release;
- k3d robot: Pull only on release.

## How GitOps and ArgoCD work

The GitOps repository does not build images. It selects a release artifact through the `image` field in the Kubernetes Deployment:

```yaml
image: host.docker.internal:8083/devsecops-lab/wordpress@sha256:<digest>
```

The YAML manifests also describe:

- WordPress and MySQL Deployments;
- Services and internal DNS;
- persistent storage for MySQL;
- health probes;
- CPU and memory requests and limits;
- references to Kubernetes Secrets;
- the ArgoCD source repository, branch, and manifest path.

ArgoCD continuously compares the desired state in Git with the actual cluster state. When Git changes, ArgoCD syncs the workload. When someone changes the cluster directly, `selfHeal` restores the declared state.

The release digest is currently updated through a controlled manual step:

```text
promote-release
→ read RELEASE_IMAGE from release.env
→ update the GitOps manifest
→ commit and push the GitOps repository
→ ArgoCD syncs
```

The pipeline does not yet commit a new digest to the GitOps repository automatically.

## Artifact traceability

The artifact can be traced across the full system:

```text
test_project Git commit
→ Harbor candidate tag
→ candidate manifest digest
→ security reports and SBOM
→ Harbor release with the same digest
→ GitOps image@digest
→ Kubernetes pod imageID
```

Primary evidence sources:

- the pipeline and `candidate.env` / `release.env` artifacts in GitLab;
- candidate and release artifacts in Harbor;
- the SBOM project/version in Dependency-Track;
- scanner findings in DefectDojo;
- the `image:` value in the GitOps manifest;
- ArgoCD Application status;
- the Kubernetes Deployment and pod `imageID`.

## Lab limitations

- Harbor uses HTTP as an insecure registry.
- GitLab Runner uses privileged Docker-in-Docker.
- Kubernetes Secrets are bootstrapped outside Git.
- GitOps digest updates are not automated.
- Image signing, admission verification, and SLSA provenance are not integrated.
- The lab bypass tests deployment flow only; it does not replace remediation.

## Detailed documentation

- [Harbor registry and artifact promotion](docs/harbor/README.md)
- [Dependency-Track and SBOMs](docs/dependency-track/README.md)
- [DefectDojo and finding aggregation](docs/defectdojo/README.md)
- [ArgoCD and GitOps on k3d](docs/argocd/README.md)
- [Clean rebuild runbook](docs/clean-rebuild/README.md)
