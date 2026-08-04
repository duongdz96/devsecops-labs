# Dependency-Track — SBOM + Fail Gate

Dependency-Track nhận SBOM, quét component lỗ hổng, trả về metrics → CI fail gate.

Lab này chứng minh:

```text
GitLab CI -> generate SBOM -> Dependency-Track ingest -> metrics -> FAIL nếu HIGH/CRITICAL
```

## Thông số

- Dependency-Track API: `http://localhost:8080`
- Dependency-Track UI: `http://localhost:8081`
- Compose project: `devsecops-labs-dtrack`
- Docker network: `devsecops-labs-cicd`
- App GitLab CI: `test-cicd/test_project`
- Dependency-Track project: `devsecops-wordpress`
- Version: `lab`

## Yêu cầu

- Docker Desktop + Docker Compose plugin.
- ~8GB RAM, 4 CPU.
- GitLab đang chạy tại `http://localhost:8929`.
- Cổng `8080` (API) và `8081` (UI) trống.

## Environment configuration

`.env.dependency-track` chứa cấu hình stack. Biến quan trọng:

| Biến | Mục đích |
| --- | --- |
| `DTRACK_ALPINE_SECRET_KEY` | 64-char hex, mã hóa API key. Phải giữ ổn định sau boot đầu. Đổi = mất key. |
| `DTRACK_API_PORT` | Cổng host API (mặc định `8080`). |
| `DTRACK_FRONTEND_PORT` | Cổng host UI (mặc định `8081`). |
| `DTRACK_POSTGRES_PASSWORD` | Password PostgreSQL cho DB `dtrack`. |

CORS chỉ cho phép origin `http://localhost:${DTRACK_FRONTEND_PORT}`. Không dùng wildcard `*`.

## Start Dependency-Track

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml up -d
```

Check:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml ps
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml logs -f dtrack-apiserver
```

Boot đầu mất vài phút. Vulnerability intelligence sync có lâu hơn sau lần login đầu.

## Login

UI: `http://localhost:8081`

```text
Username: admin
Password: admin
```

Đổi password admin ngay sau lần login đầu.

## Tạo API Key

1. **Administration → Access Management → Teams**.
2. Chọn team CI hoặc tạo mới.
3. Thêm quyền BOM upload + project access.
4. Generate API key → copy.

Lưu API key chỉ trong GitLab CI/CD variables, không commit.

## GitLab CI variables

Trong project `test-cicd/test_project`, **Settings > CI/CD > Variables**:

| Variable | Value |
| --- | --- |
| `DTRACK_API_URL` | `http://host.docker.internal:8080` |
| `DTRACK_API_KEY` | API key từ Dependency-Track |
| `DTRACK_PROJECT_NAME` | `devsecops-wordpress` |
| `DTRACK_PROJECT_VERSION` | `lab` |
| `DTRACK_FAIL_ON_SEVERITY` | `HIGH` |

Dùng `host.docker.internal:8080` trên Docker Desktop để runner job container reach được cổng host-published.

Nếu runner job container nằm trên Docker network `devsecops-labs-cicd`, có thể dùng service name:

```text
http://dtrack-apiserver:8080
```

## Hành vi CI

`.gitlab-ci.yml` có job `dependency-track-sbom`:

1. Cài Syft trong Alpine CI container.
2. Tạo CycloneDX JSON SBOM: `gl-sbom.cdx.json`.
3. Upload lên Dependency-Track: `POST /api/v1/bom?autoCreate=true`.
4. Project `devsecops-wordpress` version `lab` tự tạo nếu chưa có.
5. Poll BOM processing token → chờ finish hoặc timeout.
6. Lookup project UUID.
7. Query project metrics.
8. FAIL nếu `critical > 0`.
9. FAIL nếu `DTRACK_FAIL_ON_SEVERITY=HIGH` và `high > 0`.
10. Lưu `gl-sbom.cdx.json` artifact 7 ngày.

## Fail gate

Threshold mặc định: `HIGH`.

Pipeline fail khi Dependency-Track báo:

- `CRITICAL` vulnerable component
- `HIGH` vulnerable component

Pipeline pass chỉ khi:

- SBOM generation/upload succeed
- BOM processing finish trước timeout
- project metrics đọc được
- không có `HIGH`/`CRITICAL`

Giảm xuống `CRITICAL` only (lab troubleshooting):

```text
DTRACK_FAIL_ON_SEVERITY=CRITICAL
```

## Verify locally

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml config
```

Check API:

```powershell
Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8080/api/version"
```

Check UI: `http://localhost:8081`

Expected: API trả HTTP 200, UI trả HTTP 200, browser mở được.

## Verify từ GitLab CI

1. Commit `.gitlab-ci.yml` vào `test-cicd/test_project`.
2. Config CI variables.
3. Run pipeline.
4. Xác nhận artifact `gl-sbom.cdx.json` tồn tại.
5. Mở Dependency-Track UI → project `devsecops-wordpress` version `lab`.
6. Confirm components xuất hiện.
7. Confirm gate result khớp metrics `HIGH`/`CRITICAL`.

## Stop Dependency-Track

Giữ dữ liệu:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml down
```

Xóa hết:

```powershell
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml down
Remove-Item -Recurse -Force .\dependency-track
```

## Ghi chú tài nguyên

~8GB RAM. Dependency-Track tách khỏi GitLab để có thể tắt khi không scan.

If memory căng:

1. Stop stack không dùng.
2. Chạy GitLab + Dependency-Track chỉ cho SBOM test.
3. Không chạy Harbor + ArgoCD + DefectDojo + Dependency-Track đồng loạt.

## Troubleshooting

### UI không reach API

```powershell
Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8080/api/version"
docker compose --env-file .env.dependency-track -f docker-compose.dependency-track.yml logs -f dtrack-apiserver
```

### GitLab CI không reach Dependency-Track

Docker Desktop:

```text
DTRACK_API_URL=http://host.docker.internal:8080
```

Shared network:

```text
DTRACK_API_URL=http://dtrack-apiserver:8080
```

### Pipeline fail vì HIGH/CRITICAL

Mở Dependency-Track UI → project `devsecops-wordpress` → version `lab` → review vulnerabilities. Fix component hoặc suppress nếu verified false positive.

### BOM processing timeout

Dependency-Track có thể vẫn đang sync vulnerability data. Re-run pipeline sau khi API stable. Timeout fail closed — không treat missing data as pass.
