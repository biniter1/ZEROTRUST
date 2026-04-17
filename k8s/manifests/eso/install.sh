#!/bin/bash
# ============================================================
# EXTERNAL SECRETS OPERATOR (ESO) — cài đặt
#
# ESO là gì?
#   Tool tự động sync secret từ AWS Secrets Manager → K8s Secret
#   Pod đọc K8s Secret như bình thường, không cần biết đến AWS
#
# Flow hoạt động:
#   AWS Secrets Manager
#         ↓ (ESO pull về mỗi refreshInterval)
#   ExternalSecret CRD (cấu hình "lấy secret nào")
#         ↓
#   K8s Secret (được ESO tạo và giữ sync)
#         ↓
#   Pod mount Secret dưới dạng file hoặc env var
#
# Tại sao dùng ESO thay vì hardcode?
#   - Secret không bao giờ vào git history
#   - Rotate secret trong AWS → K8s tự cập nhật
#   - Audit trail đầy đủ trong AWS CloudTrail
#   - Không lộ secret trong `kubectl describe pod`
#
# Chuẩn: NSA K8s §6 · CIS EKS 5.3.1 · NIST 800-207 T4
# ============================================================

set -euo pipefail

CLUSTER_NAME="online-boutique-prod"
REGION="ap-southeast-1"
ACCOUNT_ID="${AWS_ACCOUNT_ID}"

echo "=== Step 1: Cài External Secrets Operator ==="
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm upgrade --install external-secrets \
  external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true \
  --set replicaCount=2 \
  --wait

echo "ESO pods:"
kubectl get pods -n external-secrets

echo ""
echo "=== Step 2: Apply manifests ==="
kubectl apply -f k8s/manifests/eso/secret-store.yaml
kubectl apply -f k8s/manifests/eso/external-secrets.yaml

echo ""
echo "=== Step 3: Verify sync ==="
kubectl get externalsecrets -n production
kubectl get secrets -n production | grep -v "default-token"