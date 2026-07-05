# ArgoCD GitOps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a lightweight k3d + ArgoCD GitOps layer that deploys the Harbor WordPress image into Kubernetes.

**Architecture:** A single-node k3d cluster pulls the WordPress image from Harbor through an insecure registry endpoint reachable from node containers. ArgoCD syncs plain Kubernetes YAML from a separate local GitLab manifest repository.

**Tech Stack:** k3d, k3s, kubectl, ArgoCD v2.11.7 pinned install manifest, Kubernetes YAML, local GitLab, Harbor HTTP registry.

## Global Constraints

- Host has about 8GB RAM and 4 CPU.
- Build one component at a time.
- Harbor must already work and contain image `vinfast/wordpress`.
- GitLab already runs at `http://localhost:8929`.
- Kubernetes tool is k3d, not Docker Desktop Kubernetes and not kind.
- ArgoCD UI is exposed by port-forward on `https://localhost:8084`.
- Harbor is HTTP/insecure registry at `localhost:8083` from host perspective.
- k3d nodes must pull Harbor through host/network reachable name.
- Manifest repo is separate from this `Vinfast` repo.
- No ArgoCD Image Updater in Phase 5A.
- No Helm/Kustomize in Phase 5A.

---

## File Structure

- `scripts/k3d-create-cluster.ps1`: creates single-node k3d cluster and generated registry config.
- `docs/argocd/README.md`: step-by-step k3d, ArgoCD, GitOps repo, sync, verify, teardown, troubleshooting guide.
- `G:\Cyber security\vinfast-gitops\wordpress\*.yaml`: external GitOps repo Kubernetes manifests for namespace, MySQL, WordPress.
- `G:\Cyber security\vinfast-gitops\argocd\application.yaml`: ArgoCD Application pointing to local GitLab manifest repo.
- `G:\Cyber security\vinfast-gitops\README.md`: external repo usage notes.

---

### Task 1: k3d cluster helper

**Files:**

- Create: `scripts/k3d-create-cluster.ps1`
- Modify: `.gitignore`

**Interfaces:**

- Produces: `.k3d/registries.yaml` generated at runtime.
- Produces: k3d cluster named `vinfast-gitops`.
- Consumes: Harbor reachable from k3d node as `host.docker.internal:8083`.

- [ ] **Step 1: Write script**

Create a PowerShell script that writes this registry config:

```yaml
mirrors:
  "host.docker.internal:8083":
    endpoint:
      - "http://host.docker.internal:8083"
configs:
  "host.docker.internal:8083":
    tls:
      insecure_skip_verify: true
```

Then run:

```powershell
k3d cluster create vinfast-gitops --servers 1 --agents 0 --registry-config .\.k3d\registries.yaml --k3s-arg "--disable=traefik@server:0" --wait
```

- [ ] **Step 2: Ignore generated `.k3d/` runtime config**

Add `.k3d/` to `.gitignore`.

- [ ] **Step 3: Manual verification command**

Run after Harbor image exists:

```powershell
docker exec k3d-vinfast-gitops-server-0 crictl pull host.docker.internal:8083/vinfast/wordpress:latest
```

Expected: image pull succeeds.

---

### Task 2: GitOps manifest repository scaffold

**Files:**

- Create: `G:\Cyber security\vinfast-gitops\README.md`
- Create: `G:\Cyber security\vinfast-gitops\wordpress\namespace.yaml`
- Create: `G:\Cyber security\vinfast-gitops\wordpress\mysql-secret.yaml`
- Create: `G:\Cyber security\vinfast-gitops\wordpress\mysql-deployment.yaml`
- Create: `G:\Cyber security\vinfast-gitops\wordpress\mysql-service.yaml`
- Create: `G:\Cyber security\vinfast-gitops\wordpress\wordpress-deployment.yaml`
- Create: `G:\Cyber security\vinfast-gitops\wordpress\wordpress-service.yaml`
- Create: `G:\Cyber security\vinfast-gitops\argocd\application.yaml`

**Interfaces:**

- Produces: namespace `vinfast-wordpress`.
- Produces: service `mysql` on port `3306`.
- Produces: service `wordpress` on port `80`.
- Consumes: image `host.docker.internal:8083/vinfast/wordpress:latest`.
- Consumes: GitLab repo URL `http://host.docker.internal:8929/gitops/vinfast-wordpress.git`.

- [ ] **Step 1: Create namespace and MySQL manifests**

Create namespace, secret, deployment, and service YAML with small resource requests for local k3d.

- [ ] **Step 2: Create WordPress manifests**

Create WordPress deployment using Harbor image and service for port-forward access.

- [ ] **Step 3: Create ArgoCD Application**

Create ArgoCD Application targeting repo URL `http://host.docker.internal:8929/gitops/vinfast-wordpress.git`, path `wordpress`, target revision `main`, namespace `vinfast-wordpress`.

- [ ] **Step 4: Validate manifests**

Run after cluster exists:

```powershell
kubectl apply --dry-run=client -f "G:\Cyber security\vinfast-gitops\wordpress"
kubectl apply --dry-run=client -f "G:\Cyber security\vinfast-gitops\argocd\application.yaml"
```

Expected: dry-run configured messages, no schema errors.

---

### Task 3: ArgoCD operator docs

**Files:**

- Create: `docs/argocd/README.md`

**Interfaces:**

- Consumes: script from Task 1.
- Consumes: GitOps repo from Task 2.
- Produces: operator flow for create cluster, install ArgoCD, push manifest repo, apply Application, verify WordPress.

- [ ] **Step 1: Document prerequisites and resource strategy**

List k3d, kubectl, Docker, GitLab, Harbor image, and services to stop.

- [ ] **Step 2: Document k3d and Harbor pull test**

Include cluster creation script and `crictl pull` test.

- [ ] **Step 3: Document pinned ArgoCD install**

Use:

```powershell
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.7/manifests/install.yaml
```

- [ ] **Step 4: Document Windows admin password decode**

Use `[System.Convert]::FromBase64String()` PowerShell flow.

- [ ] **Step 5: Document GitLab manifest repo push**

Use local path `G:\Cyber security\vinfast-gitops` and remote `http://localhost:8929/gitops/vinfast-wordpress.git`.

- [ ] **Step 6: Document sync and verification**

Include `kubectl apply -f argocd/application.yaml`, app status, pod status, and WordPress port-forward.

- [ ] **Step 7: Document teardown and troubleshooting**

Include ImagePullBackOff, ArgoCD cannot reach GitLab, OutOfSync/Degraded, port conflicts, low memory.
