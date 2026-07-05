# ArgoCD GitOps Lab Design

Date: 2026-07-05

## Goal

Add a lightweight Kubernetes + GitOps deployment layer after Harbor is working. This phase deploys the WordPress image from Harbor into k3d using ArgoCD and a separate GitLab manifest repository.

This phase proves:

```text
Harbor image -> k3d cluster -> ArgoCD sync -> WordPress running in Kubernetes
```

Image auto-update is intentionally split into a later sub-phase.

## Scope

### Phase 5A — k3d + ArgoCD deploy from Harbor

In scope:

- Create k3d cluster.
- Configure k3d/containerd to pull from Harbor insecure registry.
- Install ArgoCD.
- Create separate GitOps manifest repo.
- Create Kubernetes manifests for WordPress and its database if needed.
- Create ArgoCD Application.
- Sync app and verify WordPress pod/service.
- Write detailed docs under `docs/argocd/README.md`.

Out of scope for Phase 5A:

- ArgoCD Image Updater.
- Automatic tag update commits.
- Ingress controller.
- TLS certificates.
- Helm/Kustomize.
- Production-grade Kubernetes hardening.

### Phase 5B — ArgoCD Image Updater

Deferred until 5A works. Adds:

```text
Harbor new tag -> Image Updater commits manifest tag -> ArgoCD syncs new image
```

## Constraints

- Host has about 8GB RAM and 4 CPU.
- Build one component at a time.
- Harbor must already work and contain image `vinfast/wordpress`.
- GitLab already runs at `http://localhost:8929`.
- Documentation must be written under `docs/`.
- Kubernetes tool: k3d, not Docker Desktop Kubernetes and not kind.
- ArgoCD UI exposed via port-forward on `https://localhost:8084`.
- Harbor is HTTP/insecure registry at `localhost:8083` from host perspective.
- k3d nodes must be configured to pull from Harbor via Docker host/network reachable name.
- Manifest repo is separate from this `Vinfast` repo.
- Manifest repo is pushed to local GitLab as a new project.
- Do not require all lab stacks to run simultaneously.

## Recommended Approach

Use k3d single-node cluster:

```text
1 server node
0 agents
containerd registry config for Harbor
```

Use official ArgoCD install manifests pinned to a release version rather than `stable`.

Use plain Kubernetes YAML in a separate GitOps repo:

```text
vinfast-gitops/
  wordpress/
    namespace.yaml
    mysql-secret.yaml
    mysql-deployment.yaml
    mysql-service.yaml
    wordpress-deployment.yaml
    wordpress-service.yaml
  argocd/
    application.yaml
```

Use a static Harbor image tag first, e.g. `latest` or a known pushed commit SHA. Image Updater will be later.

## Data Flow

1. Harbor phase builds and pushes `localhost:8083/vinfast/wordpress:<tag>`.
2. User creates k3d cluster with registry config for Harbor.
3. User installs ArgoCD into namespace `argocd`.
4. User creates/pushes GitOps manifest repo to local GitLab.
5. User applies ArgoCD Application pointing to the manifest repo/path.
6. ArgoCD syncs manifests into k3d.
7. k3d pulls WordPress image from Harbor.
8. User verifies WordPress pod is running.
9. User verifies WordPress service can be reached via `kubectl port-forward`.

## Harbor Pull Configuration

k3d cannot use host `localhost:8083` from inside node containers the same way the host can. The docs and implementation must explicitly define the registry address used inside k3d.

Expected approach:

- Use host-reachable name `host.docker.internal:8083` so it matches Harbor `hostname` and token realm, or Docker bridge gateway address if needed.
- Create k3d `registries.yaml` marking Harbor endpoint as plain HTTP/insecure.
- Use the same image reference in Kubernetes manifests that k3d can resolve.
- Verify with a manual pull test before ArgoCD sync.

## ArgoCD Setup

- Namespace: `argocd`.
- Install source: official ArgoCD release manifest pinned to a version.
- UI access:

