# hermes-k8s

Helm chart for running the [Hermes agent](https://github.com/NousResearch/hermes-agent)
gateway and dashboard on Kubernetes.

## Contents

- `chart/` — the `hermes` Helm chart (application chart, Helm v3).

## Prerequisites

- Kubernetes 1.25+
- Helm v3.x

## Hermes runtime contract (verified)

The chart is built against the official `nousresearch/hermes-agent` image, whose runtime
contract was verified against the published docs and empirically (Docker smoke, see
`Verifying the release`):

| Aspect | Value |
| --- | --- |
| Image | `nousresearch/hermes-agent` (pin `image.tag` for production) |
| Gateway API server | port `8642` (OpenAI-compatible API + `GET /health`) |
| Dashboard | port `9119`, enabled with `HERMES_DASHBOARD=1` |
| State directory | `/opt/data` (host `~/.hermes`); `HERMES_HOME` points here |
| State files | `config.yaml`, `.env`, `SOUL.md`, `state.db` (SQLite, WAL), `sessions/`, `memories/`, `skills/`, `cron/`, `logs/` |
| Runtime user | `hermes` uid/gid `10000` (s6-overlay drops from root) |
| Init | s6-overlay starts as root to chown/seed `/opt/data`, then drops to uid 10000 |
| Install tree | `/opt/hermes` immutable, root-owned |
| Minimum resources | 1 GB RAM / 1 core (2 GB with browser tools) |

Two consequences drive the chart design:

1. **Hermes is stateful** — it self-manages `config.yaml`, `.env`, `state.db`, sessions,
   memory, and skills on disk. Two gateway containers must never share one data directory
   (session files and memory stores are not concurrency-safe). The chart therefore runs a
   single gateway replica with a `ReadWriteOnce` PVC and a `Recreate` rollout.
2. **The dashboard runs in the gateway's container** — the official image supervises the
   dashboard (and per-profile gateways) with s6-overlay *inside the same container*. A
   standalone dashboard container needs a shared PID/network namespace for gateway-liveness
   detection, so the chart models the dashboard as a flag on the single gateway pod
   (`gateway.dashboard.enabled` → `HERMES_DASHBOARD=1`), not a separate Deployment.

## Installing

```bash
git clone https://github.com/gregbacchus/hermes-k8s
helm install hermes ./hermes-k8s/chart \
  --set secret.enabled=true \
  --set 'secret.stringData.API_SERVER_KEY=change-me-min-16-chars'
```

> The gateway API server requires an `API_SERVER_KEY` of at least 16 characters.
> Installing with no key (or a shorter key) leaves no listener on port 8642 and the
> pod crash-loops on its liveness probe — see [Gateway API server](#gateway-api-server).

For a custom namespace:

```bash
helm install hermes ./chart -n hermes --create-namespace
```

## Configuration

The chart deploys one workload — the Hermes **gateway** — with the **dashboard** available
as an in-pod, s6-supervised service. `gateway.*` configures the agent; `gateway.dashboard.*`
configures the dashboard; `config.*`/`secret.*` supply environment variables to the agent.

### Supplying API keys and configuration

Hermes reads API keys and configuration from environment variables (which override the
`.env` file on disk), so the shared `Secret` is the recommended way to configure the agent
without running the interactive setup wizard:

```bash
helm install hermes ./chart \
  --set secret.enabled=true \
  --set 'secret.stringData.ANTHROPIC_API_KEY=sk-ant-...' \
  --set 'secret.stringData.API_SERVER_KEY=change-me-min-16-chars'
```

The chart also creates a shared `ConfigMap` (`config.data`) wired into the gateway as
`envFrom`. `gateway.env` / `gateway.envFrom` entries are appended after the shared sources
so per-workload values can override shared keys.

### Gateway API server

The OpenAI-compatible API server is the primary Kubernetes interface. It is enabled by
default and requires a bearer key:

- `gateway.apiServer.enabled` — default `true` (`API_SERVER_ENABLED=true`).
- `gateway.apiServer.host` / `gateway.apiServer.port` — bind address/port (default
  `0.0.0.0` / `8642`).
- `gateway.apiServer.key` — plaintext `API_SERVER_KEY` (min 16 chars, image-enforced).
  The chart fails to render if a shorter key is supplied.
- `gateway.apiServer.keySecretRef` — reference an existing Secret instead (`{name, key}`).
  The Secret's value cannot be length-validated at render time, so it must itself be
  16+ chars.
- `gateway.apiServer.corsOrigins` — optional browser allowlist.

> The API server binds only when `API_SERVER_KEY` is a valid (16+ char) key. With no
> key — or a key the image rejects — nothing listens on 8642, `/health` is
> connection-refused, and the pod fails its liveness probe (crash-loop) even though the
> gateway process itself keeps running. With a valid key, `/health` returns HTTP 200 on a
> fresh, unconfigured install and the pod becomes Ready immediately.

### Dashboard

The dashboard is a supervised s6 service in the gateway's container. Enable it and (on a
non-loopback bind) configure an auth provider — Hermes fails closed on a public bind with no
auth:

```bash
helm install hermes ./chart \
  --set gateway.dashboard.enabled=true \
  --set 'gateway.dashboard.auth.basicAuth.username=admin' \
  --set 'gateway.dashboard.auth.basicAuth.password=change-me'
```

- `gateway.dashboard.host` / `gateway.dashboard.port` — bind address/port (default
  `0.0.0.0` / `9119`).
- `gateway.dashboard.auth.basicAuth.*` — bundled username/password provider
  (`HERMES_DASHBOARD_BASIC_AUTH_*`). For public exposure prefer OAuth/OIDC (see the
  Hermes dashboard docs) or bind `127.0.0.1` and tunnel.

### Persistence (Hermes self-managed state)

The chart mounts a `PersistentVolumeClaim` at `gateway.persistence.mountPath` (default
`/opt/data`) and sets `HERMES_HOME` to that path:

- `gateway.persistence.enabled` — default `true`.
- `gateway.persistence.existingClaim` — reuse a pre-provisioned PVC.
- `gateway.persistence.storageClass`, `size`, `accessMode` — default `ReadWriteOnce` +
  `2Gi` (upstream recommends 500 MB–2 GB+).

When persistence is disabled the chart mounts an ephemeral `emptyDir` at
`gateway.persistence.mountPath` so Hermes still has a writable state directory under the
read-only root filesystem (the image's own `VOLUME /opt/data` is Docker-only — kubelet
does not mount image-declared volumes). State is then lost on pod restart; use this only
for stateless evaluation.

A `ReadWriteOnce` volume attaches to one pod, so with persistence enabled the chart runs a
single replica with a `Recreate` strategy and refuses to render if you scale past one
replica or enable autoscaling above `maxReplicas: 1`.

> **Warning**: never run two Hermes gateways against the same data directory — session
> files and memory stores are not designed for concurrent access.

### Security contexts

The image must start as **root** so s6-overlay can chown the data volume and seed first-boot
config, after which it drops every supervised service to the `hermes` user (uid/gid 10000).
The chart therefore does **not** set `runAsUser`/`runAsNonRoot` (the image refuses arbitrary
non-root bootstrap); it sets `fsGroup: 10000` so the PVC is group-writable even if the
image's internal chown is bypassed, and `seccompProfile: RuntimeDefault`.

The container runs with `allowPrivilegeEscalation: false` (no-new-privileges) and a
read-only root filesystem. Capabilities are dropped to a minimal set: the chart drops `ALL`
and adds back only the four the s6-overlay bootstrap needs — `CHOWN` (chown `/opt/data`),
`DAC_OVERRIDE` (seed first-boot files), and `SETUID`/`SETGID` (drop to the `hermes` user).
Dropping `ALL` outright breaks the s6 bootstrap (`s6-applyuidgid: ... Operation not
permitted`, container exits 111), which is why the four bootstrap capabilities are retained.
`readOnlyRootFilesystem: true` requires two writable scratch volumes, which the chart mounts
automatically:

- `/run` — s6-overlay's runtime state (a **disk-backed** emptyDir; a `medium: Memory`
  tmpfs is mounted `noexec` and breaks s6-overlay).
