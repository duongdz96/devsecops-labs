# ArgoCD GitOps Lab

ArgoCD adds a lightweight Kubernetes GitOps deployment layer after Harbor works.

This lab proves:

```text
Harbor image -> k3d cluster -> ArgoCD sync -> WordPress running in Kubernetes
```

Image auto-update is intentionally deferred. This phase uses a static tag, usually `latest`.

This lab uses:

- Kubernetes cluster: k3d cluster `vinfast-gitops`
- ArgoCD namespace: `argocd`
- ArgoCD UI port-forward: `https://localhost:8084`
- WordPress namespace: `vinfast-wordpress`
- Harbor image in Kubernetes manifests: `host.docker.internal:8083/vinfast/wordpress:latest`
- GitOps repo local path: `G:\Cyber security\vinfast-gitops`
- GitOps repo host push URL: `http://localhost:8929/gitops/vinfast-wordpress.git`
- GitOps repo URL used by ArgoCD in cluster: `http://host.docker.internal:8929/gitops/vinfast-wordpress.git`

## Requirements

- Docker Desktop or Docker Engine.
- k3d installed and available in `PATH`.
- kubectl installed and available in `PATH`.
- Harbor running at `http://localhost:8083`.
- Harbor project `vinfast` exists.
- Harbor contains image `vinfast/wordpress:latest` or another tag you put into the manifest.
- GitLab running at `http://localhost:8929` when creating and syncing the manifest repo.
- About 8GB RAM and 4 CPU.

Do not enable Docker Desktop Kubernetes for this phase. Use k3d.

## Resource Strategy

This host has about 8GB RAM. Run only required services.

For k3d + ArgoCD testing:

- Harbor must run so Kubernetes can pull the WordPress image.
- GitLab must run so ArgoCD can fetch the GitOps repo.
- GitLab Runner is not needed after the image has been pushed.
- Dependency-Track and DefectDojo can be stopped.

Stop optional stacks:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml down
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml down
```

If memory remains tight, stop GitLab Runner:

```powershell
docker stop vinfast-gitlab-runner
```

Keep GitLab server running while ArgoCD syncs from GitLab.

## Verify Harbor Image Exists

On host:

```powershell
docker pull localhost:8083/vinfast/wordpress:latest
```

Expected: pull succeeds.

If image is missing, run the Harbor CI pipeline first or build/push manually:

```powershell
Set-Location .\ci-cd
docker build -t localhost:8083/vinfast/wordpress:latest .
docker push localhost:8083/vinfast/wordpress:latest
Set-Location ..
```

## Create k3d Cluster

The helper script creates a single-node k3d cluster and writes `.k3d/registries.yaml` for Harbor HTTP pulls.

From repo root:

```powershell
.\scripts\k3d-create-cluster.ps1
```

Script defaults:

```text
Cluster: vinfast-gitops
Harbor endpoint inside k3d: host.docker.internal:8083
Servers: 1
Agents: 0
Traefik: disabled
```

Generated registry config:

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

Check cluster:

```powershell
k3d cluster list
kubectl get nodes
```

Expected:

```text
vinfast-gitops appears in k3d cluster list
node status is Ready
```

## Verify k3d Can Pull From Harbor

Run this before installing ArgoCD app:

```powershell
docker exec k3d-vinfast-gitops-server-0 crictl pull host.docker.internal:8083/vinfast/wordpress:latest
```

Expected: pull succeeds.

If this fails, do not continue to ArgoCD yet. Fix Harbor reachability first.

### Fallback Harbor Address

If `host.docker.internal:8083` does not work, find Docker bridge gateway:

```powershell
docker network inspect bridge --format "{{(index .IPAM.Config 0).Gateway}}"
```

Common value:

```text
172.17.0.1
```

Then recreate cluster with custom endpoint:

```powershell
k3d cluster delete vinfast-gitops
.\scripts\k3d-create-cluster.ps1 -HarborEndpoint "172.17.0.1:8083"
```

Also update the image in `G:\Cyber security\vinfast-gitops\wordpress\wordpress-deployment.yaml` to match the same endpoint.

## Install ArgoCD

Create namespace:

```powershell
kubectl create namespace argocd
```

Install pinned ArgoCD release:

```powershell
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.7/manifests/install.yaml
```

Wait for pods:

```powershell
kubectl -n argocd wait --for=condition=Available deployment --all --timeout=300s
kubectl -n argocd get pods
```

Expected: ArgoCD pods are `Running` or deployments are available.

## Get ArgoCD Admin Password on Windows PowerShell

ArgoCD stores initial admin password as base64 in a secret.

PowerShell decode:

```powershell
$encoded = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
$password = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encoded))
$password
```

Login:

```text
Username: admin
Password: value printed above
```

## Open ArgoCD UI

Start port-forward:

```powershell
kubectl port-forward svc/argocd-server -n argocd 8084:443
```

Open:

```text
https://localhost:8084
```

Browser will warn about self-signed certificate. Accept it for this local lab.

## Create GitOps Project in GitLab

In GitLab UI at `http://localhost:8929`:

