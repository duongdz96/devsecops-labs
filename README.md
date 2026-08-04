# DevSecOps-Labs

Local lab học GitOps + DevSecOps: GitLab CI/CD → Harbor registry → quét SBOM/SAST → tổng hợp lỗ hổng → ArgoCD deploy WordPress lên k3d.

## Kiến trúc

```text
GitLab CI (build) -> Harbor (registry) -> k3d + ArgoCD (GitOps deploy)
       \-> Dependency-Track (SBOM)  -> fail gate
       \-> DefectDojo (aggregation) -> fail gate
```

Sáu thành phần chạy trên máy 8GB RAM này. Mỗi phase bật một phần, không chạy đồng loạt.

| Layer | Compose project | Cổng | Docs |
| --- | --- | --- | --- |
| GitLab CE + Runner | `devsecops-labs-gitlab` | HTTP `8929`, SSH `3224` | - |
| Harbor registry | installer riêng (không trong compose chính) | `8083` | `docs/harbor/README.md` |
| Dependency-Track | `devsecops-labs-dtrack` | API `8080`, UI `8081` | `docs/dependency-track/README.md` |
| DefectDojo | `devsecops-labs-dojo` | `8082` | `docs/defectdojo/README.md` |
| k3d + ArgoCD | cluster `devsecops-gitops` | ArgoCD `8084`, WordPress `8085` | `docs/argocd/README.md` |
| Clean rebuild | - | - | `docs/clean-rebuild/README.md` |

## Tên chuẩn (bắt buộc khớp)

Lab dùng một bộ tên thống nhất. Đừng đổi tên tùy ý; mọi docs/script/compose đều tham chiếu đúng tên này.

| Vai trò | Tên |
| --- | --- |
| Mạng Docker chung (external) | `devsecops-labs-cicd` |
| Compose project GitLab | `devsecops-labs-gitlab` |
| Compose project Dependency-Track | `devsecops-labs-dtrack` |
| Compose project DefectDojo | `devsecops-labs-dojo` |
| GitLab group + project app | `test-cicd` / `test_project` |
| GitLab SSH port | `3224` |
| Dependency-Track project | `devsecops-wordpress` |
| DefectDojo product | `devsecops-wordpress` |
| Harbor project (candidate) | `devsecops-candidate` |
| Harbor project (release) | `devsecops-lab` |
| k3d cluster + tên GitOps | `devsecops-gitops` |

App nim `test_project` là repo Git độc lập, nested trong đây nhưng bị `.gitignore` chặn, nên không bao giờ bị parent repo track hay commit. Vào GitLab nó nằm ở `test-cicd/test_project`.

## Mẫu → runtime: bảo vệ secret

Thiết kế secret theo mẫu "template track bằng git, runtime giá trị thật gitignored":

- File `*.example` (vd `.env.gitlab.example`) là **template**, có git, chỉ chứa placeholder.
- File runtime (`.env.gitlab`, `.env.harbor`, ...) là **gitignored**, chứa giá trị thật — không bao giờ commit.
- `infra/harbor/harbor.yml.tmpl` là template có git; `infra/harbor/harbor.yml` là runtime gitignored.

Lần đầu khởi tạo secrets và config:

```powershell
.\scripts\New-LabSecrets.ps1
.\scripts\New-HarborConfig.ps1
.\scripts\Test-LabConfig.ps1
```

- `New-LabSecrets.ps1` sinh mật khẩu ngẫu nhiên cho cả 4 env stack, render từ template `.example` → runtime `.env.*`.
- `New-HarborConfig.ps1` đọc `.env.harbor`, render `infra/harbor/harbor.yml` từ `harbor.yml.tmpl`, chặn mọi `CHANGE_ME`/kí tự nguy hiểm.
- `Test-LabConfig.ps1` preflight: kiểm tra docker, env files không còn `CHANGE_ME`, compose render đúng project name `devsecops-labs-*` + network `devsecops-labs-cicd`, cổng trống, tool k3d/kubectl/wsl (phase `gitops`).

Giữ giá trị ổn định **sau lần boot đầu**: đổi `DTRACK_ALPINE_SECRET_KEY` hoặc `DD_SECRET_KEY` / `DD_CREDENTIAL_AES_256_KEY` sau khi có dữ liệu sẽ làm API key / credential đã mã hóa đọc không được. Chỉ đổi khi rebuild sạch theo runbook.

## Các phase

1. [Harbor registry](docs/harbor/README.md)
2. [Dependency-Track — SBOM + fail gate](docs/dependency-track/README.md)
3. [DefectDojo — tổng hợp lỗ hổng](docs/defectdojo/README.md)
4. [ArgoCD — GitOps trên k3d](docs/argocd/README.md)

## Dọn dẹp / rebuild

Muốn bootstrap lại lab sạch (giữ image cache + volume MySQL), xem runbook an toàn tại [`docs/clean-rebuild/README.md`](docs/clean-rebuild/README.md). Runbook là thao tác **do người chạy thủ công theo checkpoint**, không auto-run lệnh phá dữ liệu.

## Ghi chú tài nguyên

Host ~8GB RAM. Nếu bật cùng lúc quá nhiều stack: GitLab/Postgres restart, container OOM, pod kẹp `Pending`. Chạy đúng stack cho từng phase theo phụ lục docs tương ứng, tắt stack dư khi cần.
