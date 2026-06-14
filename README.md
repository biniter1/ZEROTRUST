# Zero Trust DevSecOps on AWS EKS

> Implements a complete Zero Trust Architecture across three independent security layers — identity & access, CI/CD supply chain, and Kubernetes runtime — validated against NIST SP 800-207, SLSA Level 3, and NSA K8s Hardening Guide. Demo workload: **Google Online Boutique** (10 microservices, gRPC). Region: `ap-southeast-1`.

![License](https://img.shields.io/badge/license-MIT-blue)
![Kubernetes](https://img.shields.io/badge/kubernetes-1.31-326CE5?logo=kubernetes&logoColor=white)
![Terraform](https://img.shields.io/badge/terraform-%3E%3D1.6-7B42BC?logo=terraform&logoColor=white)
![AWS EKS](https://img.shields.io/badge/AWS-EKS-FF9900?logo=amazonaws&logoColor=white)
![SLSA Level 3](https://img.shields.io/badge/SLSA-Level%203-green)
![NIST 800-207](https://img.shields.io/badge/NIST%20SP%20800--207-7%2F7-success)
![NSA K8s](https://img.shields.io/badge/NSA%20K8s%20Guide-5%2F5-success)

---

## Table of Contents

- [Problem Statement](#problem-statement)
- [Architecture Overview](#architecture-overview)
- [Layer 1 — Identity & Access Control](#layer-1--identity--access-control)
- [Layer 2 — Secure CI/CD Supply Chain](#layer-2--secure-cicd-supply-chain)
- [Layer 3 — Kubernetes Runtime Security](#layer-3--kubernetes-runtime-security)
- [Evaluation Results](#evaluation-results)
- [Repository Structure](#repository-structure)
- [Quick Start](#quick-start)
- [Standards Compliance](#standards-compliance)
- [Author](#author)

---

## Problem Statement

Traditional DevOps pipelines assume implicit trust once inside the network perimeter. This project addresses six concrete attack vectors that conventional setups leave open:

| Attack Vector | Conventional DevOps | This Project |
|---|---|---|
| Long-lived AWS IAM keys in CI/CD secrets | ✗ Static keys with no expiry | ✅ OIDC short-lived tokens (15-min TTL) |
| Unsigned container images | ✗ No supply chain verification | ✅ Cosign + AWS KMS signing |
| Lateral movement between microservices | ✗ Flat network, any pod → any pod | ✅ NetworkPolicy + Istio AuthzPolicy |
| Secrets stored in Kubernetes Secrets (base64) | ✗ Readable by any cluster admin | ✅ AWS Secrets Manager + ESO |
| No runtime threat visibility | ✗ Zero detection capability | ✅ Falco eBPF, MTTD < 60 s |
| Overly broad pod IAM permissions | ✗ Shared node role for all pods | ✅ 10 per-service least-privilege roles |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  LAYER 1 — Identity & Access Control                                        │
│                                                                             │
│  AWS Organizations (4 SCP)  │  IAM Identity Center (SSO + MFA)             │
│  GitHub OIDC Federation     │  EKS Pod Identity (10 roles)                 │
│  Istio SPIFFE/X.509 Identity                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│  LAYER 2 — Secure CI/CD Supply Chain                                        │
│                                                                             │
│  ci.yml (PR)  ──►  build.yml (merge)  ──►  deploy.yml (workflow_run)       │
│  Gitleaks · Semgrep · Trivy FS · Checkov                                    │
│  Trivy image · Cosign/KMS · Syft SBOM · SLSA Provenance · deploy@sha256    │
├─────────────────────────────────────────────────────────────────────────────┤
│  LAYER 3 — Kubernetes Runtime Security                                      │
│                                                                             │
│  PSS restricted (enforce)  │  NetworkPolicy default-deny + 10 allow        │
│  Kyverno 5 ClusterPolicy   │  Istio Ambient mTLS STRICT (12 AuthzPolicy)   │
│  External Secrets Operator │  Falco eBPF (modern_ebpf, 4 custom rules)     │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Layer 1 — Identity & Access Control

### AWS Organizations — 4 Service Control Policies

The entire AWS footprint is governed under AWS Organizations with 8 Organizational Units (Security, Infrastructure, Workloads/Dev/Staging/Prod). Four SCPs enforce guardrails that cannot be overridden even by account root:

| SCP | Enforcement |
|---|---|
| Region restriction | All actions blocked outside `ap-southeast-1` |
| MFA enforcement | Sensitive IAM actions require MFA session |
| No long-lived keys | Creating IAM User access keys is denied org-wide |
| Audit protection | Disabling CloudTrail or AWS Config is denied |

### IAM Identity Center — SSO + MFA

All human access (developer, DevOps, admin) routes through IAM Identity Center — no individual IAM Users with static passwords. Permission Sets map to K8s RBAC groups via `aws-auth`:

| Role | AWS Access | K8s Access |
|---|---|---|
| Developer | Read-only (no secrets) | `k8s-developers` — get/list/watch, no `exec` |
| DevOps | Full staging, read-only prod | `k8s-devops` — view prod, full staging |
| Admin | Break-glass (1-hour TTL) | `k8s-admins` — cluster-admin, emergency only |
| GitHub Actions | ECR push / EKS deploy | `k8s-deployers` — deploy production only |

### GitHub OIDC Federation — Zero Static Credentials

CI/CD workers never hold a long-lived AWS key. The flow per workflow run:

```
GitHub Actions Runner
  │  (1) Request OIDC JWT from GitHub
  ▼
GitHub OIDC Endpoint
  │  (2) JWT signed with GitHub's private key
  │      claims: sub=repo:org/repo:ref:refs/heads/main
  ▼
AWS STS AssumeRoleWithWebIdentity
  │  (3) Verify JWT signature + claim conditions
  │      Condition: repo must match, ref must be main
  ▼
Temporary STS credentials  (TTL: 900 seconds)
  │  (4) Usable for ECR push / EKS deploy — expires automatically
  ▼
gha-ecr-push-role  ─── ECR: push, sign, describe images
gha-eks-deploy-role ─── EKS: describe cluster, update deployments
```

Two least-privilege roles are provisioned via Terraform (`modules/IRSA/GITHUB-ECR/`, `modules/IRSA/GITHUB-EKS/`). `gha-ecr-push-role` cannot deploy; `gha-eks-deploy-role` cannot push images — blast radius is isolated.

### EKS Pod Identity — 10 Per-Service IAM Roles

The EKS Pod Identity Agent addon (`v1.3.2-eksbuild.2`) binds each ServiceAccount to a dedicated IAM role. No pod can access resources belonging to another service:

| Service | IAM Permission Granted | Denied (implicitly) |
|---|---|---|
| `frontend` | ECR: GetAuthorizationToken, GetImage | Secrets Manager, SES, CloudWatch |
| `cartservice` | ElastiCache: DescribeReplicationGroups | Everything else |
| `checkoutservice` | Secrets Manager: GetSecretValue (`prod/checkout/*`) | Other services' secrets |
| `paymentservice` | Secrets Manager: GetSecretValue (`prod/payment/*`) | ECR, SES, CloudWatch |
| `emailservice` | SES: SendEmail, SendRawEmail | Secrets Manager, ECR |
| `adservice` | CloudWatch: PutMetricData, GetMetricData | Secrets Manager, ECR, SES |
| `shippingservice` | ECR: GetAuthorizationToken | Secrets Manager, SES |
| `recommendationservice` | ECR: GetAuthorizationToken | Secrets Manager, SES |
| `currencyservice` | ECR: GetAuthorizationToken | Secrets Manager, SES |
| `productcatalogservice` | ECR: GetAuthorizationToken | Secrets Manager, SES |

If `paymentservice` is compromised and an attacker escapes the container, they gain read access to `prod/payment/*` secrets only — they cannot read Redis credentials, send emails, or access any other service's resources.

### Istio SPIFFE Identity

Every pod in `production` and `staging` receives an X.509 SVID (SPIFFE Verifiable Identity Document):

```
spiffe://cluster.local/ns/production/sa/paymentservice
```

Istio Ambient Mode rotates these certificates automatically. All inter-service traffic is authenticated via mutual TLS — an attacker who intercepts network traffic cannot impersonate a service without its certificate's private key.

---

## Layer 2 — Secure CI/CD Supply Chain

### Workflow Trigger Chain

```
┌───────────────────────────────────────────────────────────────────────┐
│  Pull Request opened/updated                                          │
│  └─► ci.yml — 4 security gates + language CI (must all pass)         │
│                                                                       │
│  Merge to main                                                        │
│  └─► build.yml — build + 3 supply chain gates + signing + attest     │
│                                                                       │
│  build.yml completes (workflow_run trigger)                           │
│  └─► deploy.yml — pre-verify → staging → gate → production           │
│                                                                       │
│  Emergency                                                            │
│  └─► rollback.yml — manual dispatch, auto-creates incident issue     │
│                                                                       │
│  Semver tag push (v*)                                                 │
│  └─► release.yml — retag via crane, re-verify signatures             │
└───────────────────────────────────────────────────────────────────────┘
```

### ci.yml — Security Gates on Every Pull Request

`dorny/paths-filter` detects which of the 10 services changed and runs only the relevant language CI jobs (Go, Python, Node.js, Java, .NET), cutting pipeline time significantly. All four security gates run unconditionally:

**Gate 1 — Gitleaks (secret scanning)**
Scans the full git history for AWS keys, private keys, API tokens, passwords, and certificates. Results upload as SARIF to GitHub Security Dashboard. Fails PR if any secret is found.

**Gate 2 — Semgrep (SAST)**
Runs three rulesets: `p/security-audit`, `p/secrets`, `p/owasp-top-ten`. Two modes: `report` (SARIF upload) and `enforce` (exit-code 1 on findings). Catches SQL injection, path traversal, hardcoded credentials, insecure deserialization.

**Gate 3 — Trivy FS (SCA)**
Scans `go.mod`, `package.json`, `requirements.txt`, `pom.xml` for dependencies with known CVEs. Severity threshold: `CRITICAL,HIGH`. Enforce mode blocks PR merge.

**Gate 4 — Checkov (IaC scan)**
Runs only when Terraform files change. Validates 500+ rules: encryption at rest, public S3, overly permissive security groups, IMDSv2 disabled, missing CloudTrail.

**ci-gate** is a required status check — GitHub Branch Protection enforces that all four gates and all language CI jobs pass before merge is allowed.

### build.yml — Build, Scan, Sign, Attest

Runs as a matrix job per changed service. Uses `dorny/paths-filter` to build only what changed.

**Step 1 — Docker build**
```bash
docker build \
  --build-arg VERSION=${{ github.sha }} \
  --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  -t $ECR_REPO/$SERVICE:sha-$SHORT_SHA .
```
Images are tagged with the git SHA — no `latest`, no semantic version at build time.

**Step 2 — Trivy image scan (blocks on CRITICAL)**
```bash
trivy image --severity CRITICAL --exit-code 1 $ECR_REPO/$SERVICE:sha-$SHORT_SHA
```
Scans OS packages, language runtime, and application libraries inside the built image. Pipeline halts if any CRITICAL CVE is found — the image never reaches ECR.

**Step 3 — Cosign sign with AWS KMS**
```bash
cosign sign \
  --key awskms:///$KMS_KEY_ARN \
  --annotations "github-sha=${{ github.sha }}" \
  --annotations "github-repo=${{ github.repository }}" \
  --annotations "service=$SERVICE" \
  $ECR_REPO/$SERVICE@$DIGEST
```
The KMS private key never leaves AWS HSM. The signature is stored as an OCI artifact in the same ECR repository. Anyone can verify: `cosign verify --key awskms:///$KMS_KEY_ARN <image>`.

**Step 4 — Syft SBOM + Cosign attestation**
```bash
syft $ECR_REPO/$SERVICE@$DIGEST -o cyclonedx-json > sbom.json
cosign attest --predicate sbom.json --type cyclonedx \
  --key awskms:///$KMS_KEY_ARN $ECR_REPO/$SERVICE@$DIGEST
```
CycloneDX SBOM lists every OS package and application library in the image. The SBOM is cryptographically attached to the image digest — when a new CVE is published, any service using the affected package can be identified within minutes by querying attested SBOMs.

**Step 5 — SLSA Provenance attestation**
```yaml
uses: actions/attest-build-provenance@v1
```
Records: build system identity, GitHub Actions workflow SHA, input commit, base image. Stored in the OCI registry. Satisfies SLSA Level 3 requirements for provenance (7/8 — hermetic build isolation is the remaining gap).

### deploy.yml — Staging → Gate → Production

**Pre-deploy verification** (runs before any kubectl command):
```bash
# Verify signature
cosign verify --key awskms:///$KMS_KEY_ARN $ECR_REPO/$SERVICE@$DIGEST

# Verify SBOM attestation
cosign verify-attestation --type cyclonedx \
  --key awskms:///$KMS_KEY_ARN $ECR_REPO/$SERVICE@$DIGEST

# Verify SLSA provenance
gh attestation verify oci://$ECR_REPO/$SERVICE@$DIGEST --repo $GITHUB_REPO
```
If any of the three checks fails, the deploy aborts — the image is treated as untrusted regardless of how it arrived in ECR.

**Deploy by digest, never by tag:**
```bash
DIGEST=$(aws ecr describe-images \
  --repository-name $SERVICE \
  --image-ids imageTag=sha-$SHORT_SHA \
  --query 'imageDetails[0].imageDigest' --output text)

helm upgrade $SERVICE ./helm-chart \
  --set image.digest=$DIGEST   # @sha256:... is immutable
```
Tags can be overwritten (push a new image with the same tag). A digest is content-addressable and cannot be changed after signing.

**Production gate:** Requires manual approval via GitHub Environments protection. After approval, a final cosign verification runs. Post-deploy, a CloudWatch metric `ProductionDeployment=1` is emitted for audit trail. If the rollout fails within 600 seconds, Helm auto-rollbacks and a GitHub Incident Issue is created automatically.

---

## Layer 3 — Kubernetes Runtime Security

### Pod Security Standards — `restricted` enforce

Namespaces `production` and `staging` are labeled `enforce: restricted`. The Kubernetes API server rejects any Pod that violates — no exceptions, no warnings:

```yaml
pod-security.kubernetes.io/enforce: restricted   # blocks non-compliant pods at admission
pod-security.kubernetes.io/audit:   restricted   # logs violations even if not blocked
pod-security.kubernetes.io/warn:    restricted   # surfaces warnings in kubectl output
```

Restricted profile requires: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault`, no `hostNetwork/hostPID/hostIPC`.

### NetworkPolicy — Default-Deny + 10 Explicit Allow

```yaml
# Blocks ALL ingress and egress by default in production
kind: NetworkPolicy
metadata: { name: default-deny-all, namespace: production }
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
  # no rules = deny everything
```

Ten service-specific policies open only the exact ports required. The most security-critical example — `paymentservice`:

```yaml
# paymentservice: only checkoutservice may call it (not frontend directly)
spec:
  podSelector:
    matchLabels: { app: paymentservice }
  ingress:
  - from:
    - podSelector:
        matchLabels: { app: checkoutservice }   # whitelist by label, not IP
    ports:
    - port: 50051
  egress:
  - ports:
    - { port: 53, protocol: UDP }               # DNS only — no outbound
```

This enforces the business logic at the network layer: frontend cannot bypass checkout validation and call the payment service directly.

### Kyverno — 5 ClusterPolicy in `Enforce` Mode

All five policies run as Admission Webhooks — they intercept every Pod creation/update before Kubernetes accepts it.

| Policy | What it Enforces | Attack Blocked |
|---|---|---|
| `verify-image-signature` | Image must have valid Cosign signature from AWS KMS key | Supply chain attack, unauthorized image |
| `block-mutable-tags` | Image reference must be `@sha256:…`, not `:latest`/`:main` | Tag overwrite, mutable image substitution |
| `require-resource-limits` | Every container must declare CPU/memory requests & limits | Resource exhaustion, noisy-neighbor DoS |
| `deny-privileged-containers` | `privileged: true`, `hostNetwork`, `hostPID`, `hostIPC` forbidden | Container escape via privileged mode |
| `enforce-security-context` | `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities.drop: ALL`, `seccompProfile: RuntimeDefault` | Privilege escalation, unrestricted syscalls |

`verify-image-signature` and `deny-privileged-containers` each provide a second, independent enforcement layer on top of PSS restricted — if one is misconfigured, the other still catches the violation.

### Istio Ambient Mode — mTLS STRICT + 12 AuthorizationPolicy

Istio Ambient Mode uses a **ztunnel** (node-level L4 proxy) and **waypoint proxy** (namespace-level L7 proxy) — no sidecar injection required, lower overhead than traditional Istio.

**PeerAuthentication STRICT** rejects all plaintext traffic cluster-wide:
```yaml
kind: PeerAuthentication
metadata: { name: default, namespace: production }
spec:
  mtls:
    mode: STRICT   # TLS 1.3 + mutual cert auth on every connection
```
mTLS coverage: 0% → 100%.

**12 AuthorizationPolicy** enforce access control on SPIFFE identity (not IP/port, which can be spoofed):

```yaml
# Foundation: deny everything
kind: AuthorizationPolicy
metadata: { name: deny-all, namespace: production }
spec: {}   # empty spec = deny all

# Example: only checkoutservice (by SPIFFE cert) may reach paymentservice
kind: AuthorizationPolicy
metadata: { name: allow-checkout-to-payment }
spec:
  selector:
    matchLabels: { app: paymentservice }
  action: ALLOW
  rules:
  - from:
    - source:
        principals:
        - "cluster.local/ns/production/sa/checkoutservice"
    to:
    - operation:
        ports: ["50051"]
        methods: ["POST"]   # gRPC = HTTP/2 POST
```

NetworkPolicy enforces at L3/L4; Istio AuthorizationPolicy enforces at L7 on cryptographic identity. An attacker who compromises a node and spoofs a pod IP still cannot pass the mTLS certificate check.

### External Secrets Operator — No Secrets in Kubernetes

Secrets live in AWS Secrets Manager (encrypted by KMS), never in the cluster. ESO syncs them into short-lived Kubernetes Secrets at runtime:

```yaml
kind: ExternalSecret
metadata: { name: payment-secret, namespace: production }
spec:
  refreshInterval: 1h         # ESO re-reads from Secrets Manager every hour
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: payment-secret      # K8s Secret created and managed by ESO
    creationPolicy: Owner
  data:
  - secretKey: api-key
    remoteRef:
      key: prod/payment/api-key   # path in AWS Secrets Manager
```

Benefits: secret rotation is automatic (Secrets Manager rotates → ESO syncs within 1 hour), full CloudTrail audit of every secret access, zero secrets committed to git or CI/CD variables.

### Falco eBPF — Runtime Threat Detection

Falco runs as a DaemonSet using the **`modern_ebpf`** driver — hooks into Linux kernel syscalls without a kernel module, zero impact on workload performance.

Four custom detection rules tuned for Online Boutique:

| Rule | Trigger | Severity | Signal |
|---|---|---|---|
| `Shell spawned in container` | `/bin/sh`, `/bin/bash`, etc. executed inside any container | WARNING | Post-exploit shell access |
| `Sensitive file read` | Read of `/etc/shadow`, `/etc/passwd`, `/root/.ssh/*`, `/proc/1/environ` | ERROR | Credential harvesting |
| `Write to unexpected dir` | Write outside `/tmp`, `/dev`, `/proc` in frontend/cart/payment/checkout/catalog | WARNING | Malware persistence |
| `Unexpected outbound connection` | Pod connects to IP outside known internal CIDR | WARNING | C2 callback, data exfil |

Alert fires within the same syscall event — **MTTD < 60 seconds** from intrusion to alert, compared to zero detection capability in the baseline.

---

## Evaluation Results

### Attack Scenarios — Baseline vs Zero Trust

| # | Attack Scenario | Baseline | Zero Trust | Blocking Mechanism |
|---|---|---|---|---|
| 1 | Deploy unsigned container image to production | ✗ Succeeds | ✅ Blocked | Kyverno `verify-image-signature` |
| 2 | Launch privileged pod (`securityContext.privileged: true`) | ✗ Succeeds | ✅ Blocked | PSS restricted + Kyverno `deny-privileged-containers` |
| 3 | Lateral movement: frontend → paymentservice (direct gRPC) | ✗ Succeeds | ✅ Blocked | NetworkPolicy + Istio AuthorizationPolicy |
| 4 | Extract secrets via `kubectl get secret` | ✗ Succeeds | ✅ Blocked | ESO (no secrets stored in K8s) |
| 5 | Push tampered image to ECR, deploy it | ✗ Succeeds | ✅ Blocked | Cosign verify + Kyverno at admission |
| 6 | Reverse shell inside compromised container | ✗ No detection | ⚠ Limited | Falco detects + alerts, does not auto-terminate |

> Scenario 6 is "limited" rather than blocked — Falco operates in detection-only mode. Full blocking requires Falco Sidekick → Kubernetes Admission Webhook integration (identified as future work).

### Security Posture Metrics

| Metric | Baseline | Zero Trust |
|---|---|---|
| Static AWS credentials (IAM keys) | 5+ | **0** |
| mTLS inter-service coverage | 0% | **100%** |
| Image signing coverage | 0% | **100%** (all 10 services) |
| SBOM coverage | 0 services | **10 / 10 services** |
| Mean Time to Detect (runtime threats) | None | **< 60 seconds** |
| Secrets stored in Kubernetes | Yes | **No** (ESO + Secrets Manager) |
| Attack scenarios blocked | 0 / 6 | **5 blocked, 1 limited** |

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       ├── ci.yml                   # PR: Gitleaks, Semgrep, Trivy FS, Checkov + language CI
│       ├── build.yml                # Push main: build, Trivy image, Cosign, SBOM, Provenance
│       ├── deploy.yml               # workflow_run: pre-verify → staging → gate → production
│       ├── rollback.yml             # Manual dispatch: emergency rollback + incident issue
│       ├── release.yml              # Semver tag: crane retag + re-verify
│       ├── reusable-go-ci.yml       # Shared Go build + test job
│       ├── reusable-python-ci.yml   # Shared Python lint + test job
│       ├── reusable-nodejs-ci.yml   # Shared Node.js build + test job
│       ├── reusable-java-ci.yml     # Shared Java build + test job
│       └── reusable-dotnet-ci.yml   # Shared .NET build + test job
├── Terraform/
│   ├── main.tf                      # Root module composition
│   ├── variables.tf                 # Region, project, CIDR, GitHub org/repo
│   ├── outputs.tf                   # Cluster endpoint, node group, IAM ARNs
│   └── modules/
│       ├── vpc/                     # VPC, public/private subnets (2 AZ), NAT GW
│       ├── compute/
│       │   ├── eks_cluster/         # EKS control plane, private endpoint, KMS encryption
│       │   └── eks_node/            # Managed node groups (ON_DEMAND, private subnets)
│       ├── identity/
│       │   └── iam/                 # EKS cluster role, node role, GitHub OIDC provider
│       ├── IRSA/
│       │   ├── GITHUB-ECR/          # gha-ecr-push-role (ECR push + KMS decrypt)
│       │   └── GITHUB-EKS/          # gha-eks-deploy-role (EKS describe + deploy)
│       ├── Pod_Identity/            # EKS Pod Identity addon + 10 per-service IAM roles
│       ├── kms/                     # KMS key (EKS secrets encryption + CloudWatch logs)
│       ├── organization/            # AWS Organizations, 8 OUs, 4 SCPs
│       ├── security/                # Security groups (ALB, EKS nodes, DB, VPC endpoints)
│       └── secrets/                 # AWS Secrets Manager resources
├── k8s/
│   └── manifests/
│       ├── ambient/
│       │   └── ambient-mtls.yaml    # PeerAuthentication STRICT + 12 AuthorizationPolicy
│       ├── network-policy/
│       │   └── networkpolicies.yaml # default-deny-all + 10 per-service NetworkPolicy
│       ├── kyverno/
│       │   └── policies.yaml        # 5 ClusterPolicy (all Enforce mode)
│       ├── pss/
│       │   └── namespace-labels.yaml # PSS restricted on production/staging namespaces
│       ├── rbac/
│       │   └── rbac.yaml            # aws-auth ConfigMap + 7 ClusterRole/Binding
│       ├── eso/
│       │   └── external-secrets.yaml # 4 ExternalSecret + ClusterSecretStore
│       └── audit/
│           ├── audit-policy.yaml    # K8s audit policy (8 rules, RequestResponse for RBAC)
│           └── falco-rules.yaml     # 4 custom Falco rules (modern_ebpf)
├── helm-chart/                      # Helm chart for all 10 Online Boutique services
├── src/                             # Application source (Go, Python, Node.js, Java, .NET)
├── gitleaks.toml                    # Gitleaks custom ruleset
└── docs/                            # Architecture diagrams, evaluation reports
```

---

## Quick Start

### Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| AWS CLI | v2 | Infrastructure provisioning |
| Terraform | >= 1.6 | IaC |
| kubectl | >= 1.31 | Cluster management |
| helm | >= 3.14 | Application deployment |
| cosign | >= 2.0 | Image signature verification |
| syft | >= 1.0 | SBOM generation |

### 1. Provision AWS Infrastructure

```bash
git clone https://github.com/<org>/zero-trust-devsecops.git
cd zero-trust-devsecops/Terraform/environments/staging

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Terraform provisions: VPC (2 AZ, private subnets), EKS 1.31 cluster (private endpoint, KMS encryption), managed node groups, GitHub OIDC roles, Pod Identity addon + 10 service roles, KMS keys, AWS Organizations SCPs.

### 2. Configure Cluster Access

```bash
aws eks update-kubeconfig \
  --region ap-southeast-1 \
  --name <cluster-name>

kubectl get nodes   # verify connectivity
```

### 3. Install Platform Components

```bash
# Istio Ambient Mode
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm install istio-base  istio/base    -n istio-system --create-namespace
helm install istiod      istio/istiod  -n istio-system --set profile=ambient
helm install istio-cni   istio/cni     -n istio-system --set profile=ambient
helm install ztunnel     istio/ztunnel -n istio-system

# Kyverno
helm repo add kyverno https://kyverno.github.io/kyverno/
helm install kyverno kyverno/kyverno -n kyverno --create-namespace

# Falco (eBPF driver)
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm install falco falcosecurity/falco -n falco --create-namespace \
  --set driver.kind=modern_ebpf \
  --set-file customRules.zero-trust-rules=k8s/manifests/audit/falco-rules.yaml

# External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace
```

### 4. Apply Kubernetes Manifests

```bash
# Namespaces with PSS labels
kubectl apply -f k8s/manifests/pss/

# RBAC (aws-auth + ClusterRoles)
kubectl apply -f k8s/manifests/rbac/

# Network isolation
kubectl apply -f k8s/manifests/network-policy/

# Admission policies
kubectl apply -f k8s/manifests/kyverno/

# Istio mTLS + AuthorizationPolicy
kubectl apply -f k8s/manifests/ambient/

# Secret synchronization
kubectl apply -f k8s/manifests/eso/
```

### 5. Deploy Application

Push to `main` — the workflow chain (`ci.yml` → `build.yml` → `deploy.yml`) triggers automatically. Monitor at the **Actions** tab. Production deployment requires manual approval at the `production-gate` step.

---

## Standards Compliance

| Standard | Area | Requirements | Met | Gap |
|---|---|---|---|---|
| **NIST SP 800-207** | Zero Trust Architecture | 7 tenets | **7 / 7** | — |
| **SLSA Level 3** | Supply Chain Security | 8 requirements | **7 / 8** | Hermetic build isolation |
| **NSA K8s Hardening Guide** | Kubernetes Security | 5 sections | **5 / 5** | — |
| **CIS EKS Benchmark** | Cloud-native Security | Key controls | ✅ | IAM, encryption, logging, network |

**NIST SP 800-207 Tenets Mapping:**

| Tenet | Implementation |
|---|---|
| T1 — All data sources are resources | Pod Identity per-service roles, ESO secret scoping |
| T2 — All communication is secured | Istio mTLS STRICT, NetworkPolicy default-deny |
| T3 — Access granted per-session | OIDC STS (15-min TTL), no persistent sessions |
| T4 — Access determined by dynamic policy | Kyverno ClusterPolicy, Istio AuthorizationPolicy |
| T5 — Monitor integrity of all assets | Falco eBPF, K8s audit policy, CloudWatch |
| T6 — Authentication and authorization enforced | IAM Identity Center MFA, SPIFFE/X.509, RBAC |
| T7 — Collect telemetry for improvement | CloudTrail, CloudWatch Logs, Falco alerts |

---

## Tech Stack

| Category | Technology |
|---|---|
| **Cloud Platform** | AWS EKS, ECR, IAM Identity Center, KMS, Secrets Manager, Organizations, STS, CloudWatch |
| **Infrastructure as Code** | Terraform >= 1.6 (AWS provider 6.35.1) |
| **Container Orchestration** | Kubernetes 1.31 |
| **CI/CD** | GitHub Actions (6 workflows, matrix builds, reusable workflows) |
| **Service Mesh** | Istio Ambient Mode — ztunnel (L4), waypoint proxy (L7), SPIFFE/X.509 |
| **Policy Engine** | Kyverno (Admission Webhook, 5 ClusterPolicy, Enforce mode) |
| **Runtime Security** | Falco eBPF (`modern_ebpf` driver, 4 custom rules) |
| **Image Security** | Cosign/Sigstore (KMS signing), Syft (CycloneDX SBOM), SLSA Provenance |
| **Static Analysis** | Gitleaks (secrets), Semgrep (SAST, OWASP Top 10), Trivy (SCA + image), Checkov (IaC) |
| **Secrets Management** | External Secrets Operator + AWS Secrets Manager + KMS |

---

## Author

**Student:** Nguyen Son Bin  
**Institution:** Ho Chi Minh City University of Technology and Education (HCMUTE)  
**Advisor:** [Advisor Name] — [Department]  
**Academic Year:** 2025 – 2026
