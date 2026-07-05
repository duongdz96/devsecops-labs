# ArgoCD GitOps Lab Design

Date: 2026-07-05
Branch: `feature/harbor-argocd-gitops`

## Goal

Stand up a lightweight Kubernetes cluster (k3d) and ArgoCD, then wire a GitOps loop: GitLab CI builds the `ci-cd` WordPress image, pushes it to Harbor, ArgoCD Image Updater notices the new tag and updates a separate manifest repo, and ArgoCD syncs that repo's manifests to deploy WordPress on the k3d cluster.

This phase depends on Harbor already existing (see `2026-07-05-harbor-registry-design.md`) as the image source ArgoCD Image Updater watches and the cluster pulls from.

## Constraints

- Host has about 8GB RAM and 4 CPU.
- Build one component at a time; k3d + ArgoCD adds a fifth stack on top of GitLab, Dependency-Track, DefectDojo, and Harbor — do not run all five simultaneously.
- Work happens on branch `feature/harbor-argocd-gitops`; do not merge into or modify `main`.
- Documentation must be written under `docs/`.
- Cluster tooling: k3d (k3s running as Docker containers), not Docker Desktop's built-in Kubernetes and not kind.
- ArgoCD reads from a separate Git repo (not this `Vinfast` repo) containing plain Kubernetes manifests for WordPress.
- That manifest repo is a new local Git repo, pushed to a new project on the local GitLab lab instance (`http://localhost:8929`).
- Image tag updates in the manifest repo are automated via ArgoCD Image Updater, not manual edits.
- Harbor is treated as an insecure (HTTP) registry, consistent with the Harbor design; k3d and ArgoCD Image Updater must both be configured to trust it.

## Recommended Approach

### Cluster

- Use `k3d` to create a single-node lab cluster (1 server, 0 extra agents — keep it minimal for 8GB RAM).
- Configure k3d's embedded registries config (`k3d registry` / `registries.yaml`) to mark the Harbor host:port as an insecure/plain-HTTP registry so containerd inside k3d nodes can pull from it.
- No Ingress controller needed for this phase; access ArgoCD UI and the deployed WordPress service via `kubectl port-forward` or a k3d `--port` mapping at cluster-create time.

### ArgoCD