- `/tmp` — the runtime's scratch space.

### Service accounts

The gateway gets a `ServiceAccount` (`{name}-gateway`) unless `serviceAccount.name` is set
globally or `gateway.serviceAccount.name` is set per component. Set
`serviceAccount.create: false` (or `gateway.serviceAccount.create: false`) to reference an
out-of-band account.

### Key parameters

| Parameter | Description | Default |
| --- | --- | --- |
| `image.repository` | Hermes image | `nousresearch/hermes-agent` |
| `image.tag` | Hermes image tag (pin for production) | `latest` |
| `gateway.enabled` | Deploy the gateway workload | `true` |
| `gateway.replicaCount` | Gateway replicas (keep `1` with persistence) | `1` |
| `gateway.command` | Container command | `["gateway", "run"]` |
| `gateway.apiServer.enabled` | Enable the OpenAI-compatible API server | `true` |
| `gateway.apiServer.host` / `port` | API server bind address / port | `0.0.0.0` / `8642` |
| `gateway.apiServer.key` | API server bearer key | `""` |
| `gateway.service.type` / `port` | Gateway service type / port | `ClusterIP` / `8642` |
| `gateway.resources` | Gateway requests/limits | `1Gi`/`1` cpu … `4Gi`/`2` cpu |
| `gateway.dashboard.enabled` | Enable the in-pod dashboard | `false` |
| `gateway.dashboard.port` | Dashboard port | `9119` |
| `gateway.dashboard.auth.basicAuth.*` | Dashboard basic-auth provider | empty |
| `gateway.persistence.enabled` | Create/mount a PVC (sets `HERMES_HOME`) | `true` |
| `gateway.persistence.mountPath` | State mount path / `HERMES_HOME` | `/opt/data` |
| `gateway.persistence.size` | PVC size | `2Gi` |
| `gateway.autoscaling.enabled` | Create an HPA (keep `maxReplicas: 1` with persistence) | `false` |
| `config.enabled` | Create the shared ConfigMap (`envFrom`) | `true` |
| `secret.enabled` | Create the shared Secret (`envFrom`) | `false` |
| `ingress.enabled` | Create an Ingress | `false` |
| `podDisruptionBudget.enabled` | Create a PDB | `false` |
| `networkPolicy.enabled` | Create default-deny NetworkPolicies | `false` |