```powershell
kubectl port-forward svc/argocd-server -n argocd 8084:443
```

- Admin password retrieval:

```powershell
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

On Windows PowerShell, docs must include a Windows-compatible decode alternative.

## GitOps Repository

Create a separate local repo, e.g.:

```text
g:\Cyber security\vinfast-gitops
```

Push it to local GitLab project, e.g.:

```text
http://localhost:8929/gitops/vinfast-wordpress.git
```

The repo contains manifests for WordPress and MySQL.

ArgoCD Application points to:

- repo URL: local GitLab manifest project
- path: `wordpress`
- target revision: `main` or configured default branch
- destination namespace: `vinfast-wordpress`
- sync policy: automated or manual; for first pass, automated sync with prune/selfHeal is acceptable if documented.

## Documentation Requirements

Create `docs/argocd/README.md` with careful, step-by-step instructions:

1. Prerequisites: k3d, kubectl, Docker, GitLab, Harbor image already pushed.
2. Resource warning and what services can be stopped.
3. Verify Harbor image exists.
4. Create k3d registry config for Harbor insecure registry.
5. Create k3d cluster.
6. Verify cluster with `kubectl get nodes`.
7. Install ArgoCD pinned version.
8. Wait for ArgoCD pods.
9. Get ArgoCD admin password on Windows PowerShell.
10. Port-forward ArgoCD UI.
11. Create GitOps manifest repo locally.
12. Create GitLab project and push manifest repo.
13. Apply ArgoCD Application.
14. Sync app.
15. Verify pods/services.
16. Port-forward WordPress service and open browser.
17. Teardown cluster.
18. Troubleshooting:
    - k3d cannot pull from Harbor
    - ImagePullBackOff
    - ArgoCD cannot reach GitLab repo
    - ArgoCD app OutOfSync/Degraded
    - port-forward conflicts
    - low memory

## Files to Create or Modify

- Create `scripts/k3d-create-cluster.ps1` or document equivalent commands.
- Create `docs/argocd/README.md`.
- Create external repo `g:\Cyber security\vinfast-gitops` with Kubernetes manifests.
- No changes to `ci-cd/.gitlab-ci.yml` in Phase 5A.
- No ArgoCD Image Updater manifests in Phase 5A.

## Success Criteria

- `k3d cluster list` shows cluster running.
- `kubectl get nodes` shows node ready.
- ArgoCD pods running in namespace `argocd`.
- ArgoCD UI reachable via `https://localhost:8084` port-forward.
- Admin login works with retrieved password.
- GitOps manifest repo exists locally and in local GitLab.
- ArgoCD Application points at manifest repo/path.
- ArgoCD Application becomes `Synced` and `Healthy`.
- WordPress pod runs using image from Harbor.
- WordPress service reachable via `kubectl port-forward`.
- `docs/argocd/README.md` explains setup, usage, verification, and teardown.

## Resource Strategy

Because host has about 8GB RAM:

- k3d + ArgoCD is its own phase.
- Run only required stacks:
  - Harbor must be running for image pulls.
  - GitLab must be running while creating/pushing manifest repo or if ArgoCD pulls from GitLab.
  - Dependency-Track and DefectDojo can be stopped during ArgoCD testing.
- Use 1 k3d server and 0 agents.
- If pods remain pending or node is pressured, stop other stacks before changing the design.

## Risks and Mitigations

- k3d registry networking differs from host Docker and GitLab DinD.
  - Mitigation: docs include a manual pull test before ArgoCD sync.
- WordPress may require database configuration different from Docker Compose.
  - Mitigation: include MySQL Deployment/Service/Secret in GitOps repo.
- ArgoCD needs GitLab repo access.
  - Mitigation: use public/internal local project for lab or document credentials if private.
- Local GitLab may use HTTP and self-hosted URL.
  - Mitigation: document repo URL exactly and test ArgoCD repo connection.
- Image Updater adds extra credential complexity.
  - Mitigation: split it into Phase 5B after 5A works.
