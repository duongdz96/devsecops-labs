# DefectDojo — Tổng hợp lỗ hổng

DefectDojo nhận báo cáo từ nhiều scanner, tổng hợp findings, cung cấp API cho CI import + fail gate.

Lab chứng minh:

```text
GitLab CI (Trivy + Dependency-Check) -> DefectDojo import -> findings -> FAIL nếu HIGH/CRITICAL
```

## Thông số

- DefectDojo UI/API: `http://localhost:8082`
- Compose project: `devsecops-labs-dojo`
- Docker network: `devsecops-labs-cicd`
- App GitLab CI: `test-cicd/test_project`
- DefectDojo product: `devsecops-wordpress`
- Engagement: `gitlab-ci`

## Yêu cầu

- Docker Desktop + Docker Compose plugin.
- ~8GB RAM, 4 CPU.
- GitLab đang chạy tại `http://localhost:8929`.
- Cổng `8082` trống.

## Environment configuration

`.env.defectdojo` chứa cấu hình stack. Biến quan trọng:

| Biến | Mục đích |
| --- | --- |
| `DOJO_PORT` | Cổng host (mặc định `8082`). |
| `DD_SECRET_KEY` | Django secret key. **Giữ ổn định sau boot đầu**. Đổi = stored credential đọc không được. |
| `DD_CREDENTIAL_AES_256_KEY` | AES-256 key cho credentials. **Giữ ổn định**. |
| `DD_DATABASE_URL` | PostgreSQL connection string (compose tự expand từ `DOJO_DATABASE_PASSWORD`). |
| `DD_SITE_URL` | Public URL, mặc định `http://localhost:8082`. |

Không đổi `DD_SECRET_KEY` hay `DD_CREDENTIAL_AES_256_KEY` sau lần boot đầu trừ khi reset toàn bộ lab.

## Start DefectDojo

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml up -d
```

Check:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml ps
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml logs -f dojo-initializer
```

Boot đầu mất vài phút (migrations + initialization).

## Lấy admin password

DefectDojo sinh admin password trong initializer logs:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml logs dojo-initializer | Select-String "Admin password:"
```

Login:

```text
URL: http://localhost:8082
Username: admin
Password: giá trị trong initializer logs
```

Đổi admin password sau lần login đầu.

Nếu data đã init trước, password có thể không in ra nữa. Lúc đó dùng DefectDojo password reset hoặc reset lab data.

## Tạo API Token

Trong DefectDojo UI:

1. Login `admin`.
2. Mở user menu → **API v2 Key**.
3. Copy token.

Lưu token chỉ trong GitLab CI/CD variables, không commit.

## GitLab CI variables

Trong project `test-cicd/test_project`, **Settings > CI/CD > Variables**:

| Variable | Value |
| --- | --- |
| `DEFECTDOJO_URL` | `http://host.docker.internal:8082` |
| `DEFECTDOJO_API_KEY` | API token từ DefectDojo |
| `DEFECTDOJO_PRODUCT_NAME` | `devsecops-wordpress` |
| `DEFECTDOJO_ENGAGEMENT_NAME` | `gitlab-ci` |
| `DEFECTDOJO_MIN_SEVERITY` | `High` |

Dùng `host.docker.internal:8082` trên Docker Desktop để runner job container reach được host-published port.

Nếu runner job container nằm trên Docker network `devsecops-labs-cicd`, có thể dùng service name:

```text
http://dojo-nginx:8080
```

## Hành vi CI

`.gitlab-ci.yml` trong `test_project` có jobs:

- `trivy-fs-scan`
- `dependency-check-scan`
- `defectdojo-import`

### Trivy

1. Filesystem scan toàn bộ repo contents.
2. Ghi `trivy-fs-report.json`.
3. Lưu artifact.
4. Không fail trước import → DefectDojo nhận được report.

### Dependency-Check

1. OWASP Dependency-Check scan repo contents.
2. Ghi `dependency-check-report.json`.
3. Lưu artifact.
4. Không fail trước import.

### DefectDojo import

1. Download scanner artifacts.
2. `POST /api/v2/reimport-scan/`.
3. Import Trivy report: scan type `Trivy Scan`.
4. Import Dependency-Check report: scan type `Dependency Check Scan`.
5. `auto_create_context=true` tạo product/engagement nếu chưa có.
6. FAIL nếu có `HIGH` hoặc `CRITICAL` findings.

## Fail gate

Pipeline import reports trước, rồi fail khi scanner báo:

- `CRITICAL` finding
- `HIGH` finding

Reports giữ lại artifact ngay cả khi gate fail. DefectDojo nhận reports trước khi fail.

## Verify locally

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml config
```

Check UI:

```powershell
Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8082"
```

Expected: config command exit 0, UI HTTP 200, browser mở được `http://localhost:8082`.

## Verify từ GitLab CI

1. Commit `.gitlab-ci.yml` vào `test-cicd/test_project`.
2. Config CI variables.
3. Run pipeline.
4. Xác nhận artifacts: `trivy-fs-report.json`, `dependency-check-report.json`.
5. Mở DefectDojo UI → product `devsecops-wordpress` → engagement `gitlab-ci`.
6. Confirm imported tests/findings.
7. Confirm gate result khớp `HIGH`/`CRITICAL` findings.

## Stop DefectDojo

Giữ dữ liệu:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml down
```

Xóa hết:

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml down
Remove-Item -Recurse -Force .\defectdojo
```

## Ghi chú tài nguyên

~8GB RAM. DefectDojo tách khỏi GitLab để tắt khi không import findings.

Dependency-Check chạy chậm, tốn memory. Lần đầu download vulnerability data, có thể lâu.

If memory căng:

1. Stop stack không dùng.
2. Chạy GitLab + DefectDojo cho import test.
3. Không chạy Harbor + ArgoCD + DefectDojo + Dependency-Track đồng loạt.

## Troubleshooting

### UI không mở

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml ps
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml logs -f dojo-uwsgi dojo-nginx
```

### Admin password không thấy

```powershell
docker compose --env-file .env.defectdojo -f docker-compose.defectdojo.yml logs dojo-initializer | Select-String "Admin password:"
```

### GitLab CI không reach DefectDojo

Docker Desktop:

```text
DEFECTDOJO_URL=http://host.docker.internal:8082
```

Shared network `devsecops-labs-cicd`:

```text
DEFECTDOJO_URL=http://dojo-nginx:8080
```

### Import fail

Check:

- `DEFECTDOJO_API_KEY` đúng.
- `DEFECTDOJO_URL` reachable từ CI job container.
- Scan type names chính xác: `Trivy Scan`, `Dependency Check Scan`.
- Token có permission import scans.

### Pipeline fail vì HIGH/CRITICAL

Mở DefectDojo UI → product `devsecops-wordpress` → engagement `gitlab-ci` → review findings. Fix component hoặc mark false positive sau khi verified.
