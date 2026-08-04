# ArgoCD — GitOps trên k3d

ArgoCD thêm lớp GitOps Kubernetes nhẹ, deploy WordPress từ Harbor lên k3d.

Lab này chứng minh:

```text
Harbor image (release by digest) -> k3d cluster -> ArgoCD sync -> WordPress running in Kubernetes
```

Image auto-update (ArgoCD Image Updater) cố tình để sau. Phase này dùng image release **tham chiếu theo digest** trong manifest GitOps.

## Thông số

- Kubernetes cluster: k3d cluster `devsecops-gitops`
- ArgoCD namespace: `argocd`
- ArgoCD UI port-forward: `https://localhost:8084`
- WordPress namespace: `devsecops-wordpress`
- Harbor release image trong manifest: `host.docker.internal:8083/devsecops-lab/wordpress@sha256:<digest>`
- GitOps repo local path: `G:\Cyber security\devsecops-gitops`
- GitOps repo host push URL: `http://localhost:8929/gitops/devsecops-gitops.git`
- GitOps repo URL dùng bởi ArgoCD trong cluster: `http://host.docker.internal:8929/gitops/devsecops-gitops.git`
- App GitLab CI: `test-cicd/test_project`

## Yêu cầu

- Docker Desktop hoặc Docker Engine.
- k3d trong `PATH`.
- kubectl trong `PATH`.
- Harbor đang chạy tại `http://localhost:8083`.
- Harbor project `devsecops-lab` có image `wordpress` (tag digest).
- GitLab chạy tại `http://localhost:8929` khi tạo + sync manifest repo.
- ~8GB RAM, 4 CPU.

Không bật Docker Desktop Kubernetes cho phase này. Dùng k3d.

## Chiến lược tài nguyên

Máy ~8GB RAM, chỉ chạy service cần thiết.

Test k3d + ArgoCD:

- Harbor phải chạy để k3d pull được image.
- GitLab phải chạy để ArgoCD fetch GitOps repo.
- GitLab Runner không cần sau khi image đã push.
- Dependency-Track và DefectDojo tắt được.

Tắt stack không cần:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml down
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml down
```

Nếu vẫn căng RAM, tắt runner:

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml stop gitlab-runner
```

Giữ GitLab server chạy trong khi ArgoCD sync từ GitLab.

## Verify Harbor image tồn tại

Pull từ host:

```powershell
docker pull host.docker.internal:8083/devsecops-lab/wordpress@sha256:<digest>
```

Expected: pull succeed. Lấy digest immutable từ artifact `release.env` của job `promote-release`; pipeline không phụ thuộc `latest`.

Nếu thiếu image, chạy pipeline Harbor của `test-cicd/test_project` trước, hoặc build/push tay.

## Tạo k3d cluster

Script helper tạo k3d single-node và ghi `.k3d/registries.yaml` cho Harbor HTTP pulls.

Từ repo root:

```powershell
.\scripts\k3d-create-cluster.ps1
```

Default của script:

```text
Cluster: devsecops-gitops
Harbor endpoint trong k3d: host.docker.internal:8083
Servers: 1
Agents: 0
Traefik: disabled
```

Registry config sinh ra:

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
devsecops-gitops xuất hiện trong k3d cluster list
node status Ready
```

## Verify k3d pull được từ Harbor

Chạy trước khi cài ArgoCD app:

```powershell
docker exec k3d-devsecops-gitops-server-0 crictl pull host.docker.internal:8083/devsecops-lab/wordpress@sha256:<digest>
```

Expected: pull succeed.

Nếu fail, chưa sang ArgoCD. Sửa Harbor reachability trước.

### Fallback Harbor address

Nếu `host.docker.internal:8083` không chạy, tìm Docker bridge gateway:

```powershell
docker network inspect bridge --format "{{(index .IPAM.Config 0).Gateway}}"
```

Giá trị thường gặp:

```text
172.17.0.1
```

Recreate cluster với endpoint tùy chỉnh:

```powershell
k3d cluster delete devsecops-gitops
.\scripts\k3d-create-cluster.ps1 -HarborEndpoint "172.17.0.1:8083"
```

Đồng bộ image trong `G:\Cyber security\devsecops-gitops\wordpress\wordpress-deployment.yaml` theo cùng endpoint.

## Cài ArgoCD

Tạo namespace:

```powershell
kubectl create namespace argocd
```

Cài ArgoCD pinned release:

```powershell
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.7/manifests/install.yaml
```

Chờ pods:

```powershell
kubectl -n argocd wait --for=condition=Available deployment --all --timeout=300s
kubectl -n argocd get pods
```

Expected: ArgoCD pods `Running` hoặc deployments available.

## Lấy admin password ArgoCD trên Windows PowerShell

ArgoCD lưu initial admin password dạng base64 trong secret:

```powershell
$encoded = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
$password = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encoded))
$password
```

Login:

```text
Username: admin
Password: giá trị in ra ở trên
```

## Mở ArgoCD UI

Port-forward:

```powershell
kubectl port-forward svc/argocd-server -n argocd 8084:443
```

Mở:

```text
https://localhost:8084
```

Browser sẽ cảnh báo self-signed certificate. Chấp nhận cho lab local này.

## Tạo GitOps project trong GitLab

GitLab UI `http://localhost:8929`:

