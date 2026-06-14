# Zero Trust DevSecOps on AWS EKS

> End-to-end Zero Trust Architecture across identity, CI/CD supply chain, and Kubernetes runtime — validated against NIST SP 800-207, SLSA Level 3, and NSA K8s Hardening Guide.

![License](https://img.shields.io/badge/license-MIT-blue) ![Kubernetes](https://img.shields.io/badge/kubernetes-1.31-326CE5?logo=kubernetes&logoColor=white) ![Terraform](https://img.shields.io/badge/terraform-IaC-7B42BC?logo=terraform&logoColor=white) ![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?logo=amazonaws&logoColor=white) ![SLSA](https://img.shields.io/badge/SLSA-Level%203-green) ![NIST](https://img.shields.io/badge/NIST%20SP%20800--207-7%2F7-success)

---

## Architecture Overview

Demo workload: [Google Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo) (10 microservices) — Region: `ap-southeast-1`

| Layer | Components | Standards |
|---|---|---|
| **L1 — Identity & Access Control** | AWS Organizations (4 SCP), IAM Identity Center (SSO + MFA), GitHub OIDC (15-min TTL STS), EKS Pod Identity (10 IAM roles), Istio SPIFFE/mTLS | NIST SP 800-207, Zero Trust Tenets |
| **L2 — Secure CI/CD Supply Chain** | 3 workflows (`ci.yml` → `build.yml` → `deploy.yml`), 7 security gates, Cosign/KMS signing, Syft SBOM, SLSA Provenance, deploy-by-digest | SLSA Level 3, SSDF |
| **L3 — Kubernetes Runtime Security** | PSS restricted, NetworkPolicy default-deny, Kyverno (5 ClusterPolicy), Istio Ambient mTLS STRICT (12 AuthorizationPolicy), External Secrets Operator, Falco eBPF | NSA K8s Hardening Guide, CIS Benchmarks |

---

## Security Pipeline

```
Pull Request
    │
    ▼
[ci.yml] ── Gitleaks (secret scan)
         ── Semgrep (SAST)
         ── Trivy FS (SCA)
         └─ Checkov (IaC scan)
    │ gates pass
    ▼
Merge to main
    │
    ▼
[build.yml] ── Docker build
            ── Trivy image scan
            ── Cosign sign (AWS KMS)
            └─ Syft SBOM + SLSA Provenance
    │ build gate passes
    ▼
[deploy.yml] ── Deploy by digest @sha256
             ── Kyverno verify-image-signature
             └─ Istio Ambient mTLS STRICT
    │
    ▼
Runtime: Falco eBPF (MTTD < 60s)
```

---

## Evaluation Results

| Metric | Baseline | Zero Trust |
|---|---|---|
| Attack scenarios blocked (6 tested) | 0 / 6 | 5 blocked, 1 limited |
| Static credentials | 5+ | **0** |
| mTLS service coverage | 0% | **100%** |
| Mean Time to Detect (MTTD) | None | **< 60 seconds** (Falco) |
| NIST SP 800-207 tenets | — | **7 / 7** |
| SLSA Level 3 requirements | — | **7 / 8** |
| NSA K8s Hardening Guide sections | — | **5 / 5** |

---

## Standards Compliance

| Standard | Requirements | Met | Status |
|---|---|---|---|
| NIST SP 800-207 | 7 tenets | 7 | ✅ Full |
| SLSA Level 3 | 8 requirements | 7 | ✅ Level 3 |
| NSA K8s Hardening Guide | 5 sections | 5 | ✅ Full |

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       ├── ci.yml          # PR gates: Gitleaks, Semgrep, Trivy FS, Checkov
│       ├── build.yml       # Build, Trivy image, Cosign sign, SBOM, Provenance
│       └── deploy.yml      # Deploy by digest, post-deploy validation
├── Terraform/
│   ├── modules/
│   │   ├── compute/        # EKS cluster, node groups, Pod Identity
│   │   ├── iam/            # IAM roles, OIDC federation, SCPs
│   │   ├── network/        # VPC, subnets, security groups
│   │   └── security/       # KMS, Secrets Manager, CloudWatch
│   └── environments/
│       └── staging/
├── k8s/
│   ├── manifests/
│   │   ├── ambient/        # Istio Ambient mode, AuthorizationPolicy (12)
│   │   ├── network-policy/ # Default-deny + 10 explicit allow rules
│   │   └── kyverno/        # 5 ClusterPolicy (enforce)
│   └── external-secrets/   # ExternalSecret + SecretStore resources
└── docs/                   # Architecture diagrams, evaluation reports
```

---

## Quick Start

### Prerequisites

- AWS CLI v2 + credentials with admin access
- Terraform >= 1.6
- `kubectl`, `helm`, `cosign`, `syft`
- GitHub repository with OIDC federation configured

### Deploy

```bash
# 1. Clone
git clone https://github.com/<org>/zero-trust-devsecops.git
cd zero-trust-devsecops

# 2. Provision infrastructure
cd Terraform/environments/staging
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 3. Configure kubeconfig
aws eks update-kubeconfig --region ap-southeast-1 --name <cluster-name>

# 4. Install Istio Ambient + Kyverno + Falco via Helm
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm install istio-base istio/base -n istio-system --create-namespace
helm install istiod istio/istiod -n istio-system
helm install ztunnel istio/ztunnel -n istio-system

# 5. Apply K8s manifests
kubectl apply -f k8s/manifests/network-policy/
kubectl apply -f k8s/manifests/kyverno/
kubectl apply -f k8s/manifests/ambient/
kubectl apply -f k8s/external-secrets/

# 6. Deploy Online Boutique (CI/CD triggers automatically on push)
```

> Full deployment guide: [`docs/deployment.md`](docs/)

---

## Tech Stack

| Category | Tools |
|---|---|
| Cloud | AWS EKS, ECR, IAM Identity Center, KMS, Secrets Manager, Organizations, STS, CloudWatch |
| Infrastructure as Code | Terraform |
| Container Orchestration | Kubernetes 1.31 |
| CI/CD | GitHub Actions |
| Service Mesh | Istio Ambient Mode (SPIFFE/mTLS) |
| Policy Engine | Kyverno |
| Runtime Security | Falco eBPF (modern_ebpf) |
| Supply Chain | Cosign/Sigstore, Syft, SLSA |
| Scanning | Gitleaks, Semgrep, Trivy, Checkov |
| Secrets | External Secrets Operator |

---

## Author

**Student:** Nguyen Son Bin — Ho Chi Minh City University of Technology and Education (HCMUTE)  
**Advisor:** [Advisor Name] — [Department]  
**Year:** 2025–2026
