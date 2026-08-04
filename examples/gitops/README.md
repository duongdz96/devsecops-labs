# GitOps bootstrap templates

Bộ mẫu để **tự viết lại** repository `G:\Cyber security\devsecops-gitops`. Không apply trực tiếp trước khi thay placeholders.

## Trình tự

1. Tạo GitLab project `gitops/devsecops-gitops`.
2. Copy folder `wordpress/` và `argocd/` vào repository mới.
3. Thay `REPLACE_WITH_RELEASE_DIGEST` bằng digest từ job `promote-release`.
4. Chọn cách quản lý secret:
   - lab đầu tiên: tạo Secret thủ công ngoài Git;
   - gần doanh nghiệp: SOPS hoặc Sealed Secrets, encrypted value mới được commit.
5. Tạo Harbor pull secret bằng read-only robot riêng trong namespace; manifest WordPress tham chiếu `harbor-pull-secret`.
6. Commit/push manifests.
7. Đăng ký repository credentials trong ArgoCD nếu project private.
8. Apply `argocd/application.yaml`.

## Tạo Secret thủ công cho lần học đầu

Không commit password plaintext:

```powershell
kubectl create namespace devsecops-wordpress
kubectl -n devsecops-wordpress create secret generic wordpress-db-secret `
  --from-literal=MYSQL_DATABASE=wordpress `
  --from-literal=MYSQL_USER=wordpress `
  --from-literal=MYSQL_PASSWORD='<strong-password>' `
  --from-literal=MYSQL_ROOT_PASSWORD='<strong-root-password>'

kubectl -n devsecops-wordpress create secret docker-registry harbor-pull-secret `
  --docker-server=host.docker.internal:8083 `
  --docker-username='<release-pull-robot>' `
  --docker-password='<release-pull-token>'
```

`wordpress/secret.example.yaml` chỉ mô tả schema. Không đổi tên và commit nó với real values.

## Verify

```powershell
kubectl apply --dry-run=client -f .\wordpress\namespace.yaml
kubectl apply --dry-run=client -f .\wordpress\mysql-pvc.yaml
kubectl apply --dry-run=client -f .\wordpress\mysql-deployment.yaml
kubectl apply --dry-run=client -f .\wordpress\mysql-service.yaml
kubectl apply --dry-run=client -f .\wordpress\wordpress-deployment.yaml
kubectl apply --dry-run=client -f .\wordpress\wordpress-service.yaml
```

Deployment phải dùng immutable image digest, không dùng `latest`.
