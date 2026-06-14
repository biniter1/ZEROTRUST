# Mô tả Đồ án Tốt nghiệp
# Triển khai Kiến trúc Zero Trust trong DevSecOps trên Kubernetes và AWS

---

## 1. Tổng quan

Đồ án nghiên cứu và triển khai mô hình **Zero Trust Architecture (ZTA)** toàn diện cho hệ thống DevSecOps vận hành trên **AWS Elastic Kubernetes Service (EKS)**. Thay vì bảo mật theo vành đai (perimeter security) — mô hình cũ giả định mọi thứ bên trong mạng nội bộ đều đáng tin — Zero Trust áp dụng nguyên tắc **"never trust, always verify"**: mọi thực thể (người dùng, dịch vụ, máy chủ) đều phải xác thực và được phép tường minh trước khi truy cập bất kỳ tài nguyên nào.

**Ứng dụng demo:** [Google Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo) — hệ thống thương mại điện tử gồm 10 microservices giao tiếp qua gRPC, triển khai tại AWS region `ap-southeast-1` (Singapore).

**Vấn đề đặt ra:** Hầu hết pipeline DevOps hiện tại sử dụng static credentials (Access Key/Secret Key), không có ký số image, không có kiểm tra SBOM, không mã hóa traffic nội bộ giữa các microservices, và không có runtime detection. Một lỗ hổng nhỏ ở bất kỳ layer nào (developer machine, CI/CD runner, hay một pod trong cluster) có thể dẫn tới lateral movement và compromise toàn bộ hệ thống.

---

## 2. Kiến trúc 3 Lớp

Hệ thống được thiết kế theo 3 lớp bảo mật độc lập, bổ trợ cho nhau. Mỗi lớp đảm bảo rằng ngay cả khi lớp trên bị vượt qua, lớp dưới vẫn ngăn chặn được tấn công.

```
┌─────────────────────────────────────────────────────────────────┐
│         LAYER 1 — Identity & Access Control                     │
│  AWS Organizations · IAM Identity Center · GitHub OIDC          │
│  EKS Pod Identity · Istio SPIFFE/mTLS                           │
├─────────────────────────────────────────────────────────────────┤
│         LAYER 2 — Secure CI/CD Supply Chain                     │
│  GitHub Actions · Gitleaks · Semgrep · Trivy · Checkov          │
│  Cosign/KMS · Syft SBOM · SLSA Provenance · Deploy-by-digest   │
├─────────────────────────────────────────────────────────────────┤
│         LAYER 3 — Kubernetes Runtime Security                   │
│  PSS Restricted · NetworkPolicy · Kyverno · Istio Ambient       │
│  External Secrets Operator · Falco eBPF                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Layer 1 — Identity & Access Control

### 3.1. AWS Organizations và Service Control Policies (SCP)

Toàn bộ hạ tầng AWS được tổ chức trong **AWS Organizations** với cấu trúc phân cấp:

```
Root
├── Security OU
│   ├── Logging Account
│   └── Audit Account
├── Infrastructure OU
│   └── Shared Services Account
└── Workloads OU
    ├── Development Account
    ├── Staging Account
    └── Production Account
```

**4 Service Control Policies (SCP)** được áp dụng ở cấp OU để đảm bảo ngay cả tài khoản root của từng AWS Account cũng không thể vi phạm:

- **SCP-1:** Chặn mọi hành động từ region ngoài `ap-southeast-1` (data residency)
- **SCP-2:** Bắt buộc bật MFA cho mọi IAM action nhạy cảm
- **SCP-3:** Cấm tạo IAM User với long-lived Access Key (phải dùng SSO)
- **SCP-4:** Cấm vô hiệu hóa CloudTrail và AWS Config

### 3.2. IAM Identity Center (SSO + MFA)

Thay vì cấp IAM User riêng lẻ, toàn bộ developer và DevOps sử dụng **IAM Identity Center** với:
- **Single Sign-On (SSO):** Đăng nhập một lần cho cả AWS Console, CLI, và kubectl
- **Bắt buộc MFA (TOTP/FIDO2)** cho mọi session
- **Permission Sets** phân theo vai trò:
  - `Developer`: Read-only, không xem secrets
  - `DevOps`: Full staging, read-only production
  - `Admin`: Break-glass only, audit logged, TTL 1 giờ

Session credentials tự hết hạn và không thể dùng lại — loại bỏ hoàn toàn long-lived credentials.

### 3.3. GitHub OIDC Federation (Keyless Authentication)

**Vấn đề cũ:** CI/CD pipeline lưu `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` trong GitHub Secrets — nếu secret bị lộ, attacker có AWS access vô thời hạn.

**Giải pháp:** GitHub Actions sử dụng **OIDC (OpenID Connect) federation** để lấy STS token tạm thời:

```
GitHub Actions Runner
    │  (1) Request OIDC token từ GitHub
    ▼
