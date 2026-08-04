# Harbor Registry Lab

Harbor là registry nội bộ cho lab. GitLab CI build image WordPress từ app `test_project`, push lên Harbor, sau đó k3d + ArgoCD pull về deploy.

Lab này chứng minh:

```text
GitLab CI -> Docker build -> Harbor push -> image visible trong Harbor UI
```

## Thông số

- Harbor UI/registry: `http://localhost:8083`
- Harbor project candidate: `devsecops-candidate`
- Harbor project release: `devsecops-lab`
- Image: `wordpress` (tham chiếu theo digest, không theo tag `latest` ở release)
- GitLab: `http://localhost:8929`
- App GitLab CI: `test-cicd/test_project`
- Config: `infra/harbor/harbor.yml` (runtime, gitignored — template `infra/harbor/harbor.yml.tmpl`)

## Yêu cầu

- Docker Desktop (hoặc Docker Engine) + Docker Compose plugin.
- WSL2 shell Linux để chạy installer chính thức của Harbor (script `prepare`/`install.sh` là Linux executable).
- GitLab đang chạy tại `http://localhost:8929` khi test CI push.
- Cổng `8083` trống trên host.
- ~8GB RAM, 4 CPU.

Harbor trong lab là registry **HTTP**, không phải bản production hardened.

## Chiến lược tài nguyên

Máy ~8GB RAM, không bật toàn bộ stack cùng lúc.

Chỉ setup Harbor UI:

- Harbor bật.
- GitLab tắt được cho tới khi test CI push.
- Dependency-Track, DefectDojo tắt.
- k3d + ArgoCD đứng yên tới phase sau.

Test CI push:

- Harbor + GitLab + GitLab Runner bật.
- Dependency-Track, DefectDojo tắt nếu RAM căng.

Tắt stack không cần:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml down
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml down
```

## Cấu hình Harbor (template → runtime)

Không sửa `harbor.yml` tay rồi commit. Quy trình:

1. `.env.harbor` chứa giá trị thật (gitignored), render ra `infra/harbor/harbor.yml`:
   - `New-LabSecrets.ps1`: sinh lần đầu, tạo `.env.harbor` từ `.env.harbor.example`.
   - `New-HarborConfig.ps1`: đọc `.env.harbor` → render `infra/harbor/harbor.yml` từ `harbor.yml.tmpl`.

```powershell
.\scripts\New-LabSecrets.ps1
.\scripts\New-HarborConfig.ps1
```

2. `New-HarborConfig.ps1` tự chặn: value rỗng, còn `CHANGE_ME`, kí tự control, dấu `'`. Template dùng token `__HARBOR_*__`; script báo lỗi nếu output còn token thừa.

3. `harbor.yml.tmpl` có git; `harbor.yml` gitignored. Đổi cấu hình thì sửa `.env.harbor` (hoặc template nếu cần) rồi render lại + chạy lại prepare/install.

Giá trị quan trọng:

```yaml
hostname: host.docker.internal
http:
  port: 8083
harbor_admin_password: <từ .env.harbor>
data_volume: ./data
```

`hostname` là `host.docker.internal` để Docker-in-Docker và k3d nhận được token realm mà chúng truy cập được. Trình duyệt vẫn mở được `http://localhost:8083` vì Harbor publish cổng `8083`.

Output do installer sinh ra bị gitignore:

```text
infra/harbor/common/
infra/harbor/data/
infra/harbor/docker-compose.yml
infra/harbor/install.sh
infra/harbor/prepare
```

Không sửa tay file trong `common/`. Đổi `harbor.yml`, render lại, chạy lại prepare/install.

## Cài Harbor

Harbor installer là Linux shell tooling. Không chạy `prepare/install.sh` trực tiếp dưới path `/mnt/g/Cyber security/...`: khoảng trắng từng làm installer tách sai path. Source config vẫn ở repo; generated runtime đặt trong WSL path không có khoảng trắng.