1. Login `root` hoặc lab user.
2. Tạo group `gitops` nếu chưa có.
3. Tạo blank project `devsecops-gitops` trong group `gitops`.
4. Giữ default branch `main`.
5. Pass đầu tiên: để project public hoặc internal nếu GitLab settings cho phép.

Nếu project private, phải cấu hình repository credentials trong ArgoCD trước khi apply Application. Project public/internal tránh được bước credentials này.

## Push GitOps repo

Local repo đã chứa manifests:

```text
G:\Cyber security\devsecops-gitops
```

Push lên GitLab:

```powershell
Set-Location "G:\Cyber security\devsecops-gitops"
git init
git branch -M main
git add .
git commit -m "Add WordPress GitOps manifests"
git remote add origin http://localhost:8929/gitops/devsecops-gitops.git
git push -u origin main
```

## Cấu trúc GitOps repo

```text
devsecops-gitops/
  README.md
  wordpress/
    namespace.yaml
    mysql-pvc.yaml
    mysql-deployment.yaml
    mysql-service.yaml
    wordpress-deployment.yaml
    wordpress-service.yaml
  argocd/
    application.yaml
```

Không commit MySQL password plaintext. Lần lab đầu tạo Secret bằng `kubectl`; phase doanh nghiệp chuyển sang SOPS hoặc Sealed Secrets.

Image reference quan trọng:

```text
host.docker.internal:8083/devsecops-lab/wordpress@sha256:<digest>
```

ArgoCD repo URL trong cluster:

```text
http://host.docker.internal:8929/gitops/devsecops-gitops.git
```

ArgoCD chạy trong k3d, nên không dùng `localhost:8929` cho GitLab. Trong cluster, `localhost` là ArgoCD pod, không phải host.

## Validate manifests

Sau khi cluster tồn tại:

```powershell
kubectl apply --dry-run=client -f "G:\Cyber security\devsecops-gitops\wordpress"
kubectl apply --dry-run=client -f "G:\Cyber security\devsecops-gitops\argocd\application.yaml"
```

Expected: dry-run output, không schema errors.

## Apply ArgoCD Application

Từ GitOps repo:

```powershell
Set-Location "G:\Cyber security\devsecops-gitops"
kubectl apply -f .\argocd\application.yaml
```

Check Application:

```powershell
kubectl -n argocd get application devsecops-wordpress
kubectl -n argocd describe application devsecops-wordpress
```

Nếu automated sync chạy, status thành `Synced` + `Healthy` sau khi resources settle.

## Verify WordPress deployment

Check namespace resources:

```powershell
kubectl -n devsecops-wordpress get pods
kubectl -n devsecops-wordpress get svc
kubectl -n devsecops-wordpress describe deployment wordpress
```

Expected:

```text
mysql pod Running
wordpress pod Running
service/mysql ClusterIP trên 3306
service/wordpress ClusterIP trên 80
```

Check image WordPress:

```powershell
kubectl -n devsecops-wordpress get deployment wordpress -o jsonpath="{.spec.template.spec.containers[0].image}"
```

Expected:

```text
host.docker.internal:8083/devsecops-lab/wordpress@sha256:<digest>
```

Port-forward WordPress:

```powershell
kubectl -n devsecops-wordpress port-forward svc/wordpress 8085:80
```

Mở:

```text
http://localhost:8085
```

Expected: trang setup/login WordPress load.

## Cập nhật image bằng digest mới

Image Updater ngoài scope. Test digest mới thủ công:

