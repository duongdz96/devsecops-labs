# Clean Rebuild — Bootstrap lại lab sạch

Runbook thủ công để đưa lab về trạng thái sạch, **giữ nguyên** Docker image cache, source WordPress và WordPress MySQL named volume. Mọi thao tác phá hủy đều có checkpoint — bạn xác nhận rõ ràng trước khi chạy.

Không auto-chạy lệnh phá dữ liệu. Bạn đọc, bạn gõ, bạn nói "yes".

## Mục đích

- Ghi inventory trước khi reset.
- Xóa sạch state GitLab, Runner, Dependency-Track, DefectDojo, Harbor, k3d và ArgoCD.
- Giữ Docker image cache để không phải tải lại hàng GB.
- Giữ source WordPress và named volume MySQL của ứng dụng.
- Xóa riêng metadata Git cũ của `test_project`, rồi tự `git init` lại ở chặng GitLab.
- Xóa source GitOps cũ, rồi tự tạo `G:\Cyber security\devsecops-gitops` ở chặng ArgoCD.

Không làm:

- Không chạy `docker system prune`, `docker volume prune` hoặc lệnh prune toàn host.
- Không xóa named volume WordPress MySQL.
- Không xóa source trong `test_project`.
- Không xóa Docker resources không thuộc lab.
- Không tự chạy bất kỳ lệnh phá hủy nào; bạn đọc allowlist và xác nhận trước.

## Kiểm tra inventory

Chạy từng lệnh, ghi output ra file tạm hoặc note tay. Biết rõ trạng thái trước khi thay đổi.

### 1. Docker compose stacks

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml ps
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml ps
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml ps
```

### 2. Containers đang chạy trên host

```powershell
docker ps --format "table {{.Names}}`t{{.Image}}`t{{.Status}}"
```

Ghi lại danh sách container + status.

### 3. Volumes tồn tại

```powershell
docker volume ls
```

Trong số đó, **bắt buộc giữ**:

```text
devsecops-wordpress-local_db_data  ← WordPress MySQL data (default)
```

Volumes thuộc GitLab, Dependency-Track, DefectDojo, Harbor và k3d nằm trong phạm vi clean reset. Ghi tên chính xác từ inventory trước khi xóa. WordPress MySQL volume là ngoại lệ bắt buộc giữ.

### 4. Networks tồn tại

```powershell
docker network ls
```

External network `devsecops-labs-cicd` phải ở đó. Nếu thiếu, recreate:

```powershell
docker network create devsecops-labs-cicd
```

### 5. Cổng đang chiếm

```powershell
Get-NetTCPConnection -State Listen -LocalPort 8929,3224,8080,8081,8082,8083 -ErrorAction SilentlyContinue
```

Ghi cổng nào đang listen. Nếu service ngoài lab chiếm cổng, xử lý trước khi start stack.

### 6. Tooling có mặt

```powershell
docker --version
k3d version
kubectl version --client
wsl --status
```

Chỉ cần `docker` cho phase config. `k3d`/`kubectl`/`wsl` cần cho phase gitops.

### 7. File state

```powershell
Test-Path .env.gitlab
Test-Path .env.dependency-track
Test-Path .env.defectdojo
Test-Path .env.harbor
Test-Path infra/harbor/harbor.yml
```

Ghi file nào tồn tại. Nếu thiếu, chạy lại `New-LabSecrets.ps1` + `New-HarborConfig.ps1` ở phần regenerate.

## Giữ hay xóa? — allowlist

Bảng này quyết định mọi lệnh tiếp theo. Điền trước khi chạy bất kỳ lệnh destructime nào.

| Thứ | Giữ | Xóa | Ghi chú |
| --- | --- | --- | --- |
| Docker image cache | ✅ | ❌ | Không chạy `docker system prune`. |
| WordPress MySQL named volume | ✅ | ❌ | DB content. Default: `devsecops-wordpress-local_db_data`. |
| GitLab/Runner/DTrack/DefectDojo/Harbor runtime data | ❌ | ✅ | Clean rebuild: mất users, tokens, projects, history và findings cũ. |
| `.env.*` runtime secrets cũ | ❌ | ✅ | Tạo lại từ template; credentials cũ phải được rotate. |
| `test_project/.git` | ❌ | ✅ | Chỉ xóa metadata Git; giữ toàn bộ source. |
| `G:\Cyber security\vinfast-gitops` | ❌ | ✅ | Xóa source cũ; tạo lại `devsecops-gitops` sau. |
| k3d cluster `devsecops-gitops` | ❌ | ✅ | Xóa toàn bộ Kubernetes/ArgoCD state cũ. |
| Containers/networks/volumes thuộc lab | ❌ | ✅ | Chỉ xóa resources đã đối chiếu từ inventory. |

## Quy trình — theo phase

Runbook chạy theo thứ tự. Mỗi phase đều có checkpoint.

### Phase 1: Dừng mọi stack

Dừng toàn bộ stack Compose trước. Chưa dùng `-v`; volume allowlist được xử lý sau khi inventory xác nhận.

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml down
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml down
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml down
```