GitHub OIDC Provider
    │  (2) JWT token (claims: repo, ref, workflow)
    ▼
AWS STS AssumeRoleWithWebIdentity
    │  (3) Verify JWT signature + claims (repo=org/repo, ref=refs/heads/main)
    ▼
Temporary Credentials (TTL: 15 phút)
    │  (4) AWS access trong 15 phút, không thể gia hạn
    ▼
GitHub Actions (ECR push, EKS deploy)
```

**Ràng buộc an toàn:**
- Chỉ workflow chạy trên branch `main` mới được assume role ECR push
- TTL 15 phút (900 giây) — credential hết hạn trước khi attacker kịp phát hiện
- Không có static credential nào tồn tại trong repository hoặc GitHub Secrets

Hai IAM role được tạo riêng biệt:
- **`gha-ecr-push-role`:** Chỉ push image lên ECR, ký Cosign, đọc KMS
- **`gha-eks-deploy-role`:** Chỉ describe cluster, cập nhật deployment — không thể xóa hay leo thang

### 3.4. EKS Pod Identity (10 Per-Service IAM Roles)

**Vấn đề cũ:** Mọi pod trong cluster dùng chung Node IAM Role — cartservice, paymentservice, và adservice đều có quyền như nhau, vi phạm least-privilege.

**Giải pháp:** **EKS Pod Identity** gán IAM role riêng cho từng ServiceAccount theo nguyên tắc least-privilege tuyệt đối:

| Service | Quyền IAM | Lý do |
|---|---|---|
| frontend | ECR: GetAuthorizationToken, GetImage | Pull image |
| cartservice | ElastiCache: DescribeReplicationGroups | Kết nối Redis |
| checkoutservice | Secrets Manager: GetSecretValue (prod/checkout/*) | API keys |
| paymentservice | Secrets Manager: GetSecretValue (prod/payment/*) | Payment credentials |
| emailservice | SES: SendEmail, SendRawEmail | Gửi email xác nhận |
| adservice | CloudWatch: PutMetricData, GetMetricData | Metrics |
| productcatalogservice | ECR: GetAuthorizationToken | Pull catalog data |
| shippingservice | ECR: GetAuthorizationToken | Pull shipping rates |
| recommendationservice | ECR: GetAuthorizationToken | Pull ML model |
| currencyservice | ECR: GetAuthorizationToken | Pull currency data |

Nếu attacker compromise pod paymentservice và escape container, họ **chỉ** có quyền đọc secret `prod/payment/*` — không thể truy cập Redis, không gửi email, không đọc secrets của service khác.

### 3.5. Istio SPIFFE/mTLS

Mọi microservice được cấp **SPIFFE identity** (X.509 certificate) theo format:

```
spiffe://cluster.local/ns/production/sa/paymentservice
```

Istio Ambient Mode tự động rotate certificate và enforce **mTLS STRICT** — mọi kết nối không có certificate hợp lệ đều bị từ chối ở layer 4, ngay cả khi attacker nằm trong cùng namespace.

---

## 4. Layer 2 — Secure CI/CD Supply Chain

### 4.1. Tổng quan 3 Workflow

```
┌──────────────┐    PR      ┌──────────────┐   push main   ┌──────────────┐
│   ci.yml     │ ─────────► │  build.yml   │ ─────────────► │  deploy.yml  │
│  (PR gates)  │            │ (build+sign) │  workflow_run  │  (staging→   │
│  4 security  │            │  7 security  │                │  production) │
│  gates       │            │  gates       │                │              │
└──────────────┘            └──────────────┘                └──────────────┘
```

### 4.2. ci.yml — 7 Security Gates trên Pull Request

Mọi Pull Request phải vượt qua toàn bộ các gate trước khi được merge:

#### Gate 1: Gitleaks — Secret Scanning
```yaml
uses: gitleaks/gitleaks-action@v2
```
Quét toàn bộ git history tìm credentials bị commit nhầm: AWS keys, private keys, API tokens, passwords. Kết quả upload SARIF lên GitHub Security Dashboard.

#### Gate 2: Semgrep — Static Application Security Testing (SAST)
```yaml
container: semgrep/semgrep:latest
configs: [p/security-audit, p/secrets, p/owasp-top-ten]
```
Phân tích source code tìm SQL injection, XSS, path traversal, hardcoded credentials, insecure deserialization — áp dụng ruleset OWASP Top 10.

#### Gate 3: Trivy FS — Software Composition Analysis (SCA)
```yaml
uses: aquasecurity/trivy-action@v0.36.0
scan-type: fs
severity: CRITICAL,HIGH
```
Kiểm tra tất cả `go.mod`, `package.json`, `requirements.txt`, `pom.xml` — phát hiện dependency với CVE đã biết.

#### Gate 4: Checkov — Infrastructure-as-Code Security
```yaml
uses: bridgecrewio/checkov-action@v12
framework: terraform
```
Chỉ chạy khi Terraform files thay đổi. Kiểm tra 500+ quy tắc: encryption at rest, public S3 bucket, security group quá rộng, IMDSv2 disabled.

#### Gate 5–9: Language-specific CI (Matrix Strategy)
Mỗi ngôn ngữ (Go, Python, Node.js, Java, .NET) có job riêng với build + unit test + lint. Sử dụng `dorny/paths-filter` để chỉ chạy CI cho service nào có thay đổi, giảm thời gian pipeline.

#### Gate 10: ci-gate (Required Status Check)
Job tổng hợp cuối cùng — nếu bất kỳ gate nào fail, `ci-gate` fail và PR không thể merge. GitHub Branch Protection Rules enforce điều này.

### 4.3. build.yml — Build, Scan, Sign, Attest

Trigger khi merge vào `main`. Chạy matrix job song song cho từng service có thay đổi.

#### Bước 1: Docker Build
```bash
docker build \
  --build-arg VERSION=${{ github.sha }} \
  --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --build-arg GIT_REPO=${{ github.repository }} \
  -t $ECR_REPO/$SERVICE:sha-$SHORT_SHA .
```
Image được tag bằng git SHA, không phải `latest` hay semantic version — đảm bảo traceability.

#### Bước 2: Trivy Image Scan (CRITICAL block)
```yaml
severity: CRITICAL
exit-code: 1  # Dừng pipeline nếu tìm thấy CRITICAL CVE
```
Scan container image (không phải filesystem) — kiểm tra OS packages, language runtime, application libraries.

#### Bước 3: Cosign Sign với AWS KMS
```bash
cosign sign \
  --key awskms:///$KMS_KEY_ARN \
  --annotations "github-sha=${{ github.sha }}" \
  --annotations "github-repo=${{ github.repository }}" \
  --annotations "service=$SERVICE" \
  $ECR_REPO/$SERVICE@$DIGEST
```
Chữ ký được lưu trong OCI registry (ECR) cùng với image, không cần registry riêng. KMS key không bao giờ rời khỏi AWS — private key của Cosign nằm hoàn toàn trong KMS HSM.

#### Bước 4: Syft SBOM Generation + Attestation
```bash
syft $ECR_REPO/$SERVICE@$DIGEST -o cyclonedx-json > sbom.json
cosign attest \
  --predicate sbom.json \
  --type cyclonedx \
  --key awskms:///$KMS_KEY_ARN \
  $ECR_REPO/$SERVICE@$DIGEST
```
**Software Bill of Materials (SBOM):** Danh sách đầy đủ mọi package trong image (OS + application), được ký và attach vào image digest. Khi CVE mới được phát hiện, có thể query SBOM để tìm ngay service nào bị ảnh hưởng.

#### Bước 5: SLSA Provenance Attestation
```yaml
uses: actions/attest-build-provenance@v1
```
Tạo provenance record chứa: build system identity, builder GitHub Actions workflow, input materials (source commit, base image), build parameters. Bất kỳ ai cũng có thể verify: "image này được build từ commit X, bởi workflow Y, lúc Z."

### 4.4. deploy.yml — Deploy theo Digest

**Nguyên tắc:** Deploy bằng image digest (`@sha256:abc...`), không bao giờ dùng tag:

```bash
# Lookup digest từ ECR
DIGEST=$(aws ecr describe-images \
  --repository-name $SERVICE \
  --image-ids imageTag=sha-$SHORT_SHA \
  --query 'imageDetails[0].imageDigest' --output text)

# Helm deploy với digest
helm upgrade $SERVICE ./helm-chart \
  --set image.repository=$ECR_REPO/$SERVICE \
  --set image.digest=$DIGEST
```

**Tại sao quan trọng:** Tag `sha-abc1234` có thể bị overwrite (push image mới lên cùng tag). Digest `@sha256:...` là content-addressable — không thể bị thay đổi sau khi đã sign.

**Trước khi deploy staging:** Verify lại toàn bộ:
```bash
# Verify signature
cosign verify --key awskms:///$KMS_KEY_ARN $ECR_REPO/$SERVICE@$DIGEST

# Verify SBOM attestation
cosign verify-attestation --type cyclonedx --key awskms:///$KMS_KEY_ARN $ECR_REPO/$SERVICE@$DIGEST

# Verify SLSA provenance
gh attestation verify oci://$ECR_REPO/$SERVICE@$DIGEST --repo $GITHUB_REPO
```

**Production Gate:** Yêu cầu manual approval + final cosign verification. Sau khi deploy, emit CloudWatch metric `ProductionDeployment=1` cho audit trail. Nếu rollout thất bại, tự động rollback và tạo GitHub Issue.

---

## 5. Layer 3 — Kubernetes Runtime Security

### 5.1. Pod Security Standards (PSS) Restricted

Namespace `production` và `staging` được label `enforce: restricted` — Kubernetes API server tự động từ chối bất kỳ Pod nào vi phạm:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
    istio.io/dataplane-mode: ambient
```

**PSS Restricted yêu cầu:**
- `runAsNonRoot: true` — không chạy container với root
- `allowPrivilegeEscalation: false` — container không thể leo thang quyền
- `capabilities.drop: [ALL]` — drop tất cả Linux capabilities
- `seccompProfile.type: RuntimeDefault` — giới hạn syscall cho phép
- Không cho phép `hostNetwork`, `hostPID`, `hostIPC`

### 5.2. NetworkPolicy — Default-Deny + Explicit Allow

```yaml
# Mọi traffic bị chặn theo mặc định
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}  # Áp dụng cho tất cả pods
  policyTypes: [Ingress, Egress]
  # Không có rules = deny all
```

**10 NetworkPolicy tường minh** cho phép đúng traffic cần thiết. Ví dụ `paymentservice` — service nhạy cảm nhất:

```yaml
# paymentservice CHỈ nhận traffic từ checkoutservice
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: paymentservice-policy
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: paymentservice
  policyTypes: [Ingress, Egress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: checkoutservice  # CHỈ checkoutservice, không phải frontend
    ports:
    - port: 50051
  egress:
  - ports:
    - port: 53    # DNS only
      protocol: UDP
```

Frontend không thể gọi trực tiếp tới paymentservice — phải qua checkoutservice, đảm bảo business logic validation được thực thi.

### 5.3. Kyverno — 5 ClusterPolicy Enforce Mode

Kyverno là **Policy Engine** chạy như Admission Webhook — intercept mọi request tạo/sửa Pod trước khi được Kubernetes chấp nhận.

#### Policy 1: verify-image-signature
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signature
spec:
  validationFailureAction: Enforce
  rules:
  - name: verify-cosign-signature
    match:
      resources:
        kinds: [Pod]
        namespaces: [production]
    verifyImages:
    - imageReferences: ["<ECR_ACCOUNT>.dkr.ecr.ap-southeast-1.amazonaws.com/*"]
      attestors:
      - entries:
        - keys:
            kms: awskms:///<KMS_KEY_ARN>
```
Bất kỳ image nào không có chữ ký hợp lệ từ AWS KMS đều bị từ chối deploy lên production. Ngăn chặn: supply chain attacks, unauthorized image pushes.

#### Policy 2: block-mutable-tags
```yaml
# Từ chối image dùng :latest, :main, :dev
deny:
  conditions:
    all:
    - key: "{{ element.image }}"
      operator: NotContains
      value: "@sha256:"
```
Force sử dụng immutable digest — tag có thể bị overwrite, digest thì không.

#### Policy 3: require-resource-limits
```yaml
# Mọi container phải khai báo resource requests/limits
deny:
  conditions:
    any:
    - key: "{{ element.resources.limits.memory | length(@) }}"
      operator: Equals
      value: 0
    - key: "{{ element.resources.requests.cpu | length(@) }}"
      operator: Equals
      value: 0
```
Ngăn "noisy neighbor" — một pod bị khai thác không thể monopolize CPU/RAM và làm sập toàn bộ cluster.

#### Policy 4: deny-privileged-containers
```yaml
# Từ chối privileged mode, hostNetwork, hostPID, hostIPC
deny:
  conditions:
    any:
    - key: "{{ element.securityContext.privileged }}"
      operator: Equals
      value: true
    - key: "{{ request.object.spec.hostNetwork }}"
      operator: Equals
      value: true
```
Container escape với privileged mode là attack vector phổ biến nhất — policy này chặn từ admission.

#### Policy 5: enforce-security-context
```yaml
# Bắt buộc security context đầy đủ
deny:
  conditions:
    any:
    - key: "{{ element.securityContext.runAsNonRoot }}"
      operator: NotEquals
      value: true
    - key: "{{ element.securityContext.allowPrivilegeEscalation }}"
      operator: NotEquals
      value: false
```
Kết hợp với PSS restricted, tạo thành 2 lớp kiểm tra độc lập — PSS ở Kubernetes API server, Kyverno ở Admission Webhook.

### 5.4. Istio Ambient Mode — mTLS STRICT + 12 AuthorizationPolicy

**Istio Ambient Mode** thay thế sidecar proxy truyền thống bằng **ztunnel** (node-level L4 proxy) và **waypoint proxy** (namespace-level L7 proxy). Không cần inject sidecar vào từng pod — Ambient Mode transparent hơn và có overhead thấp hơn.

**PeerAuthentication STRICT:**
```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT  # Từ chối TẤT CẢ plaintext traffic
```
Sau khi áp dụng, mọi kết nối giữa microservices đều được mã hóa TLS 1.3 + xác thực mutual certificate. mTLS coverage: 0% → 100%.

**12 AuthorizationPolicy** xây dựng trên Istio SPIFFE identity (không phải IP/port):

```yaml
# deny-all foundation
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: deny-all
  namespace: production
spec: {}  # Empty = deny everything

---
# Allow CHÍNH XÁC: checkout → payment (L7 gRPC)
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-checkout-to-payment
  namespace: production
spec:
  selector:
    matchLabels:
      app: paymentservice
  action: ALLOW
  rules:
  - from:
    - source:
        principals:
          - "cluster.local/ns/production/sa/checkoutservice"
    to:
    - operation:
        ports: ["50051"]
        methods: ["POST"]  # gRPC = HTTP/2 POST
```

**Tại sao mạnh hơn NetworkPolicy:**
- NetworkPolicy kiểm tra IP + port (L3/L4) — attacker có thể spoof IP
- Istio AuthorizationPolicy kiểm tra **SPIFFE certificate identity** (L7) — không thể forge certificate
- Kết hợp cả hai: NetworkPolicy ngăn kết nối mạng, Istio ngăn ở tầng application

### 5.5. External Secrets Operator (AWS Secrets Manager + KMS)

**Vấn đề cũ:** Secret được base64-encode và lưu trong Kubernetes Secret — bất kỳ ai có `kubectl get secret` đều đọc được, secret committed nhầm vào git.

**Giải pháp:** Secrets chỉ tồn tại trong AWS Secrets Manager (encrypted bằng KMS). ESO sync về Kubernetes khi pod cần:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: payment-secret
  namespace: production
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: payment-secret      # Kubernetes Secret tạo ra
    creationPolicy: Owner     # ESO quản lý lifecycle
  data:
  - secretKey: api-key        # Key trong K8s Secret
    remoteRef:
      key: prod/payment/api-key  # Path trong Secrets Manager
```

**Lợi ích:**
- Secret rotation tự động mỗi 1 giờ (Secrets Manager auto-rotate + ESO sync)
- Audit trail đầy đủ trong CloudTrail: ai, khi nào, từ đâu truy cập secret
- Zero static secrets trong git, CI/CD, hay Kubernetes manifest

### 5.6. Falco eBPF — Runtime Threat Detection (MTTD < 60s)

**Falco** chạy như DaemonSet, sử dụng **eBPF modern driver** để hook vào Linux kernel syscall — không cần kernel module, không can thiệp vào container workload.

**4 Custom Rules được triển khai:**

```yaml
# Rule 1: Phát hiện shell được spawn trong container
- rule: Shell spawned in container
  desc: Attacker thường spawn /bin/sh, /bin/bash sau khi exploit
  condition: >
    spawned_process and container and
    proc.name in (shell_binaries) and
    not proc.pname in (shell_binaries)
  output: >
    Shell spawned (user=%user.name container=%container.name 
    image=%container.image.repository shell=%proc.name 
    parent=%proc.pname cmdline=%proc.cmdline)
  priority: WARNING
  tags: [container, shell, zerotrust]

# Rule 2: Đọc file nhạy cảm
- rule: Sensitive file read in container
  desc: /etc/shadow, /etc/passwd, SSH keys
  condition: >
    open_read and container and
    fd.name in (/etc/shadow, /etc/passwd, /etc/sudoers,
                /root/.ssh/authorized_keys, /proc/1/environ)
  priority: ERROR
  tags: [container, filesystem, zerotrust]

# Rule 3: Ghi vào thư mục không hợp lệ
- rule: Write to unexpected directory
  desc: Microservices không cần ghi ngoài /tmp
  condition: >
    open_write and container and
    container.name in (frontend, cartservice, paymentservice) and
    not fd.directory in (/tmp, /dev, /proc)
  priority: WARNING
  tags: [container, filesystem, zerotrust]

# Rule 4: Network connection bất thường
- rule: Unexpected outbound connection
  desc: Service gọi ra ngoài cluster
  condition: >
    outbound and container and
    not fd.sip.name in (known_internal_ips)
  priority: WARNING
  tags: [network, zerotrust]
```

**MTTD (Mean Time to Detect):** Từ "không phát hiện được" → dưới 60 giây. Falco emit alert ngay khi syscall xảy ra — không cần polling hay log aggregation delay.

---

## 6. Kết quả Đánh giá

### 6.1. 6 Attack Scenarios (Baseline vs Zero Trust)

| # | Kịch bản tấn công | Baseline | Zero Trust | Cơ chế chặn |
|---|---|---|---|---|
| 1 | Deploy image không được ký | Thành công | **Blocked** | Kyverno verify-image-signature |
| 2 | Pod chạy privileged mode | Thành công | **Blocked** | PSS restricted + Kyverno |
| 3 | Lateral movement frontend → payment | Thành công | **Blocked** | NetworkPolicy + Istio AuthzPolicy |
| 4 | Secret extraction từ Kubernetes | Thành công | **Blocked** | ESO (secrets không lưu trong K8s) |
| 5 | Supply chain: push image độc hại lên ECR | Thành công | **Blocked** | Cosign verify + KMS + Kyverno |
| 6 | Runtime: reverse shell trong container | Thành công | **Limited** | Falco detect + alert (không block) |

> Kịch bản 6 bị "limited" (phát hiện nhưng không tự block) vì Falco ở chế độ detection-only. Cần tích hợp Falco Sidekick → Kubernetes Admission Webhook để tự động terminate pod nghi ngờ.

### 6.2. Metrics So sánh

| Metric | Trước (Baseline) | Sau (Zero Trust) |
|---|---|---|
| Static credentials (IAM Keys) | 5+ | **0** |
| mTLS coverage | 0% | **100%** |
| Image signing | Không có | **100% signed + attested** |
| Mean Time to Detect | Không phát hiện | **< 60 giây** (Falco) |
| Secret exposure risk | Cao (K8s Secrets) | **Thấp** (ESO + Secrets Manager) |
| SBOM coverage | 0 | **10/10 services** |

### 6.3. Chuẩn Compliance

| Chuẩn | Yêu cầu | Đáp ứng | Ghi chú |
|---|---|---|---|
| **NIST SP 800-207** (Zero Trust Architecture) | 7 tenets | **7/7** | Full compliance |
| **SLSA Level 3** | 8 requirements | **7/8** | Thiếu: hermetic build |
| **NSA K8s Hardening Guide** | 5 sections | **5/5** | Full compliance |
| **CIS EKS Benchmark** | Key controls | Đáp ứng chính | IAM, logging, encryption, network |

---

## 7. Công nghệ Sử dụng

| Nhóm | Công nghệ | Mục đích |
|---|---|---|
| **Cloud** | AWS EKS, ECR, IAM Identity Center, KMS, Secrets Manager, Organizations, STS, CloudWatch | Hạ tầng + Identity |
| **IaC** | Terraform 1.6+ (AWS provider 6.35.1) | Provision toàn bộ infra |
| **Orchestration** | Kubernetes 1.31 | Container runtime |
| **CI/CD** | GitHub Actions (6 workflows) | Automation pipeline |
| **Service Mesh** | Istio Ambient Mode + Ztunnel + Waypoint | mTLS + AuthzPolicy |
| **Policy Engine** | Kyverno | Admission control |
| **Runtime Security** | Falco eBPF (modern_ebpf) | Threat detection |
| **Supply Chain** | Cosign/Sigstore, Syft, SLSA | Image signing + provenance |
| **Scanning** | Gitleaks, Semgrep, Trivy, Checkov | Security gates |
| **Secrets** | External Secrets Operator | Dynamic secret injection |

---

## 8. Hạn chế và Hướng Phát triển

### Hạn chế hiện tại:
- **Falco detection-only:** Phát hiện nhưng chưa tự block — cần tích hợp response automation
- **SLSA Level 3 7/8:** Chưa đạt hermetic build (build environment isolation)
- **Docs/error.md ghi nhận:** NetworkPolicy, Pod Identity, và Istio gặp vấn đề cấu hình trong quá trình triển khai — đã fix nhưng cần thêm integration tests
- **Single region:** Chưa có cross-region failover

### Hướng phát triển:
- Tích hợp Falco Sidekick → tự động quarantine pod nghi ngờ
- Thêm OPA/Gatekeeper cho policy-as-code ở tầng infrastructure
- Triển khai OIDC-based Workload Identity cho multi-cloud
- Automated SBOM vulnerability scanning khi CVE mới xuất hiện
- Chaos engineering để test resilience của security controls

---

*Đồ án tốt nghiệp — Hệ thống Thông tin, Trường Đại học Sư phạm Kỹ thuật TP.HCM (HCMUTE), 2025–2026*