Full parameter reference is in `chart/values.yaml`.

> **Autoscaling**: an HPA is only created when `autoscaling.enabled=true` **and** at least
> one CPU/memory target is set. With persistence (RWO) the chart caps `maxReplicas: 1`.
>
> **PodDisruptionBudget**: `minAvailable: 1` with `replicaCount: 1` blocks voluntary
> evictions; only enable PDBs with multiple replicas or set `minAvailable: 0`.

### Enabling ingress

```bash
helm install hermes ./chart --set ingress.enabled=true -f ingress-values.yaml
```

```yaml
# ingress-values.yaml
ingress:
  className: nginx
  hosts:
    - host: hermes.example.com
      paths:
        - path: /
          pathType: Prefix
          service: gateway
          port: api
        - path: /dashboard
          pathType: Prefix
          service: dashboard
          port: dashboard
```

Each `paths[].port` may be a Service **port name** (`api`, `dashboard`) or a **port
number** (`8642`, `9119`); the chart renders `port.name` or `port.number` accordingly.

### NetworkPolicy

`networkPolicy.enabled=true` applies default-deny with DNS egress (port 53) and
same-namespace traffic allowed; extend with `networkPolicy.extraIngressRules` /
`extraEgressRules` (e.g. the gateway calling an external model API).

## Verifying the release

`helm test` runs a smoke pod that requests the gateway API server's health endpoint
(`GET /health` on the gateway service) as an unprivileged user and succeeds on a 2xx
response. This requires a configured gateway (API key set):

```bash
helm test hermes
```

The state-write and API-server contracts are asserted in CI: the workflow runs the real
`nousresearch/hermes-agent` image against an empty volume **under the chart's own
securityContext** (capabilities dropped to the bootstrap set, read-only rootfs, disk-backed
`/run` and `/tmp`, no-new-privileges) and verifies it boots, writes `config.yaml` and
`state.db` (SQLite) owned by uid 10000, **and that `GET /health` returns HTTP 200 with a
16-char `API_SERVER_KEY`**. To reproduce locally:

```bash
mkdir -p /tmp/hermes-smoke/{data,run,tmp}
docker run -d --rm --name hermes-smoke \
  -v /tmp/hermes-smoke/data:/opt/data \
  -v /tmp/hermes-smoke/run:/run \
  -v /tmp/hermes-smoke/tmp:/tmp \
  -e API_SERVER_ENABLED=true -e API_SERVER_HOST=0.0.0.0 -e API_SERVER_KEY=testkey1234567890 \
  --cap-drop=ALL --cap-add=CHOWN --cap-add=DAC_OVERRIDE --cap-add=SETGID --cap-add=SETUID \
  --read-only --security-opt no-new-privileges \
  nousresearch/hermes-agent:latest gateway run
sleep 15
docker exec hermes-smoke sh -c 'test -f /opt/data/state.db && test -f /opt/data/config.yaml \
  && [ "$(stat -c %u /opt/data/state.db)" = 10000 ] && echo "state write OK"'
docker exec hermes-smoke curl -sf http://127.0.0.1:8642/health && echo " <- /health OK"
```

## Development

```bash
helm lint ./chart
helm template hermes ./chart
kubectl apply --dry-run=client --validate=true -f <(helm template hermes ./chart)
kubeconform -strict <(helm template hermes ./chart)
```