- Install ArgoCD into the k3d cluster using the official installation manifests (`kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml` equivalent, pinned to a specific released version rather than `stable` for reproducibility) into namespace `argocd`.
- Retrieve the initial admin password from the `argocd-initial-admin-secret` Kubernetes secret (documented step, not automated).
- Expose ArgoCD UI via `kubectl port-forward svc/argocd-server -n argocd 8084:443` (host port `8084`, chosen to avoid collision with Harbor's `8083`).

### ArgoCD Image Updater

- Install ArgoCD Image Updater into the same cluster/namespace via its official manifests.
- Configure it with:
  - Pull-registry credentials for Harbor (robot account, insecure/HTTP registry flag).
  - Write access to the manifest Git repo (SSH deploy key with write permission, generated for this lab and added to the GitLab manifest project).
  - An `argocd-image-updater.argoproj.io/image-list` annotation on the target ArgoCD Application pointing at `vinfast/wordpress` in Harbor, with update strategy `latest` (or digest-based) so it picks up new pushes.
- Image Updater commits tag updates directly to the manifest repo's tracked branch; ArgoCD then syncs on the next poll (or auto-sync if enabled).

### Manifest repo

- New local Git repo (e.g. `g:\Cyber security\vinfast-gitops`), containing plain Kubernetes YAML (no Helm/Kustomize for this first pass, to keep it simple):
  - `wordpress/deployment.yaml` — Deployment referencing `HARBOR_URL/vinfast/wordpress:<tag>`.
  - `wordpress/service.yaml` — ClusterIP or NodePort Service exposing WordPress.
  - `wordpress/mysql-deployment.yaml` + `wordpress/mysql-service.yaml` if WordPress needs its own DB in-cluster (existing `ci-cd` Dockerfile/compose to be checked at implementation time for whether DB is bundled or external; if the current WordPress container expects an external DB, a minimal MySQL Deployment is added here since the k3d cluster is a separate environment from the existing `docker-compose` WordPress setup).
- Pushed to a new GitLab project, e.g. `gitops/vinfast-wordpress`, on the local GitLab instance.
- An ArgoCD `Application` resource (also stored in this manifest repo or applied directly — decide at plan time) points ArgoCD at this repo/path/branch, targeting the `default` namespace in the k3d cluster, with automated sync enabled.

## Data Flow

1. User creates k3d cluster and installs ArgoCD + Image Updater.
2. User creates the manifest repo, pushes initial WordPress manifests to a new GitLab project.
3. User creates an ArgoCD `Application` pointing at that repo/path.
4. ArgoCD performs initial sync, deploying WordPress (and MySQL if needed) to the k3d cluster.
5. Later, GitLab CI (from the Harbor phase) builds and pushes a new WordPress image tag to Harbor.
6. ArgoCD Image Updater polls Harbor, detects the new tag, updates the image reference in the manifest repo, and commits/pushes that change.
7. ArgoCD detects the new commit and syncs the updated Deployment to the cluster.
8. User verifies the new pod is running the updated image via `kubectl` or the ArgoCD UI.

## Documentation

Create `docs/argocd/README.md` with:

- k3d installation/prerequisites and cluster-create command.
- Insecure-registry config for k3d to reach Harbor.
- ArgoCD install command (pinned version), namespace, initial admin password retrieval.
- ArgoCD UI access via port-forward.
- ArgoCD Image Updater install and configuration (Harbor credentials, Git write credentials, annotation syntax).
- Manifest repo structure and how it was created/pushed to GitLab.
- ArgoCD `Application` definition and how to apply it.
- End-to-end verification steps: trigger a Harbor push, confirm Image Updater commits a manifest change, confirm ArgoCD syncs, confirm the running pod's image tag changed.
- Teardown commands (`k3d cluster delete`, removing the manifest repo project if desired).
- 8GB RAM notes — stop other stacks (GitLab, Dependency-Track, DefectDojo, Harbor) as needed when running k3d; k3d itself also consumes RAM even before ArgoCD.
- Troubleshooting for cluster networking, insecure-registry pulls, and Image Updater Git push failures.

## Files to Create or Modify

- Create `scripts/k3d-create-cluster.ps1` (or documented inline command) — cluster bootstrap with registries config.
- Create `docs/argocd/README.md` — install and usage guide.
- Create manifest repo (outside this repository, at `g:\Cyber security\vinfast-gitops`) containing WordPress/MySQL manifests and the ArgoCD `Application` definition.
- No changes to `ci-cd/.gitlab-ci.yml` in this phase (the Harbor build/push job from the prior phase is the trigger; no new CI job is required since Image Updater polls Harbor directly).

## Success Criteria

- `k3d cluster list` shows the lab cluster running.
- ArgoCD UI reachable via port-forward at `https://localhost:8084`, login with admin and the retrieved initial password.
- ArgoCD Image Updater pod running in namespace `argocd` (or wherever installed) without crash-looping.
- Manifest repo exists locally, pushed to a new GitLab project on the lab instance.
- ArgoCD `Application` shows `Synced`/`Healthy` status for the WordPress deployment.
- WordPress pod(s) reachable inside the cluster (verified via `kubectl port-forward` to the WordPress Service).
- After a new image is pushed to Harbor, Image Updater commits a tag update to the manifest repo within its poll interval, and ArgoCD subsequently syncs the new tag to the running Deployment — verified by checking the pod's image digest/tag before and after.
- Documentation under `docs/argocd/README.md` explains install, usage, and the end-to-end verification steps above.

## Resource Strategy

Because host has 8GB RAM:

- k3d cluster + ArgoCD + Image Updater is its own resource pool, separate from the Docker Compose stacks.
- Stop GitLab, Dependency-Track, DefectDojo, and Harbor when not actively testing the full push-to-sync chain; keep only what's needed for the step being tested (e.g. only Harbor + k3d/ArgoCD when testing the Image Updater loop).
- If the host struggles to run k3d alongside even one other stack, fall back to running k3d cluster with 0 extra agents (already the plan) and consider trimming ArgoCD's default resource requests if pods stay pending.

## Risks and Mitigations

- k3d nodes need to trust Harbor as an insecure registry, which is a different mechanism from the Docker daemon or DinD insecure-registry config used in the Harbor phase.
  - Mitigation: document k3d's `registries.yaml` mechanism explicitly and verify with a manual `kubectl run` pulling a Harbor-hosted image before wiring ArgoCD.
- ArgoCD Image Updater needs write access to the manifest Git repo, meaning a credential (SSH key or token) is stored in-cluster as a Secret.
  - Mitigation: use a dedicated deploy key scoped to only the manifest repo/project, not a broader GitLab token; document this scoping choice.
- Existing `ci-cd` WordPress image may assume an external database reachable at a specific host/port (from the Docker Compose environment), which won't exist as-is inside the k3d cluster.
  - Mitigation: inspect `ci-cd`'s existing Dockerfile/entrypoint at implementation time; add an in-cluster MySQL Deployment and matching environment variables/Service DNS name if required, and document this as a deviation from the Compose-based `ci-cd` setup.
- Pinning ArgoCD/Image Updater to `stable` manifests can silently pick up breaking version changes over time.
  - Mitigation: pin to a specific release tag in the install command and record the version in the docs.
- Running a fifth stack (k3d) on an 8GB host may not leave enough headroom even alone.
  - Mitigation: docs call out this risk explicitly and recommend closing other heavy applications during this phase; if k3d itself is too heavy, that is a finding to report back rather than something to silently work around.
