# SLSA, OWASP DSOMM và OpenSSF trong DevSecOps

> Tài liệu nền tảng phục vụ phỏng vấn DevSecOps và chuẩn bị xây dựng một pipeline bảo mật end-to-end.
>
> Cập nhật: 18/07/2026.

## Mục lục

1. [Bức tranh tổng thể](#1-bức-tranh-tổng-thể)
2. [SLSA](#2-slsa)
3. [OWASP DSOMM](#3-owasp-dsomm)
4. [OpenSSF](#4-openssf)
5. [So sánh ba khái niệm](#5-so-sánh-ba-khái-niệm)
6. [Cách áp dụng vào một hệ thống DevSecOps](#6-cách-áp-dụng-vào-một-hệ-thống-devsecops)
7. [Câu hỏi phỏng vấn và câu trả lời gợi ý](#7-câu-hỏi-phỏng-vấn-và-câu-trả-lời-gợi-ý)
8. [Checklist học và thực hành](#8-checklist-học-và-thực-hành)
9. [Tài liệu tham khảo chính thức](#9-tài-liệu-tham-khảo-chính-thức)

---

## 1. Bức tranh tổng thể

Ba khái niệm này đều liên quan đến bảo mật phần mềm, nhưng giải quyết ba bài toán khác nhau:

| Khái niệm | Bản chất | Câu hỏi chính mà nó trả lời |
|---|---|---|
| **SLSA** | Framework và đặc tả về tính toàn vẹn của chuỗi cung ứng phần mềm | Artifact này có thực sự được tạo ra từ đúng source, bằng đúng quy trình build và có bị can thiệp hay không? |
| **OWASP DSOMM** | Mô hình trưởng thành DevSecOps | Tổ chức hiện đang trưởng thành tới đâu và nên ưu tiên cải thiện hoạt động bảo mật nào tiếp theo? |
| **OpenSSF** | Foundation/cộng đồng cùng hệ sinh thái dự án bảo mật mã nguồn mở | Làm thế nào đánh giá, cải thiện và bảo vệ phần mềm mã nguồn mở cùng các dependency được sử dụng? |

Có thể nhớ bằng ba cụm từ:

- **SLSA = integrity và provenance của artifact**.
- **DSOMM = maturity và lộ trình cải tiến DevSecOps**.
- **OpenSSF = hệ sinh thái bảo mật open source và software supply chain**.

Một nhầm lẫn phổ biến là coi cả ba là các công cụ scan. Điều này không đúng:

- SLSA không phải vulnerability scanner.
- DSOMM không phải sản phẩm CI/CD.
- OpenSSF không phải một công cụ đơn lẻ; đây là một tổ chức với nhiều dự án, tiêu chuẩn, hướng dẫn và công cụ.

---

## 2. SLSA

### 2.1. SLSA là gì?

**SLSA** là viết tắt của **Supply-chain Levels for Software Artifacts**, đọc gần giống “salsa”. Đây là một framework và đặc tả dùng để mô tả, đo lường và tăng dần mức bảo đảm an toàn cho chuỗi cung ứng phần mềm.

SLSA tập trung vào việc ngăn chặn hoặc làm giảm khả năng xảy ra các hành vi như:

- Thay đổi source trái phép.
- Chèn mã độc vào quá trình build.
- Thay thế artifact sau khi build.
- Làm giả metadata hoặc provenance.
- Build từ source, dependency hoặc cấu hình không đúng.
- Đưa lên production một artifact khác với artifact đã được kiểm tra.

SLSA là **một tập yêu cầu và mức bảo đảm**, không bắt buộc phải dùng một vendor cụ thể.

Đặc tả ổn định hiện hành được tài liệu chính thức công bố là **SLSA v1.2**.

### 2.2. Chuỗi cung ứng phần mềm là gì?

Chuỗi cung ứng phần mềm không chỉ gồm source code. Một chuỗi điển hình có thể gồm:

```text
Developer
  -> Source repository
  -> Dependencies
  -> CI/CD runner
  -> Build toolchain
  -> Artifact/Image
  -> Registry
  -> Deployment manifests
  -> Production
```

Mỗi mắt xích có thể trở thành điểm tấn công. Ví dụ:

- Tài khoản Git bị chiếm quyền.
- Branch protection bị bỏ qua.
- Dependency bị đầu độc.
- Runner dùng chung bị compromise.
- Build script tải binary không được kiểm chứng.
- Image tag bị ghi đè.
- Kẻ tấn công push một image khác lên registry.
- Production triển khai bằng `latest`, không phải digest đã kiểm tra.

SLSA không loại bỏ mọi rủi ro, nhưng cung cấp cách diễn đạt rõ ràng về mức độ tin cậy của source, build và artifact.

### 2.3. Các khái niệm quan trọng

#### Artifact

Artifact là đầu ra của quá trình build, ví dụ:

- File `.jar`, `.war`, `.exe`, package npm hoặc Python wheel.
- Container image.
- Firmware.
- Binary release.
- SBOM hoặc metadata liên quan, tùy ngữ cảnh.

#### Provenance

**Provenance** là thông tin có thể xác minh về nguồn gốc và quá trình tạo artifact.

Nó thường trả lời các câu hỏi:

- Artifact nào đã được tạo?
- Được build từ repository và commit nào?
- Build bằng workflow hoặc build definition nào?
- Builder nào thực hiện build?
- Những input nào được sử dụng?
- Quá trình build diễn ra khi nào?
- Provenance có được ký hay bảo vệ khỏi chỉnh sửa không?

Provenance có thể được hình dung như “giấy khai sinh có thể kiểm chứng” của artifact.

Ví dụ logic:

```text
image digest: sha256:abc...
source repo: git.example.com/team/payment-api
source commit: 1f84c2...
build workflow: .gitlab-ci.yml@1f84c2...
builder: protected-gitlab-runner-prod
build time: 2026-07-18T08:30:00Z
```

Provenance **không đồng nghĩa** với SBOM:

| Provenance | SBOM |
|---|---|
| Mô tả artifact được tạo ở đâu, khi nào, bằng quy trình và input nào | Liệt kê các component/dependency có trong phần mềm |
| Trọng tâm là nguồn gốc và tính toàn vẹn quá trình build | Trọng tâm là thành phần, phiên bản, license và quan hệ dependency |
| Hỗ trợ xác minh artifact có đến từ builder đáng tin cậy hay không | Hỗ trợ phân tích CVE, license và exposure của dependency |

Hai loại metadata này bổ sung cho nhau.

#### Attestation

Attestation là một tuyên bố có cấu trúc về một artifact hoặc một bước trong supply chain, thường có thể được ký và xác minh.

Provenance là một loại attestation. Các attestation khác có thể biểu diễn:

- Kết quả scan.
- SBOM.
- Kết quả test.
- Policy compliance.
- Vulnerability status.

#### Builder

Builder là hệ thống thực hiện build, chẳng hạn:

- GitLab Runner.
- GitHub Actions hosted runner.
- Jenkins agent.
- Tekton pipeline.
- Một dịch vụ build nội bộ.

Ở mức bảo đảm cao, builder cần được kiểm soát, cô lập và làm cứng để giảm khả năng người dùng hoặc một build khác can thiệp vào build hiện tại.

#### Artifact digest

Digest là định danh dựa trên nội dung, ví dụ `sha256:...`.

- Tag như `1.0.0` hoặc `latest` có thể bị thay đổi để trỏ tới nội dung khác.
- Digest gắn với nội dung cụ thể.

Do đó, production nên triển khai bằng digest khi cần bảo đảm rằng artifact đã deploy chính là artifact đã scan và phê duyệt.

### 2.4. Tracks và levels

SLSA v1.2 tổ chức các yêu cầu thành các **track**. Mỗi track tập trung vào một phần của supply chain và có hệ thống mức bảo đảm riêng.

Hai track quan trọng cần nắm chắc khi phỏng vấn là:

- **Build Track**: mức tin cậy của quá trình tạo artifact và provenance.
- **Source Track**: mức bảo đảm đối với hệ thống quản lý source và thay đổi source.

Điểm quan trọng: không nên nói chung chung rằng “hệ thống đạt SLSA Level X” mà không nêu rõ **track**. Cách nói chính xác hơn là “đạt Build L2” hoặc “đáp ứng Source L3”, vì các track có yêu cầu và cấp độ khác nhau.

### 2.5. Build Track

Build Track mô tả mức tăng dần về độ tin cậy của provenance và môi trường build.

| Mức | Ý nghĩa khái quát | Trọng tâm |
|---|---|---|
| **Build L0** | Không có bảo đảm SLSA | Chưa có yêu cầu |
| **Build L1** | Có provenance mô tả cách artifact được build | Khả năng truy vết, giảm sai sót và thiếu tài liệu |
| **Build L2** | Provenance được ký, được tạo bởi hosted build platform | Chống sửa artifact/provenance sau build |
| **Build L3** | Build platform được làm cứng, tăng bảo vệ trước can thiệp trong lúc build | Chống giả mạo hoặc can thiệp vào quá trình build |

#### Build L0

- Không có yêu cầu cụ thể.
- Có thể build thủ công trên laptop.
- Không có provenance hoặc không thể xác minh nguồn gốc artifact.

#### Build L1

- Artifact có provenance.
- Có thể biết artifact được build từ đâu và bằng cách nào.
- Mức này giúp traceability nhưng chưa đủ để chống người build sửa provenance hoặc artifact.

Ví dụ:

- Pipeline tạo một file provenance gắn commit SHA với image digest.
- Provenance được lưu cùng release.

#### Build L2

- Sử dụng hosted build platform.
- Provenance được tạo bởi build platform, không chỉ do script tùy ý của người dùng tự khai báo.
- Provenance được ký hoặc được bảo vệ để consumer có thể xác minh.
- Giảm rủi ro artifact hoặc provenance bị thay đổi sau khi build.

Ví dụ:

- GitLab pipeline chạy trên runner được quản trị tập trung.
- Builder phát hành provenance có chữ ký.
- Consumer xác minh chữ ký và identity của builder trước khi deploy.

#### Build L3

- Build platform được làm cứng.
- Có cơ chế cô lập và kiểm soát để giảm khả năng một build, người vận hành hoặc người dùng can thiệp trái phép vào build khác.
- Build definition và provenance phải đáp ứng các yêu cầu chặt hơn.

Cần tránh diễn giải Build L3 thành “phần mềm không có lỗ hổng”. SLSA Build L3 nói về **tính toàn vẹn của build**, không bảo đảm code không có bug, không có CVE hay không có logic độc hại từ source hợp lệ.

### 2.6. Source Track

Source Track tập trung vào mức bảo đảm của hệ thống source control và quy trình thay đổi source.

Theo SLSA v1.2, các mức chính được mô tả khái quát như sau:

| Mức | Ý nghĩa khái quát |
|---|---|
| **Source L1** | Source được quản lý phiên bản |
| **Source L2** | Có history và provenance phù hợp cho source |
| **Source L3** | Có các technical control được thực thi liên tục |
| **Source L4** | Thay đổi quan trọng được kiểm soát theo nguyên tắc hai người/two-party review |

Ví dụ control liên quan:

- Repository không cho phép force-push vào protected branch.
- Merge Request bắt buộc trước khi merge.
- CI status phải pass.
- Commit hoặc tag release có thể được ký.
- Hai người độc lập tham gia phê duyệt thay đổi nhạy cảm.
- Quyền admin repository được giới hạn và audit.

Two-party review giúp giảm insider risk, nhưng chỉ hiệu quả khi:

- Reviewer thực sự độc lập.
- Không thể tự phê duyệt MR của chính mình.
- Quyền bypass được hạn chế.
- Review được lưu audit trail.

### 2.7. SLSA bảo vệ và không bảo vệ điều gì?

#### SLSA hỗ trợ bảo vệ

- Tính toàn vẹn của source và lịch sử thay đổi.
- Khả năng truy vết artifact về source và build process.
- Chống thay thế artifact sau build.
- Chống làm giả provenance.
- Giảm nguy cơ build bị can thiệp.
- Tạo cơ sở để consumer áp dụng policy trước deployment.

#### SLSA không tự động bảo vệ

- Lỗ hổng logic trong source code.
- CVE trong dependency.
- Secret bị hard-code.
- Misconfiguration Kubernetes.
- Một dependency độc hại đã được chọn hợp lệ và build đúng quy trình.
- Tài khoản production bị chiếm quyền sau khi deploy.

Do đó, SLSA cần kết hợp với SAST, SCA, secret scanning, image scanning, policy-as-code, runtime security và quản trị truy cập.

### 2.8. Một luồng SLSA thực tế

```text
1. Developer tạo Merge Request.
2. Protected branch yêu cầu review và CI pass.
3. Hosted runner checkout đúng commit SHA.
4. Pipeline build container image.
5. Pipeline tạo SBOM.
6. Builder tạo provenance gắn commit với image digest.
7. Image, SBOM và provenance được ký hoặc attested.
8. Image được push vào registry có immutability policy.
9. GitOps repository tham chiếu image bằng digest.
10. Admission policy xác minh signature/provenance trước khi cho chạy.
```

### 2.9. Ví dụ policy xác minh

Trước khi deployment, tổ chức có thể yêu cầu:

- Image phải đến từ registry của công ty.
- Image phải có chữ ký hợp lệ.
- Signer phải là identity của CI builder được phép.
- Provenance phải tham chiếu repository đúng.
- Commit phải thuộc protected branch.
- Image digest trong deployment phải khớp digest trong provenance.
- Artifact phải có SBOM.
- Scan result không được có Critical vulnerability vượt policy.

Không phải tất cả các điều kiện trên đều là yêu cầu SLSA; đây là cách kết hợp SLSA với các security control khác.

### 2.10. Các lỗi diễn đạt thường gặp về SLSA

**Sai:** “Có SBOM là đạt SLSA.”  
**Đúng:** SBOM hữu ích cho supply-chain security, nhưng SLSA tập trung mạnh vào provenance và tính toàn vẹn của source/build/artifact.

**Sai:** “Ký image là đạt SLSA L3.”  
**Đúng:** Ký artifact chỉ giải quyết một phần. L3 còn phụ thuộc vào yêu cầu của builder và mức làm cứng build platform.

**Sai:** “SLSA L3 nghĩa là phần mềm an toàn.”  
**Đúng:** L3 cung cấp bảo đảm mạnh hơn về build integrity, không chứng minh phần mềm không có lỗ hổng.

**Sai:** “Chỉ cần khai báo pipeline đạt SLSA.”  
**Đúng:** Consumer cần khả năng xác minh bằng chứng, provenance, identity của builder và policy tương ứng.

---

## 3. OWASP DSOMM

### 3.1. DSOMM là gì?

**OWASP DSOMM** là viết tắt của **DevSecOps Maturity Model**. Đây là một framework của OWASP giúp tổ chức:

- Đánh giá mức trưởng thành hiện tại của DevSecOps.
- Xác định khoảng trống về con người, quy trình và công nghệ.
- Chọn các hoạt động bảo mật cần ưu tiên.
- Xây dựng lộ trình cải tiến theo từng bước.
- Theo dõi bằng chứng và tiến độ triển khai control.

DSOMM không chỉ hỏi “có dùng tool hay không”, mà quan tâm hoạt động bảo mật có được chuẩn hóa, tự động hóa, đo lường và áp dụng nhất quán hay chưa.

Theo ứng dụng DSOMM chính thức, model và application được phát hành độc lập. Tại thời điểm tài liệu này được cập nhật, trang settings của DSOMM công bố model **v4.2.0**, phát hành ngày **16/04/2026**.

### 3.2. Tại sao cần maturity model?

Một tổ chức không thể triển khai mọi control cùng lúc. Ví dụ:

- Có SAST nhưng không ai triage findings.
- Có scanner nhưng pipeline không có gate.
- Có gate nhưng exception tồn tại vô thời hạn.
- Có SBOM nhưng không theo dõi CVE mới sau release.
- Có log nhưng không có alert hoặc owner xử lý.
- Có policy nhưng mỗi team áp dụng một kiểu.

Maturity model giúp chuyển câu hỏi từ:

> “Chúng ta đã mua hoặc cài công cụ gì?”

sang:

> “Hoạt động bảo mật nào đang được thực hiện, hiệu quả ra sao, có bằng chứng gì, áp dụng tới phạm vi nào và bước cải tiến tiếp theo là gì?”

### 3.3. Cách hiểu các mức trưởng thành

DSOMM sử dụng các mức trưởng thành để mô tả quá trình tiến hóa của hoạt động bảo mật. Tên và chi tiết hoạt động cần tra theo model phiên bản đang áp dụng; về mặt tư duy, có thể hiểu lộ trình tổng quát như sau:

| Giai đoạn | Đặc điểm điển hình |
|---|---|
| **Chưa hình thành** | Hoạt động bảo mật rời rạc, phụ thuộc cá nhân, thiếu bằng chứng |
| **Cơ bản** | Một số kiểm tra đã có, thường thủ công hoặc chỉ áp dụng cho dự án quan trọng |
| **Được quản lý** | Có quy trình, owner, tiêu chí và phạm vi áp dụng rõ hơn |
| **Tự động hóa/đo lường** | Control được tích hợp pipeline, có metric và theo dõi xu hướng |
| **Tối ưu hóa** | Risk-based, cải tiến liên tục, exception được quản trị và control được kiểm chứng hiệu quả |

Không nên hiểu maturity cao là “càng nhiều tool càng tốt”. Maturity cao là control phù hợp với rủi ro, có hiệu quả, có ownership, có bằng chứng và được cải tiến liên tục.

### 3.4. Các nhóm hoạt động điển hình

DSOMM bao phủ nhiều mặt của DevSecOps. Tùy phiên bản model, cách đặt tên và phân nhóm có thể thay đổi. Khi học, nên tập trung vào các nhóm thực tiễn sau:

#### Build và deployment

- Pipeline-as-code.
- Build có thể tái lập và truy vết.
- Artifact repository/registry được kiểm soát.
- Artifact signing và verification.
- Secret được lấy từ secret manager.
- Production deployment có approval hoặc policy phù hợp.
- Không build lại artifact giữa các môi trường.

#### Test và verification

- Unit/integration/security testing.
- SAST.
- DAST.
- SCA/dependency scanning.
- Container scanning.
- IaC/Kubernetes scanning.
- Secret scanning.
- Fuzzing hoặc specialized testing khi phù hợp.

#### Culture và organization

- Security champion.
- Secure coding training.
- Phân định trách nhiệm giữa Dev, Sec và Ops.
- Blameless learning sau incident.
- Threat modeling có sự tham gia của nhiều vai trò.
- Cơ chế tư vấn và escalation.

#### Information gathering

- Inventory ứng dụng và owner.
- Danh mục dependency/SBOM.
- Threat intelligence.
- Phân loại dữ liệu.
- Risk assessment.
- Theo dõi vulnerability và trạng thái remediation.

#### Implementation

- Secure coding standard.
- Code review.
- Dependency pinning.
- Input validation.
- Security library/framework được chuẩn hóa.
- IDE/plugin hỗ trợ developer phát hiện lỗi sớm.

#### Operations

- Logging và monitoring.
- Alerting.
- Incident response.
- Patch/vulnerability management.
- Runtime hardening.
- Backup/restore test.
- Configuration và access review.

### 3.5. Quy trình assessment bằng DSOMM

Một assessment thực tế nên đi theo các bước:

#### Bước 1: Xác định phạm vi

Ví dụ:

- Toàn tổ chức.
- Một business unit.
- Một platform Kubernetes.
- Nhóm ứng dụng internet-facing.
- Một sản phẩm cụ thể.

Phạm vi quá rộng sẽ tạo kết quả chung chung; phạm vi quá hẹp có thể không phản ánh hệ thống thực tế.

#### Bước 2: Thu thập bằng chứng

Không chỉ phỏng vấn miệng. Nên thu thập:

- File pipeline.
- Branch protection settings.
- Sample scan report.
- Policy exception records.
- Dashboard SLA.
- Incident ticket.
- Training records.
- Registry configuration.
- Kubernetes admission policy.
- Audit log.

#### Bước 3: Chấm hiện trạng

Với mỗi activity, xác định:

- Đã làm hay chưa?
- Áp dụng cho bao nhiêu dự án?
- Tự động hay thủ công?
- Có owner không?
- Có tiêu chí pass/fail không?
- Có đo hiệu quả không?
- Có exception process không?
- Có bằng chứng có thể kiểm toán không?

#### Bước 4: Xác định target maturity

Không phải mọi activity đều cần mức cao nhất. Mục tiêu nên dựa trên:

- Mức độ critical của tài sản.
- Dữ liệu được xử lý.
- Khả năng tiếp xúc Internet.
- Yêu cầu pháp lý.
- Threat model.
- Chi phí và năng lực vận hành.

Ví dụ:

- Payment service cần control chặt hơn internal wiki.
- Production deployment cần signature verification; môi trường demo có thể chỉ cảnh báo.

#### Bước 5: Lập roadmap

Roadmap nên có:

- Activity/control.
- Mức hiện tại.
- Mức mục tiêu.
- Owner.
- Deadline.
- Dependency.
- Evidence cần tạo.
- Metric đánh giá.

Ví dụ:

| Hoạt động | Hiện tại | Mục tiêu | Hành động |
|---|---|---|---|
| Secret scanning | Chạy thủ công | Tự động trên MR | Tích hợp Gitleaks, chặn verified secret |
| Container scanning | Chỉ scan định kỳ | Scan trước push và định kỳ lại | Trivy trong CI, Harbor scheduled scan |
| Exception | Qua chat | Có audit và expiry | Tạo risk acceptance workflow |
| Artifact integrity | Dùng mutable tag | Ký và deploy bằng digest | Cosign + admission verification |

#### Bước 6: Đo và cải tiến

Assessment không nên là hoạt động một lần. Nên đánh giá lại theo chu kỳ hoặc khi có thay đổi lớn về kiến trúc.

### 3.6. Metric hữu ích

#### Coverage metric

- Tỷ lệ repository có secret scanning.
- Tỷ lệ ứng dụng có SAST/SCA.
- Tỷ lệ image có SBOM.
- Tỷ lệ production workload dùng image digest.
- Tỷ lệ artifact có signature hợp lệ.

#### Remediation metric

- Mean Time to Remediate theo severity.
- Tỷ lệ finding quá SLA.
- Tuổi trung bình của vulnerability.
- Tỷ lệ Critical có fix nhưng chưa xử lý.

#### Quality metric

- False-positive rate.
- Tỷ lệ finding bị reopen.
- Tỷ lệ scan job bị lỗi kỹ thuật.
- Tỷ lệ pipeline bypass.
- Tỷ lệ exception hết hạn nhưng chưa đóng.

#### Outcome metric

- Số incident bắt nguồn từ dependency.
- Số secret thật bị commit.
- Số artifact không truy vết được về source.
- Số deployment bị admission policy từ chối.
- Tỷ lệ phát hiện trước production so với sau production.

Không nên chỉ dùng “số lượng vulnerability” làm thước đo trưởng thành vì số lượng có thể tăng khi coverage tốt hơn.

### 3.7. Security gate trong DSOMM

Một security gate tốt cần có:

- Điều kiện rõ ràng.
- Dữ liệu đầu vào đáng tin cậy.
- Mức severity/risk phù hợp.
- Xử lý false positive.
- Cơ chế exception.
- Owner phê duyệt.
- Thời hạn exception.
- Audit trail.
- Cách fail-safe hoặc fail-open được quyết định trước.

Ví dụ:

```text
Hard gate:
- Verified secret.
- Critical vulnerability có exploit và có fix trong image production.
- Image không có chữ ký.
- Kubernetes workload chạy privileged trái policy.

Soft gate:
- Medium vulnerability.
- OpenSSF Scorecard thấp nhưng chưa có bằng chứng khai thác.
- License cần legal review.

Manual approval:
- Production release.
- Risk acceptance có thời hạn.
```

DSOMM giúp đánh giá mức trưởng thành của quá trình này; nó không áp đặt một threshold duy nhất cho mọi tổ chức.

### 3.8. DSOMM khác OWASP SAMM thế nào?

Cả hai đều là maturity model của OWASP, nhưng trọng tâm khác nhau:

| DSOMM | SAMM |
|---|---|
| Tập trung mạnh vào DevSecOps, automation, pipeline, deployment và operations | Tập trung rộng vào chương trình software assurance trên toàn SDLC |
| Phù hợp khi đánh giá cách security được tích hợp vào DevOps | Phù hợp khi xây dựng chiến lược AppSec tổng thể |
| Có nhiều hoạt động gắn với CI/CD và vận hành | Bao quát governance, design, implementation, verification và operations theo mô hình SAMM |

Hai model có thể bổ sung cho nhau. Không nhất thiết phải chọn một và loại bỏ hoàn toàn model còn lại.

### 3.9. Sai lầm thường gặp khi dùng DSOMM

- Chấm điểm để làm đẹp báo cáo thay vì cải thiện risk.
- Tự khai “đã đạt” nhưng không có evidence.
- Ép mọi team đạt cùng một target bất kể criticality.
- Coi mua tool là hoàn thành activity.
- Tự động hóa gate nhưng không có triage owner.
- Không quản lý exception và expiry.
- Không đánh giá lại sau khi kiến trúc thay đổi.
- Theo đuổi maturity tối đa trong khi control cơ bản chưa ổn định.

---

## 4. OpenSSF

### 4.1. OpenSSF là gì?

**OpenSSF** là viết tắt của **Open Source Security Foundation**. Đây là một sáng kiến thuộc hệ sinh thái Linux Foundation, tập hợp cộng đồng và các tổ chức nhằm cải thiện bảo mật của phần mềm mã nguồn mở.

OpenSSF không phải một scanner duy nhất. Hệ sinh thái này gồm:

- Framework và baseline.
- Công cụ đánh giá dự án open source.
- Công cụ ký và xác minh phần mềm.
- Hệ thống phân tích dữ liệu supply chain.
- Best-practice guidance.
- Training.
- Working groups và community initiatives.

Trong bối cảnh phỏng vấn DevSecOps, những nội dung nên biết nhất là:

1. OpenSSF Scorecard.
2. OpenSSF Best Practices Badge.
3. OSPS Baseline.
4. Sigstore.
5. GUAC.
6. Vai trò của SLSA trong hệ sinh thái OpenSSF.

### 4.2. OpenSSF Scorecard

#### Scorecard là gì?

OpenSSF Scorecard là công cụ đánh giá tự động các thực hành bảo mật của dự án mã nguồn mở. Nó chạy nhiều check và tạo điểm cho từng check, sau đó tổng hợp thành một tín hiệu đánh giá.

Scorecard giúp consumer hoặc maintainer trả lời các câu hỏi như:

- Dự án có branch protection không?
- Dependency có được pin không?
- Có quy trình cập nhật dependency không?
- Có CI test không?
- Có dấu hiệu dangerous workflow không?
- Có security policy không?
- Release artifact có được ký không?
- Dự án có hoạt động duy trì hay không?

Điểm Scorecard thường nằm trong thang **0–10**; điểm cao hơn thể hiện dự án tuân theo nhiều thực hành bảo mật được kiểm tra hơn.

#### Scorecard không phải là gì?

Scorecard không chứng minh rằng:

- Package không chứa mã độc.
- Package không có CVE.
- Maintainer không bị compromise.
- Dependency phù hợp với mọi threat model.
- Điểm 10 đồng nghĩa “an toàn tuyệt đối”.

Nó là **risk signal**, cần kết hợp với:

- Popularity và criticality.
- Maintenance activity.
- Known vulnerabilities.
- License.
- Provenance và signature.
- Dependency depth.
- Reachability.
- Internal usage context.

#### Cách dùng Scorecard trong pipeline

Có thể sử dụng Scorecard theo các cách:

- Đánh giá repository do tổ chức sở hữu.
- Đánh giá dependency quan trọng trước khi chấp nhận.
- Đặt policy cảnh báo khi dependency có check rủi ro cao.
- Theo dõi xu hướng điểm theo thời gian.
- Tạo issue cho maintainer khi control bị suy giảm.

Không nên hard-block mọi dependency chỉ vì tổng điểm thấp. Cần xem check cụ thể và bối cảnh.

Ví dụ:

```text
Dependency A có tổng điểm 6.5
- Branch-Protection: thấp
- Maintained: cao
- Dangerous-Workflow: cao
- Pinned-Dependencies: thấp

Kết luận hợp lý:
- Cần review sâu hơn và có thể pin dependency.
- Không tự động kết luận dependency chứa mã độc.
```

### 4.3. OpenSSF Best Practices Badge

Best Practices Badge là chương trình cho phép dự án open source thể hiện rằng dự án đáp ứng một tập thực hành phát triển phần mềm tốt.

Các tiêu chí có thể liên quan đến:

- Source được public và có version control.
- Có license rõ ràng.
- Có hướng dẫn đóng góp.
- Có test.
- Có cơ chế báo cáo vulnerability.
- Có quy trình release.
- Có thực hành secure development.

Khác biệt quan trọng:

| Scorecard | Best Practices Badge |
|---|---|
| Phần lớn là đánh giá tự động qua các check | Dựa trên bộ tiêu chí/bằng chứng do dự án khai báo và xác nhận theo chương trình |
| Cung cấp điểm và kết quả chi tiết | Cung cấp badge thể hiện đạt tiêu chí tương ứng |
| Hữu ích cho continuous signal | Hữu ích cho thể hiện cam kết và mức đáp ứng best practices |

Cả hai đều là tín hiệu; không nên coi badge là bảo đảm tuyệt đối.

### 4.4. OSPS Baseline

**Open Source Project Security Baseline (OSPS Baseline)** là một tập security control mà dự án open source nên đáp ứng để thể hiện security posture mạnh hơn.

Baseline tổ chức control theo:

- Mức trưởng thành.
- Nhóm control.
- Rationale và hướng dẫn.
- Mapping tham khảo tới các framework/standard khác khi phù hợp.

OSPS Baseline có ích khi:

- Maintainer muốn biết mức control tối thiểu nên có.
- Doanh nghiệp muốn tạo tiêu chí đánh giá OSS trước khi sử dụng.
- Tổ chức muốn chuẩn hóa yêu cầu cho dự án open source nội bộ.
- Cần mapping giữa policy nội bộ và best practices bên ngoài.

Ví dụ control mong đợi có thể liên quan đến:

- Access control.
- Change control.
- Build và release.
- Vulnerability reporting.
- Documentation.
- Dependency management.
- Security testing.

### 4.5. Sigstore

Sigstore là một hệ sinh thái/chuẩn và tập công cụ hỗ trợ **ký, xác minh và bảo vệ phần mềm**.

Trong quy trình container, công cụ thường được nhắc đến là **Cosign**.

Mục tiêu chính:

- Ký container image hoặc artifact.
- Tạo/xác minh attestation.
- Gắn identity của signer hoặc workflow với artifact.
- Cho phép policy engine kiểm tra trước khi deployment.

Ví dụ:

```text
GitLab CI build image
  -> image digest
  -> Cosign ký image bằng workload identity/key
  -> push signature/attestation lên OCI registry
  -> admission controller xác minh trước khi chạy
```

Sigstore bổ sung cho SLSA:

- SLSA mô tả yêu cầu về provenance và build integrity.
- Sigstore cung cấp cơ chế thực tế để ký và xác minh artifact/attestation.

Dùng Sigstore không tự động đồng nghĩa đạt một mức SLSA cụ thể; cần xem toàn bộ yêu cầu của track và level.

### 4.6. GUAC

**GUAC** là viết tắt của **Graph for Understanding Artifact Composition**. Nó tập hợp và liên kết dữ liệu supply chain thành một graph để hỗ trợ truy vấn và tạo insight.

Nguồn dữ liệu có thể gồm:

- SBOM.
- SLSA provenance.
- Vulnerability data.
- OpenSSF Scorecard result.
- Package metadata.
- Attestation và dữ liệu liên quan.

Ví dụ câu hỏi GUAC hướng tới:

- Những application nào bị ảnh hưởng bởi package X?
- Artifact nào được build từ repository Y?
- Image nào chứa dependency có CVE mới?
- Dependency nào có Scorecard risk cao?
- Provenance nào bị thiếu hoặc không xác minh được?

GUAC không thay thế registry, scanner hay SBOM generator; nó giúp tổng hợp và khai thác quan hệ giữa các dữ liệu này.

### 4.7. SLSA và OpenSSF liên quan thế nào?

SLSA là một dự án/framework nổi bật trong hệ sinh thái OpenSSF.

Có thể mô tả quan hệ như sau:

```text
OpenSSF
  ├── SLSA: yêu cầu và mức bảo đảm supply-chain integrity
  ├── Scorecard: đánh giá tự động thực hành bảo mật OSS
  ├── Best Practices Badge: chương trình tiêu chí/badge
  ├── OSPS Baseline: baseline control cho dự án OSS
  ├── Sigstore: ký và xác minh artifact/attestation
  └── GUAC: tổng hợp dữ liệu supply chain thành graph
```

Vì vậy, “OpenSSF” không ngang hàng hoàn toàn với “SLSA” theo nghĩa loại hình: OpenSSF là foundation/hệ sinh thái, còn SLSA là một framework/specification trong hệ sinh thái đó.

### 4.8. Cách doanh nghiệp dùng OpenSSF

#### Khi lựa chọn dependency

- Chạy Scorecard.
- Kiểm tra maintenance và release cadence.
- Kiểm tra vulnerability history.
- Kiểm tra license.
- Kiểm tra security policy và disclosure process.
- Xác minh signature/provenance nếu có.
- Đánh giá mức critical của dependency.

#### Khi quản trị repository nội bộ

- Áp dụng branch protection.
- Bật dependency update automation.
- Pin GitHub Actions/GitLab component theo commit hoặc digest khi phù hợp.
- Hạn chế token permission.
- Ký release.
- Công bố security policy.
- Tạo SBOM và provenance.

#### Khi thiết kế policy

Ví dụ policy risk-based:

```text
Critical dependency:
- Không có known Critical CVE chưa được chấp nhận.
- Maintained.
- Có security policy.
- Không có dangerous workflow nghiêm trọng.
- Có release integrity signal phù hợp.
- Có owner nội bộ và phương án thay thế.

Low-risk development dependency:
- Có thể cho phép với soft warning và monitoring.
```

---

## 5. So sánh ba khái niệm

### 5.1. Bảng so sánh chi tiết

| Tiêu chí | SLSA | OWASP DSOMM | OpenSSF |
|---|---|---|---|
| Loại | Framework/specification | Maturity model | Foundation và hệ sinh thái dự án |
| Phạm vi chính | Software supply-chain integrity | DevSecOps maturity | Bảo mật open source và supply chain |
| Đơn vị đánh giá | Source/build/artifact theo track và level | Hoạt động, quy trình và năng lực tổ chức | Project, dependency, artifact hoặc ecosystem tùy dự án |
| Đầu ra | Provenance, attestation, mức bảo đảm | Assessment, target, roadmap, evidence, metric | Score, badge, baseline, signature, graph data, guidance |
| Có phải scanner? | Không | Không | Không; nhưng có các tool đánh giá như Scorecard |
| Câu hỏi điển hình | Artifact này được tạo thế nào và có đáng tin không? | DevSecOps của tổ chức đang ở mức nào? | Dự án OSS này tuân thủ best practices nào và có thể xác minh gì? |
| Công cụ liên quan | in-toto attestation, builder, verifier, Sigstore/Cosign | DSOMM application, dashboard, evidence repository | Scorecard, Sigstore, GUAC, Best Practices Badge |
| Điểm yếu nếu dùng riêng | Không tìm hết CVE hoặc lỗi code | Có thể thành checklist hình thức | Tín hiệu không thay thế threat/risk assessment nội bộ |

### 5.2. Cách chúng bổ sung cho nhau

Một chương trình DevSecOps có thể dùng cả ba:

1. **DSOMM** xác định tổ chức đang thiếu artifact signing, provenance, dependency governance và security gate.
2. **SLSA** cung cấp yêu cầu cụ thể để tăng tính toàn vẹn của source và build.
3. **OpenSSF Scorecard/OSPS Baseline** hỗ trợ đánh giá dependency hoặc cải thiện repository.
4. **Sigstore** được dùng để ký image và provenance.
5. Kết quả được đo lại trong kỳ assessment DSOMM tiếp theo.

Ví dụ roadmap:

```text
DSOMM assessment
  -> phát hiện build chưa truy vết và dependency chưa có governance
  -> áp dụng SLSA Build L1 rồi L2
  -> dùng Scorecard làm risk signal cho OSS dependency
  -> dùng Sigstore ký image/provenance
  -> đo coverage, exception và verification rate
  -> nâng maturity trong lần đánh giá tiếp theo
```

---

## 6. Cách áp dụng vào một hệ thống DevSecOps

### 6.1. Kiến trúc tham chiếu

```text
Developer
   |
   v
GitLab Repository
   |- protected branch
   |- merge request review
   |- CODEOWNERS
   |
   v
GitLab CI / Hosted Runner
   |- unit test
   |- secret scan
   |- SAST
   |- SCA
   |- IaC scan
   |- build image
   |- generate SBOM
   |- generate provenance
   |- image scan
   |- sign image/attestation
   |
   v
Harbor Registry
   |- immutable artifact
   |- vulnerability scan
   |- signature/attestation storage
   |
   +--> Dependency-Track: SBOM/component risk
   +--> DefectDojo: aggregate/triage findings
   |
   v
GitOps Repository
   |- image referenced by digest
   |
   v
Argo CD
   |
   v
Kubernetes Admission Policy
   |- allowed registry
   |- signature verification
   |- provenance policy
   |- no privileged workload
   |
   v
Production
```

### 6.2. Mapping control

| Thành phần | SLSA | DSOMM | OpenSSF |
|---|---|---|---|
| Protected branch/MR review | Source Track | Change control maturity | Scorecard/OSPS control signal |
| Hosted GitLab Runner | Build Track | Secure build activity | SLSA project guidance |
| Provenance | Build L1+ | Artifact traceability | SLSA/Sigstore ecosystem |
| Artifact signing | Hỗ trợ integrity và verification | Secure release/deployment activity | Sigstore/Cosign |
| SBOM | Bổ sung supply-chain metadata | Dependency inventory maturity | GUAC/OSPS ecosystem |
| Dependency evaluation | Không phải trọng tâm duy nhất của Build Track | SCA và governance activity | Scorecard/OSPS Baseline |
| Admission verification | Consumer-side enforcement | Automated deployment control | Sigstore policy verification |
| Metrics và roadmap | Không phải maturity model | Trọng tâm chính | Dữ liệu từ Scorecard/baseline có thể làm evidence |

### 6.3. Lộ trình triển khai theo giai đoạn

#### Giai đoạn 1: Visibility

- Inventory repository và application owner.
- Tạo SBOM.
- Tạo provenance cơ bản.
- Scan source, dependency và image.
- Lưu report tập trung.

Kết quả mong đợi:

- Biết đang có gì.
- Biết artifact đến từ commit nào.
- Biết dependency nào tồn tại.

#### Giai đoạn 2: Standardization

- Pipeline template dùng chung.
- Protected branch.
- Review và CODEOWNERS.
- Registry private và immutable.
- Chuẩn hóa severity policy.
- Chuẩn hóa exception workflow.

#### Giai đoạn 3: Verification và enforcement

- Ký image và attestation.
- Xác minh identity của builder.
- Deploy bằng digest.
- Admission controller kiểm tra signature và policy.
- Chặn artifact không có provenance hoặc đến từ builder không được phép.

#### Giai đoạn 4: Optimization

- Risk-based gate.
- Theo dõi dependency liên tục.
- Scorecard/OSPS signal cho OSS intake.
- Tự động hết hạn exception.
- Đo false positive và developer friction.
- Periodic DSOMM reassessment.

### 6.4. Các gate mẫu

| Gate | Chặn khi | Liên hệ framework |
|---|---|---|
| Source gate | Protected branch bị bypass, thiếu review bắt buộc | SLSA Source, DSOMM change control |
| Secret gate | Verified credential xuất hiện | DSOMM secure implementation |
| Dependency gate | Critical exploitable dependency vượt policy | DSOMM SCA, OpenSSF risk evaluation |
| Build gate | Không tạo được provenance | SLSA Build L1+ |
| Signing gate | Signature không tồn tại hoặc signer không hợp lệ | SLSA integrity, Sigstore |
| Registry gate | Image mutable hoặc scan chưa hoàn tất | DSOMM artifact management |
| Deployment gate | Image không đúng registry/digest hoặc provenance sai | SLSA consumer verification, DSOMM operations |

### 6.5. Nguyên tắc thiết kế gate

- Gate theo risk, không chỉ theo con số CVSS.
- Phân biệt finding mới và technical debt cũ.
- Ưu tiên verified secret và exploitable vulnerability.
- Có timeout và fallback được thiết kế trước.
- Scanner lỗi kỹ thuật không được giả thành “không có lỗ hổng”.
- Exception phải có người chịu trách nhiệm và ngày hết hạn.
- Production nghiêm hơn development.
- Mọi bypass phải được audit.

---

## 7. Câu hỏi phỏng vấn và câu trả lời gợi ý

### 7.1. SLSA là gì?

SLSA là framework/specification giúp tăng dần mức bảo đảm cho software supply chain. Nó tập trung vào tính toàn vẹn của source, quá trình build, artifact và provenance. Mục tiêu là chứng minh artifact được tạo từ đúng source bởi builder đáng tin cậy và không bị thay thế hoặc can thiệp trái phép.

### 7.2. Provenance khác SBOM thế nào?

Provenance mô tả artifact được tạo ở đâu, khi nào, từ source/input nào và bởi builder nào. SBOM mô tả bên trong phần mềm có những component/dependency nào. Provenance phục vụ traceability và build integrity; SBOM phục vụ component inventory, vulnerability và license analysis.

### 7.3. Ký image có đủ để bảo đảm an toàn không?

Không. Chữ ký chứng minh image được ký bởi một identity/key nhất định và nội dung không đổi sau khi ký. Nó không chứng minh source an toàn, builder không bị compromise hoặc image không có CVE. Cần xác minh provenance, builder identity, scan result và policy deployment.

### 7.4. SLSA L3 có nghĩa là không có vulnerability không?

Không. Build L3 tăng bảo đảm rằng quá trình build được làm cứng và khó bị can thiệp. Nó không kiểm tra toàn bộ lỗi code hoặc dependency vulnerability.

### 7.5. OWASP DSOMM dùng để làm gì?

DSOMM dùng để đánh giá mức trưởng thành DevSecOps, xác định khoảng trống, ưu tiên activity và xây roadmap cải tiến. Giá trị chính là biến security từ các hoạt động rời rạc thành quy trình có ownership, automation, evidence và metric.

### 7.6. Maturity cao có phải dùng nhiều tool hơn không?

Không nhất thiết. Maturity cao là control phù hợp rủi ro, áp dụng nhất quán, có bằng chứng, được đo lường và cải tiến. Một tổ chức có nhiều scanner nhưng không triage hoặc không quản lý exception vẫn có maturity thấp.

### 7.7. OpenSSF là một tool phải không?

Không. OpenSSF là foundation và hệ sinh thái nhiều dự án bảo mật open source. Scorecard, Sigstore, GUAC, Best Practices Badge, OSPS Baseline và SLSA là các sáng kiến/dự án tiêu biểu trong hệ sinh thái này.

### 7.8. OpenSSF Scorecard có thể dùng làm hard gate không?

Có thể dùng trong policy, nhưng không nên block chỉ dựa vào tổng điểm. Cần xem từng check, độ critical của dependency, maintenance, vulnerability, provenance và bối cảnh sử dụng. Scorecard là risk signal chứ không phải bằng chứng rằng package có hoặc không có mã độc.

### 7.9. SLSA và Sigstore khác nhau thế nào?

SLSA mô tả các yêu cầu và mức bảo đảm cho supply-chain integrity. Sigstore cung cấp cơ chế và công cụ để ký, lưu và xác minh artifact hoặc attestation. Sigstore có thể giúp hiện thực hóa một phần yêu cầu SLSA, nhưng dùng Sigstore không tự động đạt SLSA level.

### 7.10. SLSA, DSOMM và OpenSSF kết hợp ra sao?

DSOMM giúp xác định maturity và roadmap. SLSA cung cấp yêu cầu kỹ thuật cho source/build integrity. OpenSSF cung cấp thêm công cụ và baseline như Scorecard, Sigstore, OSPS Baseline và GUAC. Kết hợp cả ba giúp tổ chức vừa có chiến lược cải tiến, vừa có technical control và dữ liệu thực thi.

### 7.11. Làm sao chứng minh image trên production là image đã scan?

- Build image một lần trong CI.
- Lấy immutable digest.
- Scan đúng digest đó.
- Tạo provenance gắn digest với source commit.
- Ký image và attestation.
- Push vào registry có kiểm soát.
- GitOps manifest tham chiếu digest.
- Admission policy xác minh signature/provenance trước khi chạy.
- Không rebuild artifact giữa staging và production.

### 7.12. Security gate nên fail-open hay fail-closed khi scanner lỗi?

Phụ thuộc rủi ro và môi trường. Với production hoặc control bảo vệ artifact integrity, thường ưu tiên fail-closed. Với một hệ thống reporting phụ trợ, có thể fail-open tạm thời nhưng phải tạo alert và retry. Quyết định cần được thiết kế trước, audit và không được nhầm “scanner lỗi” với “scan sạch”.

---

## 8. Checklist học và thực hành

### 8.1. SLSA

- [ ] Giải thích được software supply chain.
- [ ] Phân biệt artifact, provenance, attestation và SBOM.
- [ ] Nêu được Build L0–L3.
- [ ] Hiểu Source Track và two-party review.
- [ ] Giải thích được hosted/hardened builder.
- [ ] Biết vì sao deploy bằng digest tốt hơn mutable tag.
- [ ] Biết ký artifact không thay thế vulnerability scanning.
- [ ] Vẽ được luồng generate và verify provenance.

### 8.2. OWASP DSOMM

- [ ] Giải thích được mục tiêu của maturity model.
- [ ] Biết assessment phải dựa trên evidence.
- [ ] Phân biệt current maturity và target maturity.
- [ ] Biết lập roadmap theo risk và criticality.
- [ ] Nêu được metric coverage, remediation, quality và outcome.
- [ ] Thiết kế được exception có owner và expiry.
- [ ] Phân biệt DSOMM với OWASP SAMM.
- [ ] Biết maturity không đồng nghĩa số lượng tool.

### 8.3. OpenSSF

- [ ] Giải thích OpenSSF là foundation/hệ sinh thái, không phải một tool.
- [ ] Nêu được vai trò của Scorecard.
- [ ] Biết hạn chế của tổng điểm Scorecard.
- [ ] Phân biệt Scorecard và Best Practices Badge.
- [ ] Nêu được mục đích của OSPS Baseline.
- [ ] Giải thích được Sigstore/Cosign.
- [ ] Nêu được GUAC giải quyết bài toán gì.
- [ ] Giải thích quan hệ giữa SLSA và OpenSSF.

### 8.4. Bài lab tối thiểu

- [ ] Repository có protected branch và MR review.
- [ ] CI build container image.
- [ ] Tạo CycloneDX hoặc SPDX SBOM.
- [ ] Tạo provenance hoặc attestation gắn source commit với image digest.
- [ ] Scan dependency và image.
- [ ] Ký image bằng Cosign.
- [ ] Push image lên registry private.
- [ ] Deploy bằng digest.
- [ ] Xác minh signature trước deployment.
- [ ] Ghi lại evidence để map vào DSOMM assessment.
- [ ] Chạy Scorecard trên một repository và phân tích từng check thay vì chỉ nhìn tổng điểm.

---

## 9. Tài liệu tham khảo chính thức

### SLSA

- Trang chủ SLSA: <https://slsa.dev/>
- SLSA specification v1.2: <https://slsa.dev/spec/v1.2/>
- SLSA tracks: <https://slsa.dev/spec/v1.2/tracks>
- Build Track basics: <https://slsa.dev/spec/v1.2/build-track-basics>
- Build requirements: <https://slsa.dev/spec/v1.2/build-requirements>
- Build provenance: <https://slsa.dev/spec/v1.2/build-provenance>
- Source requirements: <https://slsa.dev/spec/v1.2/source-requirements>

### OWASP DSOMM

- OWASP project page: <https://owasp.org/www-project-devsecops-maturity-model/>
- DSOMM application/documentation: <https://dsomm.owasp.org/>
- Hướng dẫn sử dụng: <https://dsomm.owasp.org/usage>
- Model/application settings và version: <https://dsomm.owasp.org/settings>
- OWASP DevSecOps project: <https://devsecops.owasp.org/>

### OpenSSF

- OpenSSF: <https://openssf.org/>
- OpenSSF Scorecard: <https://openssf.org/projects/scorecard/>
- Best Practices Badge: <https://openssf.org/projects/best-practices-badge/>
- OpenSSF Best Practices resources: <https://best.openssf.org/>
- OSPS Baseline: <https://baseline.openssf.org/>
- Sigstore: <https://www.sigstore.dev/>
- GUAC: <https://guac.sh/>
- OpenSSF training: <https://openssf.org/training/>

---

## Tóm tắt cuối

- **SLSA** giúp bảo đảm và xác minh nguồn gốc cùng tính toàn vẹn của source, build và artifact thông qua tracks, levels, provenance và attestation.
- **OWASP DSOMM** giúp đánh giá DevSecOps hiện tại, chọn mức mục tiêu và xây roadmap cải tiến dựa trên evidence, risk và metric.
- **OpenSSF** là hệ sinh thái bảo mật open source, cung cấp các dự án và phương pháp như Scorecard, Best Practices Badge, OSPS Baseline, Sigstore, GUAC và SLSA.

Một câu trả lời phỏng vấn tốt không chỉ định nghĩa ba khái niệm, mà còn chỉ ra cách chúng kết hợp:

> DSOMM cho biết tổ chức cần cải thiện điều gì; SLSA mô tả mức bảo đảm cần đạt cho source và build; OpenSSF cung cấp thêm baseline, tín hiệu và công cụ để đánh giá dependency, ký artifact và phân tích dữ liệu supply chain.