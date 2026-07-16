# 1API Kubernetes Deployment

This folder deploys the local stack to Kubernetes. Public traffic is handled by an external nginx that proxies to NodePort services.

It is intentionally sibling to:

- `../new-api`
- `../potal`
- `../deploy`

## Components

- PostgreSQL 16: internal `ClusterIP` service `new-api-postgres:5432`, static NFS PV/PVC `oneapi-postgres-pv` / `postgres-data`.
- New API: service `new-api:3000`, exposed by NodePort `30081` and public host `new.api.1api.click`.
- Portal backend: service `potal-backend:8081`, exposed by NodePort `30082` and public host `api.1api.click`.
- Portal frontend: service `potal-frontend:80`, exposed by NodePort `30083` and public host `1api.click`.
- Optional admin companion: service `new-api-user-portal:3010`, exposed by NodePort `30085` and public host `admin.1api.click` if external nginx is configured for it. The main supported admin channel screen is now integrated into `potal-frontend` at `/admin`.
- 9router: service `nine-router:20128`, exposed by NodePort `30086` and public host `router.1api.click`. Local Compose publishes it at `http://localhost:20129` and exposes it to containers as `http://oneapi-9router:20128`.

Default public URLs after apply:

- Portal: `https://1api.click/`
- Portal admin: `https://1api.click/admin`
- New API: `https://new.api.1api.click/`
- 9router: `https://router.1api.click/`
- Portal backend: `https://api.1api.click/`

## Prerequisites

On the machine where you run deploy:

- `kubectl` configured for the Kubernetes cluster.
- External nginx is configured to proxy domains to the Kubernetes NodePort services.
- DNS records exist for the public hosts and point to the external nginx endpoint:
  - `1api.click`
  - `api.1api.click`
  - `new.api.1api.click`
  - `router.1api.click`
- NFS export server `172.19.81.149` is reachable from every Kubernetes node.
- NFS export directories exist and have permissions suitable for container writes:
  - `/opt/lib/k8s/data/oneapi/postgres`
  - `/opt/lib/k8s/data/oneapi/new-api-data`
  - `/opt/lib/k8s/data/oneapi/new-api-logs`
  - `/opt/lib/k8s/data/oneapi/9router-data`
- Container images for portal backend/frontend are available to the cluster.
- Server/firewall allows public HTTP/HTTPS traffic to the ingress controller endpoint.

## 1. Build and publish portal images

`new-api` uses public image `vietapi/new-api:latest`.

Portal images must be built from this repo and pushed to a registry reachable by the server cluster.
Portal images use `registry.inviv.vn/oneapi` by default.

Current portal deployment tag (admin logs error-message + full-message fix):

```txt
registry.inviv.vn/oneapi/potal-backend:20260704-174812-logerr-fullmsg-amd64
registry.inviv.vn/oneapi/potal-frontend:20260704-174812-logerr-fullmsg-amd64
```

The local build machine is arm64, so production images must be built for `linux/amd64` via `docker buildx` and pushed directly:

```bash
cd /Users/thanhtq/Documents/project/1gpt/src
TAG="$(date +%Y%m%d-%H%M%S)-amd64"
for svc in backend frontend; do
  docker buildx build --platform linux/amd64 \
    -t registry.inviv.vn/oneapi/potal-$svc:$TAG --push ./potal/$svc
done
# then set newTag for potal-backend and potal-frontend in k8s/kustomization.yaml
cd deploy && kubectl apply -k k8s
kubectl -n oneapi rollout status deploy/potal-backend
kubectl -n oneapi rollout status deploy/potal-frontend
```

Generic build/push commands:
```bash
cd /Users/thanhtq/Documents/project/1gpt/src

docker build -t registry.inviv.vn/oneapi/potal-backend:latest ./potal/backend
docker build -t registry.inviv.vn/oneapi/potal-frontend:latest ./potal/frontend

docker push registry.inviv.vn/oneapi/potal-backend:latest
docker push registry.inviv.vn/oneapi/potal-frontend:latest
```

Then edit `k8s/kustomization.yaml` or patch during deploy:

```bash
cd deploy/k8s
kubectl kustomize . >/tmp/oneapi-rendered.yaml
```

## 2. Create real secret file

Do not commit real secrets.

```bash
cd /Users/thanhtq/Documents/project/1gpt/src/deploy
cp k8s/01-secret.example.yaml k8s/01-secret.yaml
chmod 600 k8s/01-secret.yaml
$EDITOR k8s/01-secret.yaml
```

Required keys:

- `NEW_API_POSTGRES_USER`
- `NEW_API_POSTGRES_PASSWORD`
- `NEW_API_POSTGRES_DB`
- `SESSION_SECRET`
- `CRYPTO_SECRET`

Generate strong random values for `SESSION_SECRET` and `CRYPTO_SECRET`, for example:

```bash
openssl rand -hex 32
```

## 3. Deploy

The manifests create static NFS-backed PVs, following the existing cluster pattern used by Jira:

```txt
oneapi-postgres-pv      -> 172.19.81.149:/opt/lib/k8s/data/oneapi/postgres      -> PVC postgres-data
oneapi-new-api-data-pv  -> 172.19.81.149:/opt/lib/k8s/data/oneapi/new-api-data -> PVC new-api-data
oneapi-new-api-logs-pv  -> 172.19.81.149:/opt/lib/k8s/data/oneapi/new-api-logs -> PVC new-api-logs
```