1. Push image release mới lên Harbor (CI hoặc tay), lấy digest mới.
2. Sửa `G:\Cyber security\devsecops-gitops\wordpress\wordpress-deployment.yaml`: đổi image reference theo digest.
3. Commit + push GitOps repo.
4. ArgoCD sync manifest đã đổi.

```powershell
Set-Location "G:\Cyber security\devsecops-gitops"
# sửa image: thành host.docker.internal:8083/devsecops-lab/wordpress@sha256:<digest mới>
git add .\wordpress\wordpress-deployment.yaml
git commit -m "Update WordPress image digest"
git push
```

## Teardown

Xóa app resources:

```powershell
kubectl delete -f "G:\Cyber security\devsecops-gitops\argocd\application.yaml"
kubectl delete namespace devsecops-wordpress
```

Xóa ArgoCD:

```powershell
kubectl delete namespace argocd
```

Xóa k3d cluster:

```powershell
k3d cluster delete devsecops-gitops
```

Dừng Harbor + GitLab nếu xong:

```powershell
docker compose -f .\infra\harbor\docker-compose.yml down
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml down
```

## Troubleshooting

### k3d không pull được từ Harbor

Test từ k3d node:

```powershell
docker exec k3d-devsecops-gitops-server-0 crictl pull host.docker.internal:8083/devsecops-lab/wordpress@sha256:<digest>
```

Nếu lỗi HTTPS vs HTTP registry, registry config không được áp dụng hoặc endpoint khác image reference.

Fix:

1. Xóa cluster.
2. Recreate với `scripts\k3d-create-cluster.ps1`.
3. Xác nhận `.k3d\registries.yaml` chứa cùng endpoint dùng trong manifest image.

### ImagePullBackOff

Check pod events:

```powershell
kubectl -n devsecops-wordpress describe pod -l app.kubernetes.io/name=wordpress
```

Nguyên nhân thường gặp:

- Harbor đang tắt.
- Digest không tồn tại trong `devsecops-lab`.
- k3d registry endpoint không khớp image hostname.
- Docker Desktop insecure registry thiếu cho host-side test.
- Harbor project private và pull anonymous bị từ chối.

Pull private Harbor: tạo Kubernetes image pull secret trong `devsecops-wordpress` và reference trong `wordpress-deployment.yaml`. Phase này giả định lab pull cho phép.

### ArgoCD không reach được GitLab repo

ArgoCD chạy trong k3d. Không dùng repo URL này trong Application:

```text
http://localhost:8929/gitops/devsecops-gitops.git
```

Dùng:

```text
http://host.docker.internal:8929/gitops/devsecops-gitops.git
```

Test từ ArgoCD server pod:

```powershell
kubectl -n argocd exec deploy/argocd-server -- sh -c "wget -S -O- http://host.docker.internal:8929 2>&1 | head"
```

Nếu repo private, thêm credentials trong ArgoCD UI **Settings > Repositories**.

### ArgoCD app OutOfSync hoặc Degraded

Check Application details:

```powershell
kubectl -n argocd describe application devsecops-wordpress
```

Check managed resources:

```powershell
kubectl -n devsecops-wordpress get all
kubectl -n devsecops-wordpress describe pod -l app.kubernetes.io/name=wordpress
kubectl -n devsecops-wordpress describe pod -l app.kubernetes.io/name=mysql
```

Nguyên nhân thường gặp:

- MySQL readiness probe còn warming up.
- WordPress image pull fail.
- GitOps repo chưa push lên GitLab.
- Application repo URL sai host.

### Xung đột port-forward

`8084` bận, dùng port khác:

```powershell
kubectl port-forward svc/argocd-server -n argocd 8094:443
```

Mở:

```text
https://localhost:8094
```

WordPress port `8085` bận:

```powershell
kubectl -n devsecops-wordpress port-forward svc/wordpress 8095:80
```

Mở:

```text
http://localhost:8095
```

### Low memory

Triệu chứng:

- Pod kẹp `Pending`.
- Node memory pressure.
- Docker Desktop chậm.
- GitLab/Harbor restart.

Check:

```powershell
kubectl describe node
kubectl get pods -A
```

Giảm tải:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml down
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml down
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml stop gitlab-runner
```

Nếu vẫn căng, chỉ tắt GitLab sau khi ArgoCD sync thành công lần đầu nếu không cần repo access nữa. ArgoCD không fetch commit mới khi GitLab tắt.