Harbor chạy bằng installer riêng (`infra/harbor/docker-compose.yml`), không nằm trong compose chính:

```powershell
docker compose -f .\infra\harbor\docker-compose.yml down
```

> **CHECKPOINT** — Dừng ở đây. Xác nhận trong `docker ps` không còn container lab nào (chỉ trừ containers của Docker Desktop, WSL, k3d). Nếu còn, dừng thủ công hoặc đợi cho dừng xong. **Chỉ tiếp tục khi bạn đã chắc chắn.**

### Phase 2: Xóa k3d cluster (nếu muốn)

Nếu muốn rebuild lại từ đầu phần Kubernetes:

```powershell
k3d cluster delete devsecops-gitops
```

> **CHECKPOINT** — Dừng ở đây. Xác nhận `k3d cluster list` không còn `devsecops-gitops`. Nếu bạn vẫn cần cluster cũ, bỏ qua bước này. **Xóa cluster là xóa toàn bộ state Kubernetes trong cluster đó — không thể undo.**

### Phase 3: Xóa data runtime DevSecOps

**Cảnh báo:** bước này xóa vĩnh viễn GitLab users/projects/tokens/pipelines, Runner registration, DTrack SBOM/findings, DefectDojo findings, Harbor images/projects/robots và Kubernetes state. Docker image cache và WordPress MySQL named volume không nằm trong allowlist xóa.

Trước khi chạy, gõ đúng câu xác nhận trong terminal:

```powershell
$confirmation = Read-Host 'Type DELETE DEVSECOPS RUNTIME to continue'
if ($confirmation -cne 'DELETE DEVSECOPS RUNTIME') { throw 'Reset cancelled' }
```

Chỉ khi xác nhận đúng, xóa các bind-data/runtime paths đã biết. Trước đó, lấy đúng named volume IDs từ inventory và xóa **chỉ** volumes thuộc GitLab, Runner, Dependency-Track, DefectDojo, Harbor/k3d; không chọn WordPress MySQL volume:

```powershell
$labVolumes = @(
  # Điền exact volume names từ `docker volume ls` sau khi đối chiếu Mounts/Labels.
  # Ví dụ: 'devsecops-labs-dtrack_<volume-name>'
)
if ($labVolumes.Count -eq 0) {
  Write-Host 'No named lab volumes selected; bind-data cleanup continues.'
} else {
  docker volume rm $labVolumes
}
```

Sau đó xóa các bind-data/runtime paths:

```powershell
$labPaths = @(
  '.\gitlab',
  '.\gitlab-runner',
  '.\dependency-track',
  '.\defectdojo',
  '.\.k3d',
  '.\infra\harbor\common',
  '.\infra\harbor\data',
  '.\infra\harbor\security',
  '.\infra\harbor\docker-compose.yml',
  '.\infra\harbor\harbor.yml',
  '.\.env.gitlab',
  '.\.env.dependency-track',
  '.\.env.defectdojo',
  '.\.env.harbor'
)
$labPaths | ForEach-Object {
  if (Test-Path -LiteralPath $_) { Remove-Item -LiteralPath $_ -Recurse -Force }
}
```

Harbor runtime trong WSL phải được kiểm tra rồi xóa riêng:

```powershell
wsl -- bash -lc 'for p in /home/duongnb/vinfast-harbor /home/duongnb/devsecops-harbor; do test -d "$p" && printf "Found %s\n" "$p"; done'
# Sau khi tự xác nhận đúng hai path runtime:
wsl -- bash -lc 'rm -rf -- /home/duongnb/vinfast-harbor /home/duongnb/devsecops-harbor'
```