Từ PowerShell, render `infra/harbor/harbor.yml`, rồi mở WSL:

```powershell
.\scripts\New-HarborConfig.ps1
wsl
```

Trong WSL, tạo runtime sạch:

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

Nếu Docker không thấy từ WSL, bật **Docker Desktop > Resources > WSL Integration** cho distro rồi thử lại. Chỉ dùng `sudo` nếu Docker daemon của distro thực sự yêu cầu nó.

Source/runtime separation:

```text
G:\Cyber security\DevSecOps-labs\infra\harbor\harbor.yml.tmpl  tracked template
G:\Cyber security\DevSecOps-labs\infra\harbor\harbor.yml       generated secret config, ignored
/home/duongnb/devsecops-harbor/                                  generated Harbor runtime
```

## Start Harbor

Sau install, quản lý Harbor từ WSL runtime:

```bash
cd /home/duongnb/devsecops-harbor
docker compose up -d
docker compose ps
```

Harbor logging dùng syslog container. Nếu service khác báo `connect: connection refused` tới `127.0.0.1:1514`, start `log`, chờ healthy/port ready, rồi start phần còn lại:

```bash
docker compose up -d log
until docker inspect --format '{{.State.Health.Status}}' harbor-log 2>/dev/null | grep -q healthy; do sleep 2; done
docker compose up -d
```

Service kỳ vọng:

```text
log
registry
registryctl
postgresql
core
portal
jobservice
redis
proxy
```

Mở UI:

```text
http://localhost:8083
```

Login:

```text
Username: admin
Password: <HARBOR_ADMIN_PASSWORD trong .env.harbor>
```

Đổi admin password sau lần login đầu nếu muốn giữ dữ liệu lab.

## Tạo project + robot account

Lab dùng hai project:

| Project | Mục đích |
| --- | --- |
| `devsecops-candidate` | CI push image build thô, tag theo digest/tag tạm |
| `devsecops-lab` | Release: image đã pass gate, tham chiếu **theo digest** trong manifest GitOps |

Trong Harbor UI:

1. **Projects → New Project**: tạo `devsecops-candidate` và `devsecops-lab`. Giữ private trừ khi cố tình cho pull anonymous.
2. Tạo robot theo least privilege:
   - `candidate-ci`: Pull + Push trong `devsecops-candidate`.
   - `release-promoter`: Pull candidate + Pull/Push trong `devsecops-lab`.
   - `k3d-pull`: chỉ Pull trong `devsecops-lab`.
   - Copy từng robot username + token; không dùng chung token.

Username robot thường dạng:

```text
robot$devsecops-candidate+gitlab-ci
```

Lưu token chỉ trong GitLab CI/CD variables, không commit.

## Cấu hình Docker Desktop insecure registry

Docker host phải tin Harbor qua HTTP.

**Settings → Docker Engine**, thêm:

```json
{
  "insecure-registries": [
    "localhost:8083",
    "host.docker.internal:8083"
  ]
}
```

Nếu JSON đã có key khác, giữ nguyên và chỉ thêm `insecure-registries`. Apply rồi restart Docker Desktop.

Verify:

```powershell
docker login localhost:8083
```

## GitLab CI variables

Tạo hai robot accounts theo least privilege:

- Candidate robot: pull/push trong `devsecops-candidate`.
- Release robot: pull candidate + pull/push trong `devsecops-lab` để promotion.

Trong project `test-cicd/test_project`, thêm masked/protected variables:

| Variable | Value |
| --- | --- |
| `HARBOR_URL` | `host.docker.internal:8083` |
| `HARBOR_CANDIDATE_ROBOT_USER` | candidate robot username |
| `HARBOR_CANDIDATE_ROBOT_TOKEN` | candidate robot token |
| `HARBOR_RELEASE_ROBOT_USER` | release robot username |
| `HARBOR_RELEASE_ROBOT_TOKEN` | release robot token |

