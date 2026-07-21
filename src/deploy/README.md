# 1API Kubernetes Deployment

This folder deploys the local stack to Kubernetes. Public traffic is handled by an external nginx that proxies to NodePort services.

It is intentionally sibling to:

- `../new-api`
- `../potal`
- `../deploy`

## Components

- PostgreSQL 16: internal `ClusterIP` service `new-api-postgres:5432`, static NFS PV/PVC `oneapi-postgres-pv` / `postgres-data`.
- New API: service `new-api:3000`, exposed by NodePort `30081` and public host `new.api.1api.click`.
- Portal backend: service `potal-backend:8081`, exposed by NodePort `30084` and public host `api.1api.click`.
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

## Production deployment model

Production deployment is currently manual; this repository does not define a CI/CD pipeline. The operator builds and pushes immutable images, updates the image tags in `k8s/kustomization.yaml`, renders the manifests for review, applies the Kustomize directory, waits for rollout, and verifies the public endpoints.

Portal request path:

```txt
browser -> external nginx/TLS -> Kubernetes NodePort 30083 -> potal-frontend service -> nginx container
browser -> https://1api.click/api/* -> frontend nginx -> potal-backend:8081
```

The repository also contains `k8s/07-ingress.yaml`, which maps the public hosts to their services when an nginx Ingress controller is used. The documented production topology uses external nginx and NodePorts. Confirm which entry path is active on the target environment before changing routing; do not assume traffic traverses both.

## 1. Build and publish portal images

`new-api` and `9router` use the image references pinned in their manifests. Portal backend and frontend images are built from this repository and pushed to `registry.inviv.vn/oneapi`.

The local build machine may be arm64 while the production nodes are amd64. Build production images with `docker buildx --platform linux/amd64`. Use immutable, descriptive tags; do not rely on `latest` for a production release.

### Build both portal images

```bash
cd /Users/thanhtq/Documents/project/1gpt/src
TAG="$(date +%Y%m%d-%H%M%S)-portal-amd64"

for svc in backend frontend; do
  docker buildx build --platform linux/amd64 \
    -t registry.inviv.vn/oneapi/potal-$svc:$TAG \
    --push ./potal/$svc
done
```

Update the corresponding `newTag` entries in `deploy/k8s/kustomization.yaml`. The values in that file are the deployment source of truth; README examples intentionally do not duplicate a "current" tag because it becomes stale.

### Build only the frontend

For frontend, Vue, CSS, static asset, or frontend nginx changes, build and release only `potal-frontend`:

```bash
cd /Users/thanhtq/Documents/project/1gpt/src
TAG="$(date +%Y%m%d-%H%M%S)-frontend-amd64"

docker buildx build --platform linux/amd64 \
  -t registry.inviv.vn/oneapi/potal-frontend:$TAG \
  --push ./potal/frontend
```

Then update only the frontend `newTag` in `deploy/k8s/kustomization.yaml`. Before applying, review all other local tag and manifest changes because `kubectl apply -k k8s` applies the complete stack, not only the frontend.

### Render and review the release

```bash
cd /Users/thanhtq/Documents/project/1gpt/src/deploy
kubectl kustomize k8s >/tmp/oneapi-rendered.yaml
grep 'image:' /tmp/oneapi-rendered.yaml
kubectl diff -k k8s
```

Confirm that:

- `potal-backend` and `potal-frontend` resolve to the intended immutable tags.
- No unrelated Deployment, Service, Ingress, Secret, PV, or PVC change will be applied.
- `new-api-user-portal` is an optional companion Deployment with its own image reference in `k8s/09-new-api-user-portal.yaml`; changing the frontend Kustomize tag does not currently update that pinned reference.
- No secret values appear in the rendered file or shell history. Delete `/tmp/oneapi-rendered.yaml` after review if it contains sensitive rendered configuration.

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
- `NINE_ROUTER_JWT_SECRET`
- `NINE_ROUTER_API_KEY_SECRET`
- `NINE_ROUTER_MACHINE_ID_SALT`
- `NINE_ROUTER_INITIAL_PASSWORD`

Optional 9router flags are also read from the Secret when present: `NINE_ROUTER_REQUIRE_API_KEY`, `NINE_ROUTER_ENABLE_REQUEST_LOGS`, and `NINE_ROUTER_OBSERVABILITY_ENABLED`.

Generate strong random values for `SESSION_SECRET` and `CRYPTO_SECRET`, for example:

```bash
openssl rand -hex 32
```

## 3. Deploy

The manifests create static NFS-backed PVs with `ReadWriteMany` and `persistentVolumeReclaimPolicy: Retain`:

```txt
oneapi-postgres-pv      -> 172.19.81.149:/opt/lib/k8s/data/oneapi/postgres
oneapi-new-api-data-pv  -> 172.19.81.149:/opt/lib/k8s/data/oneapi/new-api-data
oneapi-new-api-logs-pv  -> 172.19.81.149:/opt/lib/k8s/data/oneapi/new-api-logs
oneapi-9router-data-pv  -> 172.19.81.149:/opt/lib/k8s/data/oneapi/9router-data
```