> **CHECKPOINT** — Dừng ở đây. Xác nhận source/config tracked vẫn còn: `docker-compose.*.yml`, `.env.*.example`, `infra/harbor/harbor.yml.tmpl`, scripts, docs và `test_project` source. Xác nhận Docker image cache và WordPress MySQL volume vẫn còn.

### Phase 4: Xóa metadata Git app và source GitOps cũ

Hai thao tác này độc lập, phá hủy lịch sử Git. Source WordPress phải được giữ.

```powershell
$confirmation = Read-Host 'Type RESET TEST SOURCE GIT to delete test_project/.git and generated wp-config.php'
if ($confirmation -ceq 'RESET TEST SOURCE GIT') {
  Remove-Item -LiteralPath '.\test_project\.git' -Recurse -Force
  Remove-Item -LiteralPath '.\test_project\wp-config.php' -Force -ErrorAction SilentlyContinue
}

$confirmation = Read-Host 'Type DELETE OLD GITOPS SOURCE to delete G:\Cyber security\vinfast-gitops'
if ($confirmation -ceq 'DELETE OLD GITOPS SOURCE') {
  Remove-Item -LiteralPath 'G:\Cyber security\vinfast-gitops' -Recurse -Force
}
```

> **CHECKPOINT** — `test_project/wp-admin`, `test_project/wp-content`, `test_project/Dockerfile` phải còn. Chỉ `test_project/.git` biến mất. Folder GitOps cũ biến mất; folder mới chưa được tạo ở bước này.

## Regenerate secrets/config

Clean reset đã xóa `.env.*`, nên tạo bộ credentials mới. `New-LabSecrets.ps1` từ chối ghi đè file tồn tại trừ khi dùng `-Force`; không cần `-Force` trong luồng sạch này.

```powershell
.\scripts\New-LabSecrets.ps1
.\scripts\New-HarborConfig.ps1
```

`New-LabSecrets.ps1`:

- Sinh mật khẩu ngẫu nhiên cho 4 env stack.
- Render từ template `.example` → file runtime `.env.*`.
- Từ chối nếu file đã tồn tại trừ khi `-Force`.
- Giá trị ổn định phải giữ nguyên sau boot đầu.

`New-HarborConfig.ps1`:

- Đọc `.env.harbor`, render `infra/harbor/harbor.yml` từ `harbor.yml.tmpl`.
- Chặn `CHANGE_ME`, kí tự nguy hiểm, token thừa.

> **CHECKPOINT** — Dừng ở đây. Chạy preflight. Không được có `CHANGE_ME` trong file runtime.

```powershell
.\scripts\Test-LabConfig.ps1
```

`Test-LabConfig.ps1` kiểm tra: docker có, env files không còn `CHANGE_ME`, compose render đúng project name `devsecops-labs-*` + network `devsecops-labs-cicd`, cổng trống, tool k3d/kubectl/wsl. Preflight fail = không start. Fix lỗi trước khi đi tiếp.

## Phase startup theo stack — checkpoint từng phase

Bật lại theo thứ tự, verify từng stack trước khi sang stack kế.

### Phase A: GitLab

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml up -d
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml ps
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml logs -f gitlab
```

Verify:

```powershell
Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8929"
```

Boot đầu GitLab mất 5-15 phút. Runner chạy sau khi GitLab healthy.

> **CHECKPOINT** — Dừng ở đây. `http://localhost:8929` phải load trang login. Nếu GitLab restart vòng lặp, check RAM + logs. Không mở tiếp stack khác khi GitLab chưa stable.

### Phase B: Harbor

Render source config từ PowerShell:

```powershell
.\scripts\New-HarborConfig.ps1
wsl
```

Trong WSL, dùng runtime path không có khoảng trắng:

```bash
mkdir -p /home/duongnb/devsecops-harbor
cd /home/duongnb/devsecops-harbor
curl -fL -o harbor-offline-installer-v2.11.1.tgz \
  https://github.com/goharbor/harbor/releases/download/v2.11.1/harbor-offline-installer-v2.11.1.tgz
tar -xzf harbor-offline-installer-v2.11.1.tgz --strip-components=1
cp "/mnt/g/Cyber security/DevSecOps-labs/infra/harbor/harbor.yml" ./harbor.yml
./prepare
./install.sh --with-trivy
```

Verify từ PowerShell:

```powershell
Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8083/api/v2.0/health"
```

> **CHECKPOINT** — Dừng ở đây. `http://localhost:8083` load UI. Xác nhận `devsecops-lab` + `devsecops-candidate` còn (giữ lại từ lần trước) hoặc tạo lại.