Project/image names đã có defaults trong pipeline: `devsecops-candidate`, `devsecops-lab`, `wordpress`.

## Hành vi CI build-once/promote

`.gitlab-ci.yml` dùng luồng:

```text
validate -> test -> build-candidate -> security -> promote
```

1. `docker-build-candidate` build một lần, push đúng tag `${CI_COMMIT_SHA}` vào candidate project và ghi immutable digest vào `candidate.env`.
2. Trivy và Syft đọc đúng candidate digest.
3. Policy gate chặn HIGH/CRITICAL chưa có exact, time-bound risk acceptance.
4. `promote-release` dùng Crane copy cùng artifact sang `devsecops-lab/wordpress:${CI_COMMIT_SHA}`; không rebuild.
5. Job so sánh candidate/release digest. Khác digest = fail.
6. Pipeline không tạo hoặc phụ thuộc tag `latest`.

## Chạy pipeline

1. Harbor, GitLab và Runner healthy.
2. Push source/config vào `test-cicd/test_project`.
3. Cấu hình CI variables ở trên cùng DTrack/DefectDojo variables.
4. Run pipeline.
5. Xác nhận vulnerable finding chưa accepted làm `security-policy-gate` fail.
6. Xác nhận artifact đạt policy làm `promote-release` pass.

## Verify image trong Harbor

Harbor UI:

1. Candidate repository có tag full commit SHA.
2. Release repository chỉ có tag được promote sau gate.
3. Copy digest từ `candidate.env` và `release.env`; hai giá trị phải bằng nhau.

Pull immutable release từ host:

```powershell
docker pull host.docker.internal:8083/devsecops-lab/wordpress@sha256:<digest>
```

## Stop/start Harbor

Trong WSL:

```bash
cd /home/duongnb/devsecops-harbor
docker compose down       # giữ data
docker compose up -d
```

## Xóa dữ liệu Harbor

Thực hiện theo [clean rebuild runbook](../clean-rebuild/README.md). Không dùng prune toàn host.

## Troubleshooting

### Cổng 8083 bị chiếm

```powershell
netstat -ano | Select-String ":8083"
```

Dừng service xung đột hoặc đổi `http.port` trong `.env.harbor` → render lại `harbor.yml` → prepare/install lại.

### Browser không mở được UI

```powershell
docker compose -f .\infra\harbor\docker-compose.yml ps
docker compose -f .\infra\harbor\docker-compose.yml logs -f proxy core portal
```

### Docker báo lỗi HTTP registry

Lỗi điển hình:

```text
server gave HTTP response to HTTPS client
```

Cấu hình insecure registry cho cả `localhost:8083` lẫn `host.docker.internal:8083`, restart Docker Desktop, thử lại:

```powershell
docker login localhost:8083
docker login host.docker.internal:8083
```

### GitLab CI không reach được Harbor

CI variable:

```text
HARBOR_URL=host.docker.internal:8083
```

DinD service trong job phải khởi động với:

```text
--insecure-registry=host.docker.internal:8083
```

Nếu không dùng Docker Desktop (Linux host thật), thay `host.docker.internal` bằng địa chỉ reach được từ job container, đồng bộ cả `HARBOR_URL` lẫn lệnh DinD.

### Robot login fail

Check:

- `HARBOR_ROBOT_USER` khớp chính xác robot username.
- `HARBOR_ROBOT_TOKEN` copy đúng.
- Robot chưa hết hạn.
- Robot có `Pull` + `Push` trên đúng project.
- Project name chính xác `devsecops-candidate` / `devsecops-lab`.

### Push denied

1. Project tồn tại.
2. Robot thuộc project.
3. Robot có push permission.
4. CI push đúng `host.docker.internal:8083/devsecops-<tên>/wordpress`.

### Low memory

Triệu chứng: Harbor service restart, runner job treo, Docker Desktop chậm.

Giảm tải:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml down
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml down
```

Chỉ chạy Harbor + GitLab + Runner khi test push.
