#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-oneapi}"
PORTAL_DOMAIN="${PORTAL_DOMAIN:-1api.click}"
API_DOMAIN="${API_DOMAIN:-api.1api.click}"
ADMIN_DOMAIN="${ADMIN_DOMAIN:-admin.1api.click}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/k8s"

if [ ! -f "$K8S_DIR/01-secret.yaml" ]; then
  cat >&2 <<MSG
Missing $K8S_DIR/01-secret.yaml
Copy k8s/01-secret.example.yaml to k8s/01-secret.yaml and fill real values first.
Do not commit k8s/01-secret.yaml.
MSG
  exit 1
fi

echo "Deploying 1API stack to Kubernetes"
echo "Namespace: $NAMESPACE"
echo "Portal domain: $PORTAL_DOMAIN"
echo "API domain: $API_DOMAIN"
echo "Admin domain via external nginx NodePort: $ADMIN_DOMAIN -> 30085"
echo "9router domain via external nginx NodePort: https://router.1api.click -> 30086"
kubectl apply -k "$K8S_DIR"
kubectl -n "$NAMESPACE" rollout status deploy/new-api-postgres --timeout=180s
kubectl -n "$NAMESPACE" rollout status deploy/new-api --timeout=300s
kubectl -n "$NAMESPACE" rollout status deploy/potal-backend --timeout=300s
kubectl -n "$NAMESPACE" rollout status deploy/potal-frontend --timeout=180s
kubectl -n "$NAMESPACE" rollout status deploy/new-api-user-portal --timeout=180s
kubectl -n "$NAMESPACE" rollout status deploy/9router --timeout=300s
kubectl -n "$NAMESPACE" get pods,svc
cat <<MSG

Access after NodePort/external nginx routing:
- Portal:       https://$PORTAL_DOMAIN/
- New API/API:  https://$API_DOMAIN/
- Admin portal: https://$ADMIN_DOMAIN/admin  (external nginx -> nodePort 30085)
- 9router:      https://router.1api.click/  (external nginx -> nodePort 30086)

Ensure external nginx proxies $ADMIN_DOMAIN to Kubernetes nodePort 30085 and router.1api.click to nodePort 30086.
MSG