### Phase C: Dependency-Track

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml up -d
```

Verify:

```powershell
Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8080/api/version"
```

> **CHECKPOINT** — Dừng ở đây. API trả HTTP 200. Project `devsecops-wordpress` version `lab` giữ được nếu bạn giữ volume postgres.

### Phase D: DefectDojo

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml up -d
```

Verify:

```powershell
Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8082"
```

> **CHECKPOINT** — Dừng ở đây. UI HTTP 200. Findings cũ giữ được nếu giữ volume postgres.

### Phase E: k3d + ArgoCD

```powershell
.\scripts\k3d-create-cluster.ps1
kubectl get nodes
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.7/manifests/install.yaml
kubectl -n argocd wait --for=condition=Available deployment --all --timeout=300s
```

Verify pull từ Harbor trước khi sync app:

```powershell
docker exec k3d-devsecops-gitops-server-0 crictl pull host.docker.internal:8083/devsecops-lab/wordpress@sha256:<digest>
```

> **CHECKPOINT** — Dừng ở đây. ArgoCD pods Running, crictl pull succeed, GitOps repo đã push lên GitLab. Chỉ khi đó apply ArgoCD Application. `host.docker.internal:8083` không reachable → tìm bridge gateway + recreate cluster.

## Failure recovery

### Startup fail vì thiếu network

```powershell
docker network create devsecops-labs-cicd
```

### Startup fail vì RAM

Tắt stack dư. Chạy lại từng phase theo docs. Không mở cùng lúc quá nhiều.

### Compose render fail

```powershell
docker compose --env-file .env.gitlab -f docker-compose.gitlab.yml config
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml config
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml config
```

Kiểm tra output có đúng project name + network. Nếu env file sai, sửa rồi chạy lại `Test-LabConfig.ps1`.

### Secret mất giá trị ổn định

Đã boot trước đó rồi đổi `DTRACK_ALPINE_SECRET_KEY` / `DD_SECRET_KEY` / `DD_CREDENTIAL_AES_256_KEY` → dữ liệu mã hóa không đọc được. Nếu còn bản sao của giá trị cũ, restore. Nếu không, chấp nhận mất data scan cũ và rebuild lại từ đầu.

### Wordpress MySQL volume mất

Kiểm tra `docker volume ls` xem có volume `devsecops-wordpress-local_db_data` không. Nếu không, pod sẽ dựng DB mới — content/upload mất. Không cố khôi phục từ xóa volume.

## Source repositories sau reset

Khi GitLab đã healthy, tự khởi tạo lại source app:

```powershell
Set-Location .\test_project
git init
git branch -M main
git add .
git commit -m "Initial WordPress test application"
git remote add origin http://localhost:8929/test-cicd/test_project.git
git push -u origin main
```

Khi tới chặng ArgoCD, tự tạo folder/repository mới:

```powershell
New-Item -ItemType Directory -Path 'G:\Cyber security\devsecops-gitops'
```

Sau đó tự viết manifests theo [GitOps examples](../../examples/gitops/) và push vào GitLab project `gitops/devsecops-gitops`.

## Kiểm tra hoàn tất

```powershell
.\scripts\Test-LabConfig.ps1 -Phase all
```

Preflight pass toàn bộ phase = configuration sẵn sàng cho flow mới.

## Failure exercises theo chặng

Không chỉ kiểm tra happy path. Sau mỗi chặng, tạo một lỗi có kiểm soát rồi phục hồi:

1. **GitLab persistence:** recreate container, xác nhận project vẫn còn.
2. **Runner:** tắt Runner, push commit, quan sát job pending; bật lại và quan sát job chạy.
3. **Harbor auth:** dùng robot token sai, xác nhận push bị từ chối; sửa token.
4. **DTrack:** upload SBOM có component vulnerable, xác nhận gate chặn.
5. **DefectDojo:** import cùng report hai lần, quan sát reimport/deduplication.
6. **Risk acceptance:** finding mới fail; exact acceptance có owner/ticket/expiry pass; expiry quá hạn fail.
7. **Promotion:** candidate có thể tồn tại, nhưng release chỉ xuất hiện sau gate; hai digest phải bằng nhau.
8. **ArgoCD:** sửa Deployment trực tiếp, quan sát drift/self-heal; rollback bằng Git revert.

Ghi lại lệnh, error, root cause và evidence. Đây là phần học quan trọng nhất của clean rebuild.