1. Login as `root` or lab user.
2. Create group `gitops` if it does not exist.
3. Create blank project `vinfast-wordpress` in group `gitops`.
4. Keep default branch `main`.
5. For first lab pass, make project public or internal if your GitLab access settings allow it.

If project is private, configure ArgoCD repository credentials before applying the Application. Public/internal local project avoids credential setup in Phase 5A.

## Push GitOps Repo

Local repo folder already contains manifests:

```text
G:\Cyber security\vinfast-gitops
```

Push to GitLab:

```powershell
Set-Location "G:\Cyber security\vinfast-gitops"
git init
git branch -M main
git add .
git commit -m "Add WordPress GitOps manifests"
git remote add origin http://localhost:8929/gitops/vinfast-wordpress.git
git push -u origin main
```

Return to main repo:

```powershell
Set-Location "G:\Cyber security\Vinfast"
```

## GitOps Repo Layout

```text
vinfast-gitops/
  README.md
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

Important image reference:

```text
host.docker.internal:8083/vinfast/wordpress:latest
```

Important ArgoCD repo URL inside cluster:

```text
http://host.docker.internal:8929/gitops/vinfast-wordpress.git
```

ArgoCD runs inside k3d, so it should not use `localhost:8929` for GitLab. Inside the cluster, `localhost` means the ArgoCD pod, not the host.

## Validate Manifests

After cluster exists:

```powershell
kubectl apply --dry-run=client -f "G:\Cyber security\vinfast-gitops\wordpress"
kubectl apply --dry-run=client -f "G:\Cyber security\vinfast-gitops\argocd\application.yaml"
```

Expected: dry-run output with no schema errors.

## Apply ArgoCD Application

From GitOps repo:

```powershell
Set-Location "G:\Cyber security\vinfast-gitops"
kubectl apply -f .\argocd\application.yaml
```

Check Application:

```powershell
kubectl -n argocd get application vinfast-wordpress
kubectl -n argocd describe application vinfast-wordpress
```

If automated sync works, status should become `Synced` and `Healthy` after resources settle.

If you use ArgoCD CLI, optional check:

```powershell
argocd app get vinfast-wordpress
```

## Verify WordPress Deployment

Check namespace resources:

```powershell
kubectl -n vinfast-wordpress get pods
kubectl -n vinfast-wordpress get svc
kubectl -n vinfast-wordpress describe deployment wordpress
```

Expected:

```text
mysql pod Running
wordpress pod Running
service/mysql ClusterIP on 3306
service/wordpress ClusterIP on 80
```

Check WordPress image:

```powershell
kubectl -n vinfast-wordpress get deployment wordpress -o jsonpath="{.spec.template.spec.containers[0].image}"
```

Expected:

```text
host.docker.internal:8083/vinfast/wordpress:latest
```

Port-forward WordPress:

```powershell
kubectl -n vinfast-wordpress port-forward svc/wordpress 8085:80
```

Open:

```text
http://localhost:8085
```

Expected: WordPress setup/login page loads.

## Update Image Tag Manually

Image Updater is out of scope for this phase. To test another tag manually:

1. Push new image tag to Harbor.
2. Edit `G:\Cyber security\vinfast-gitops\wordpress\wordpress-deployment.yaml`.
3. Change image tag.
4. Commit and push GitOps repo.
5. ArgoCD syncs the changed manifest.

Example for already-pushed tag `78576de`:

```powershell
Set-Location "G:\Cyber security\vinfast-gitops"
(Get-Content .\wordpress\wordpress-deployment.yaml) -replace 'host.docker.internal:8083/vinfast/wordpress:latest', 'host.docker.internal:8083/vinfast/wordpress:78576de' | Set-Content .\wordpress\wordpress-deployment.yaml
git add .\wordpress\wordpress-deployment.yaml
git commit -m "Update WordPress image tag"
git push
```

## Teardown

Delete app resources:

```powershell
kubectl delete -f "G:\Cyber security\vinfast-gitops\argocd\application.yaml"
kubectl delete namespace vinfast-wordpress
```

Delete ArgoCD:

```powershell
kubectl delete namespace argocd
```

Delete k3d cluster:

```powershell
k3d cluster delete vinfast-gitops
```

Stop Harbor and GitLab if done:

```powershell
docker compose -f .\infra\harbor\docker-compose.yml down
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml down
```

## Troubleshooting

### k3d cannot pull from Harbor

Test from k3d node:

```powershell
docker exec k3d-vinfast-gitops-server-0 crictl pull host.docker.internal:8083/vinfast/wordpress:latest
```

If error mentions HTTPS against HTTP registry, registry config was not applied or endpoint differs from image reference.

Fix:

1. Delete cluster.
2. Recreate with `scripts\k3d-create-cluster.ps1`.
3. Confirm `.k3d\registries.yaml` contains the same endpoint used in the manifest image.

### ImagePullBackOff

Check pod events:

```powershell
kubectl -n vinfast-wordpress describe pod -l app.kubernetes.io/name=wordpress
```

Common causes:

- Harbor is stopped.
- Image tag does not exist.
- k3d registry endpoint does not match image hostname.
- Docker Desktop insecure registry setting is missing for host-side testing.
- Harbor project is private and anonymous pull is denied.

For private Harbor pulls, create Kubernetes image pull secret in `vinfast-wordpress` and reference it in `wordpress-deployment.yaml`. Phase 5A assumes lab pull is allowed or Harbor is configured so k3d can pull the image.

### ArgoCD cannot reach GitLab repo

ArgoCD runs inside k3d. Do not use this repo URL inside Application:

```text
http://localhost:8929/gitops/vinfast-wordpress.git
```

Use:

```text
http://host.docker.internal:8929/gitops/vinfast-wordpress.git
```

Check repo from ArgoCD server pod:

```powershell
kubectl -n argocd exec deploy/argocd-server -- sh -c "wget -S -O- http://host.docker.internal:8929 2>&1 | head"
```

If private repo needs auth, add repo credentials in ArgoCD UI under **Settings > Repositories**.

### ArgoCD app OutOfSync or Degraded

Check Application details:

```powershell
kubectl -n argocd describe application vinfast-wordpress
```

Check managed resources:

```powershell
kubectl -n vinfast-wordpress get all
kubectl -n vinfast-wordpress describe pod -l app.kubernetes.io/name=wordpress
kubectl -n vinfast-wordpress describe pod -l app.kubernetes.io/name=mysql
```

Common causes:

- MySQL readiness probe still warming up.
- WordPress image pull failed.
- GitOps repo has not been pushed to GitLab.
- Application repo URL points to wrong host.

### Port-forward conflict

If `8084` is already in use, use another host port:

```powershell
kubectl port-forward svc/argocd-server -n argocd 8094:443
```

Open:

```text
https://localhost:8094
```

If WordPress port `8085` is busy:

```powershell
kubectl -n vinfast-wordpress port-forward svc/wordpress 8095:80
```

Open:

```text
http://localhost:8095
```

### Low memory

Symptoms:

- Pods stay Pending.
- Node has memory pressure.
- Docker Desktop becomes slow.
- GitLab or Harbor restarts.

Check:

```powershell
kubectl describe node
kubectl get pods -A
```

Reduce load:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml down
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml down
docker stop vinfast-gitlab-runner
```

If still low, stop GitLab after ArgoCD has synced once only if you no longer need repo access. ArgoCD cannot fetch new commits while GitLab is stopped.
