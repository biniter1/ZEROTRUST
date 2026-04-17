#!/bin/bash
# ============================================================
# KYVERNO — cài đặt và verify
# Chạy file này một lần để setup Kyverno trên EKS
# ============================================================

set -euo pipefail

CLUSTER_NAME="online-boutique-prod"
REGION="ap-southeast-1"
KMS_KEY_ARN="arn:aws:kms:ap-southeast-1:${AWS_ACCOUNT_ID}:key/${KMS_KEY_ID}"

echo "=== Step 1: Update kubeconfig ==="
aws eks update-kubeconfig \
  --region "$REGION" \
  --name "$CLUSTER_NAME"

# ── CÀI KYVERNO ──────────────────────────────────────────────
echo "=== Step 2: Cài Kyverno ==="

helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

# replicaCount: 3 cho HA — Kyverno là admission controller
# Nếu Kyverno down → failurePolicy: Fail → mọi Pod đều bị reject
# Nên phải đảm bảo Kyverno luôn chạy
helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set replicaCount=3 \
  --set resources.limits.cpu=500m \
  --set resources.limits.memory=512Mi \
  --wait

echo "Kyverno installed:"
kubectl get pods -n kyverno

# ── APPLY POLICIES ────────────────────────────────────────────
echo "=== Step 3: Apply policies ==="

# Thay KEY_ID trong file trước khi apply
sed "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g; s/KEY_ID/${KMS_KEY_ID}/g" \
  k8s/manifests/kyverno/policies.yaml | kubectl apply -f -

echo "Policies applied:"
kubectl get clusterpolicies

# ── VERIFY POLICIES ───────────────────────────────────────────
echo "=== Step 4: Test policies ==="

# Test 1: Pod dùng :latest → phải bị reject
echo "--- Test 1: Block latest tag ---"
cat <<EOF | kubectl apply -f - 2>&1 | grep -E "Error|blocked|created"
apiVersion: v1
kind: Pod
metadata:
  name: test-latest
  namespace: production
spec:
  containers:
  - name: test
    image: nginx:latest
    resources:
      limits:
        cpu: 100m
        memory: 64Mi
EOF
# Kết quả mong đợi: "Error ... blocked due to ... block-mutable-tags"

# Test 2: Pod không có resource limits → phải bị reject
echo "--- Test 2: Block missing limits ---"
cat <<EOF | kubectl apply -f - 2>&1 | grep -E "Error|blocked|created"
apiVersion: v1
kind: Pod
metadata:
  name: test-no-limits
  namespace: production
spec:
  containers:
  - name: test
    image: nginx@sha256:abc123
EOF
# Kết quả mong đợi: "Error ... blocked due to ... require-resource-limits"

# Test 3: Pod privileged → phải bị reject
echo "--- Test 3: Block privileged ---"
cat <<EOF | kubectl apply -f - 2>&1 | grep -E "Error|blocked|created"
apiVersion: v1
kind: Pod
metadata:
  name: test-privileged
  namespace: production
spec:
  containers:
  - name: test
    image: nginx@sha256:abc123
    securityContext:
      privileged: true
    resources:
      limits:
        cpu: 100m
        memory: 64Mi
EOF
# Kết quả mong đợi: "Error ... blocked due to ... deny-privileged-containers"

echo "=== Kyverno setup complete ==="

# ── XEM POLICY REPORTS ───────────────────────────────────────
# Sau khi apply policies, Kyverno tự scan pods đang chạy
# và tạo PolicyReport
echo "=== Policy Reports (background scan) ==="
kubectl get policyreport -n production
# Nếu có pod vi phạm → hiện trong report này

# Xem chi tiết
# kubectl describe policyreport -n production