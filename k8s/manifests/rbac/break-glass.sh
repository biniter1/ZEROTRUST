#!/bin/bash
# ============================================================
# BREAK-GLASS PROCEDURE
#
# Dùng khi nào?
#   - SSO/IAM Identity Center bị lỗi
#   - Cluster bị incident nghiêm trọng cần can thiệp ngay
#   - Không đăng nhập được qua SSO thông thường
#
# Cách hoạt động:
#   1. Admin chạy script này
#   2. Script tạo ClusterRoleBinding cluster-admin tạm thời
#   3. Admin xử lý incident
#   4. Script TỰ XÓA binding sau TTL (mặc định 1 giờ)
#   5. Mọi hành động được ghi vào CloudTrail + K8s audit log
#
# Chuẩn: NSA K8s §5 — break-glass access control
# ============================================================

set -euo pipefail

# ── VALIDATION ────────────────────────────────────────────────
if [ $# -lt 2 ]; then
  echo "Usage: $0 <admin-iam-arn> <reason>"
  echo "Example: $0 arn:aws:iam::123456789:role/AdminRole 'Production outage'"
  exit 1
fi

ADMIN_ARN="$1"
REASON="$2"
TTL_MINUTES="${3:-60}"   # mặc định 60 phút
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
BINDING_NAME="break-glass-${TIMESTAMP}"
CLUSTER_NAME="online-boutique-prod"
REGION="ap-southeast-1"

# ── CONFIRM ───────────────────────────────────────────────────
echo "======================================"
echo "  BREAK-GLASS ACCESS REQUEST"
echo "======================================"
echo "Admin ARN : $ADMIN_ARN"
echo "Reason    : $REASON"
echo "TTL       : ${TTL_MINUTES} minutes"
echo "Time      : $TIMESTAMP"
echo "Cluster   : $CLUSTER_NAME"
echo "======================================"
echo ""
echo "WARNING: This will grant cluster-admin access."
echo "All actions will be logged to CloudTrail and K8s audit log."
echo ""
read -p "Type 'CONFIRM' to proceed: " CONFIRM

if [ "$CONFIRM" != "CONFIRM" ]; then
  echo "Aborted."
  exit 1
fi

# ── LOG TO CLOUDWATCH ─────────────────────────────────────────
echo "Logging break-glass event to CloudWatch..."
aws cloudwatch put-metric-data \
  --namespace "ZeroTrust/Security" \
  --metric-data \
    MetricName=BreakGlassAccess,Value=1,Unit=Count,\
    Dimensions=[{Name=Cluster,Value=$CLUSTER_NAME},{Name=Admin,Value=$ADMIN_ARN}] \
  --region "$REGION"

# ── TẠO CLUSTERROLEBINDING TẠM THỜI ──────────────────────────
echo "Creating temporary cluster-admin binding..."
aws eks update-kubeconfig \
  --region "$REGION" \
  --name "$CLUSTER_NAME"

kubectl create clusterrolebinding "$BINDING_NAME" \
  --clusterrole=cluster-admin \
  --user="$ADMIN_ARN" \
  --dry-run=client -o yaml | \
kubectl annotate --local -f - \
  "security.break-glass/created-at=$TIMESTAMP" \
  "security.break-glass/created-by=$(aws sts get-caller-identity --query Arn --output text)" \
  "security.break-glass/reason=$REASON" \
  "security.break-glass/expires-at=$(date -u -d "+${TTL_MINUTES} minutes" +%Y%m%dT%H%M%SZ 2>/dev/null || date -u -v+${TTL_MINUTES}M +%Y%m%dT%H%M%SZ)" \
  -o yaml | kubectl apply -f -

echo ""
echo "Break-glass access GRANTED:"
echo "  Binding : $BINDING_NAME"
echo "  Expires : ${TTL_MINUTES} minutes from now"
echo ""
echo "Starting auto-cleanup timer..."

# ── AUTO-CLEANUP SAU TTL ──────────────────────────────────────
# Chạy cleanup trong background
(
  sleep $((TTL_MINUTES * 60))
  echo ""
  echo "TTL expired. Revoking break-glass access..."
  kubectl delete clusterrolebinding "$BINDING_NAME" 2>/dev/null || true

  # Log revocation
  aws cloudwatch put-metric-data \
    --namespace "ZeroTrust/Security" \
    --metric-data \
      MetricName=BreakGlassRevoked,Value=1,Unit=Count,\
      Dimensions=[{Name=Cluster,Value=$CLUSTER_NAME}] \
    --region "$REGION"

  echo "Break-glass access REVOKED: $BINDING_NAME"
) &

CLEANUP_PID=$!
echo "Cleanup scheduled (PID: $CLEANUP_PID)"
echo ""
echo "To revoke manually before TTL expires:"
echo "  kubectl delete clusterrolebinding $BINDING_NAME"
echo ""
echo "To check current break-glass bindings:"
echo "  kubectl get clusterrolebindings | grep break-glass"

# ── AUDIT CHECK SCRIPT ────────────────────────────────────────
# Kiểm tra xem có ClusterRoleBinding cluster-admin nào không nên có không
cat > /tmp/check-rbac.sh << 'CHECKSCRIPT'
#!/bin/bash
echo "=== Checking cluster-admin bindings ==="
echo ""
echo "ClusterRoleBindings với cluster-admin:"
kubectl get clusterrolebindings \
  -o jsonpath='{range .items[?(@.roleRef.name=="cluster-admin")]}{.metadata.name}{"\n"}{end}'

echo ""
echo "Nếu thấy binding nào không phải break-glass- hay kyverno → đó là vấn đề"
echo ""
echo "=== Checking for overly permissive roles ==="
kubectl get clusterroles \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | \
  xargs -I{} kubectl get clusterrole {} \
    -o jsonpath='{.metadata.name}: {.rules[*].verbs}{"\n"}' 2>/dev/null | \
  grep '"*"' | grep -v "system:"

echo ""
echo "=== Current break-glass bindings ==="
kubectl get clusterrolebindings | grep break-glass || echo "None"
CHECKSCRIPT

chmod +x /tmp/check-rbac.sh
echo "RBAC audit script saved to: /tmp/check-rbac.sh"
echo "Run: bash /tmp/check-rbac.sh"