All three PVs use:

```txt
accessModes: ReadWriteMany
persistentVolumeReclaimPolicy: Retain
```

```bash
cd /Users/thanhtq/Documents/project/1gpt/src/deploy
./deploy.sh
```

Equivalent manual command:

```bash
kubectl apply -k k8s
kubectl -n oneapi get pods,svc
```

## 4. Verify

```bash
kubectl -n oneapi rollout status deploy/new-api-postgres
kubectl -n oneapi rollout status deploy/new-api
kubectl -n oneapi rollout status deploy/potal-backend
kubectl -n oneapi rollout status deploy/potal-frontend
kubectl -n oneapi rollout status deploy/9router

curl -i https://1api.click/
curl -i https://1api.click/admin
curl -i https://1api.click/api/health
curl -i https://api.1api.click/api/health
curl -i https://new.api.1api.click/v1/models
curl -i https://router.1api.click/api/health
```

After signing in as an admin at `/admin`, open `Channels` and run the VietAPI upstream quota check for a channel. A successful check returns sanitized fields such as `total_available`, `total_used`, `daily_cap`, and `expire_time`; the UI displays the same upstream quota units returned by VietAPI. This check is separate from portal user billing, which remains token/quota based.

## 5. External nginx routing

Workload services are exposed as NodePorts for the external nginx:

```txt
new-api:             NodePort 30081 -> container port 3000
potal-backend:       NodePort 30082 -> container port 8081
potal-frontend:      NodePort 30083 -> container port 80
new-api-user-portal: NodePort 30085 -> container port 3010 (optional companion admin)
nine-router:         NodePort 30086 -> container port 20128
```

Public host mapping:

- `1api.click` routes to `potal-frontend` NodePort `30083`.
- `api.1api.click` routes to `potal-backend` NodePort `30082`.
- `new.api.1api.click` routes to `new-api` NodePort `30081`.
- `admin.1api.click`, if used, routes to optional `new-api-user-portal` NodePort `30085`. Prefer `https://1api.click/admin` for the integrated portal admin.
- `router.1api.click` routes directly to `nine-router` NodePort `30086`.

Configure TLS certificates on the external nginx for each public hostname. For SSE/LLM streaming, disable proxy buffering and set read/send timeouts to at least 180 seconds. The Kubernetes Ingress manifest applies the same 180-second streaming timeout to the `new.api.1api.click` path:

```nginx
proxy_http_version 1.1;
proxy_buffering off;
proxy_request_buffering off;
proxy_read_timeout 180s;
proxy_send_timeout 180s;
add_header X-Accel-Buffering no always;
```

The production request path is:

```txt
client -> external nginx -> Kubernetes NodePort/Ingress -> New API
New API -> router.1api.click -> external nginx -> NodePort 30086 -> 9router -> provider
```

A successful streaming verification must return SSE chunks followed by `data: [DONE]`. New API logs should record `is_stream: true` and `stream_status.status: ok`; a failure at exactly 60 seconds with `client_gone` or `context canceled` indicates an unconfigured proxy timeout on the request path.

## Local Compose: 9router

Create local secrets before starting the Compose-managed 9router instance:

```bash
cd src/deploy
cp .env.example .env
chmod 600 .env
# Replace every placeholder with an independent strong value.
docker compose config
docker compose up -d 9router
curl -fsS http://localhost:20129/api/health
```

The 9router dashboard and OpenAI-compatible API are available on the host at `http://localhost:20129` and `http://localhost:20129/v1`. Containers on `oneapi-net` must use `http://oneapi-9router:20128/v1`; port `20129` is only the host mapping.

For a VietAPI model exposed by 9router as `vietapi/gpt-5.5`, configure a New API OpenAI channel with:

- Base URL: `http://oneapi-9router:20128/v1`
- Key: an API key generated by 9router, not the underlying VietAPI key
- Model: `vietapi/gpt-5.5`
- Group: `default`
- Status: enabled

Verify the upstream before testing through New API:

```bash
curl -fsS http://localhost:20129/v1/models \
  -H "Authorization: Bearer $NINE_ROUTER_CLIENT_API_KEY"

curl -fsS http://localhost:20129/v1/chat/completions \
  -H "Authorization: Bearer $NINE_ROUTER_CLIENT_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"vietapi/gpt-5.5","messages":[{"role":"user","content":"ping"}],"stream":false}'
```

If New API reports connection refused, confirm the channel uses container port `20128`, not host port `20129`. If 9router reports no active credentials, activate the provider credential in the 9router dashboard. Do not put provider keys or 9router client keys in this README, committed SQL, or Compose literals.

Rollback is non-destructive: disable the 9router channel in New API, then run `docker compose stop 9router`. Do not remove `oneapi-9router-data` unless the provider/account configuration is intentionally being discarded.

## Notes

- `.env` and `k8s/01-secret.yaml` are ignored; `.env.example` contains placeholders only.
- PostgreSQL, New API data, and logs use static NFS PV/PVC. PV reclaim policy is `Retain`; deleting PVCs will not automatically delete the NFS directory, but can detach the claim from the workload.
- Portal frontend nginx proxies `/api/` to `http://potal-backend:8081/api/`, matching Kubernetes service DNS.
- Public access is domain-based through the external nginx and Kubernetes NodePort services.