### Full-stack apply

```bash
cd /Users/thanhtq/Documents/project/1gpt/src/deploy
./deploy.sh
```

`deploy.sh` runs `kubectl apply -k k8s`, then waits for PostgreSQL, New API, portal backend, portal frontend, the optional companion portal, and 9router. It does not build or push images and does not execute the standalone `migration-*.sql` files.

Equivalent apply command:

```bash
kubectl apply -k k8s
kubectl -n oneapi get pods,svc
```

### Frontend-only rollout

Kustomize still applies the whole directory, but only the frontend Deployment should roll when the frontend image tag is the only effective manifest change:

```bash
cd /Users/thanhtq/Documents/project/1gpt/src/deploy
kubectl apply -k k8s
kubectl -n oneapi rollout status deploy/potal-frontend --timeout=180s
kubectl -n oneapi get deploy potal-frontend \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Do not use `kubectl rollout restart` as a substitute for updating an immutable tag. Keeping the desired tag in Kustomize makes the deployed state reproducible and rollback explicit.

## 4. Verify

### Kubernetes state

```bash
kubectl -n oneapi rollout status deploy/new-api-postgres --timeout=180s
kubectl -n oneapi rollout status deploy/new-api --timeout=300s
kubectl -n oneapi rollout status deploy/potal-backend --timeout=300s
kubectl -n oneapi rollout status deploy/potal-frontend --timeout=180s
kubectl -n oneapi rollout status deploy/new-api-user-portal --timeout=180s
kubectl -n oneapi rollout status deploy/9router --timeout=300s
kubectl -n oneapi get pods,svc
```

Check the images actually running rather than relying only on the local manifest:

```bash
kubectl -n oneapi get deploy potal-backend potal-frontend \
  -o custom-columns='NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image,READY:.status.readyReplicas'
```

### Public endpoints

```bash
curl -fsSI https://1api.click/
curl -fsSI https://1api.click/admin
curl -fsS https://1api.click/api/health
curl -fsS https://api.1api.click/api/health
curl -fsS https://new.api.1api.click/api/status
curl -fsS https://router.1api.click/api/health
```

After signing in as an admin at `https://1api.click/admin`, verify the changed admin flow manually. For model or channel changes, run the relevant upstream check and confirm the response contains only expected sanitized fields.

### Frontend asset and cache verification

Vite emits content-hashed files under `/assets/`. The frontend nginx must cache those immutable assets, avoid caching `index.html`, and return `404` for a missing asset instead of falling back to HTML. Returning `index.html` for an old JavaScript filename causes the browser error “Expected a JavaScript-or-Wasm module script” because the response MIME type is `text/html`.

```bash
HTML_HEADERS="$(mktemp)"
HTML_BODY="$(mktemp)"
curl -fsS -D "$HTML_HEADERS" -o "$HTML_BODY" https://1api.click/
cat "$HTML_HEADERS"

ASSET="$(grep -oE '/assets/[^" ]+\.js' "$HTML_BODY" | head -n1)"
test -n "$ASSET"
curl -fsSI "https://1api.click$ASSET"
curl -sS -o /dev/null -w '%{http_code} %{content_type}\n' \
  https://1api.click/assets/definitely-missing.js
rm -f "$HTML_HEADERS" "$HTML_BODY"
```

Expected results:

- HTML returns `Cache-Control: no-store, no-cache, must-revalidate`.
- The current JavaScript asset returns `200`, a JavaScript MIME type, and `Cache-Control: public, max-age=31536000, immutable`.
- The deliberately missing asset returns `404`; it must not return `200 text/html`.
- A hard refresh and direct navigation to `/user/*` and `/admin/*` still load the SPA through the `index.html` fallback.

If public results differ from an in-cluster request, inspect the external nginx or CDN for stale HTML caching, URI rewrites, or overridden response headers.

## Rollback

Prefer a declarative rollback:

1. Set the affected image `newTag` in `k8s/kustomization.yaml` back to the last known-good immutable tag.
2. Run `kubectl diff -k k8s` and confirm only the intended image changes.
3. Run `kubectl apply -k k8s`.
4. Wait for the affected Deployment rollout and repeat the public verification above.

For an emergency only, `kubectl -n oneapi rollout undo deployment/potal-frontend` can restore the previous ReplicaSet. Afterwards, update Kustomize to the restored tag so Git and cluster state do not drift.

Database migrations are not run by `deploy.sh`; each migration needs its own backup, execution, verification, and rollback procedure. Never delete PVCs or NFS data as an application rollback step.

## 5. External nginx routing

Workload services are exposed as NodePorts for the external nginx:

```txt
new-api:             NodePort 30081 -> container port 3000
potal-backend:       NodePort 30084 -> container port 8081
potal-frontend:      NodePort 30083 -> container port 80
new-api-user-portal: NodePort 30085 -> container port 3010 (optional companion admin)
nine-router:         NodePort 30086 -> container port 20128
```

Public host mapping:

- `1api.click` routes to `potal-frontend` NodePort `30083`.
- `api.1api.click` routes to `potal-backend` NodePort `30084`.
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
