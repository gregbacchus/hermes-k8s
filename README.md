# hermes-k8s

Helm chart for running the **Hermes gateway** and **Hermes dashboard** on Kubernetes.

## Contents

- `chart/` — the `hermes` Helm chart (application chart, Helm v3).

## Prerequisites

- Kubernetes 1.25+
- Helm v3.x

## Installing

This chart is not yet published to a chart repository. Install it directly from this
repository:

```bash
git clone https://github.com/gregbacchus/hermes-k8s
helm install hermes ./hermes-k8s/chart
```

For a custom namespace:

```bash
helm install hermes ./chart -n hermes --create-namespace
```

## Quick start

```bash
helm install hermes ./chart \
  --set gateway.image.tag=0.1.0 \
  --set dashboard.image.tag=0.1.0
```

## Configuration

The chart deploys two workloads:

- **Gateway** (`gateway.*`) — the Hermes API gateway (default port `8080`).
- **Dashboard** (`dashboard.*`) — the Hermes web dashboard (default port `3000`).

Both workloads share `serviceAccount`, `podAnnotations`, `podLabels`, `nodeSelector`,
`tolerations`, `affinity`, `imagePullSecrets`, and the shared `config`/`secret` material.

### ConfigMap and Secret

The chart creates a shared `ConfigMap` (when `config.enabled=true`, the default) and an
optional shared `Secret` (when `secret.enabled=true`). When created, they are wired into
**both** workloads as `envFrom` sources (`configMapRef`/`secretRef`), so every key in
`config.data` and `secret.stringData` becomes an environment variable in the gateway and
dashboard containers:

```bash
helm install hermes ./chart \
  --set 'config.data[APP_ENV]=production' \
  --set secret.enabled=true \
  --set 'secret.stringData[API_TOKEN]=change-me'
```

`gateway.envFrom` / `dashboard.envFrom` entries are appended after the shared refs, so
per-component sources can override the shared keys.

### Service accounts

- Each enabled component gets its own `ServiceAccount` (`{name}-gateway`, `{name}-dashboard`)
  unless a global `serviceAccount.name` is set.
- A non-empty global `serviceAccount.name` overrides both component names; in that case the
  chart creates exactly **one** `ServiceAccount` with that name, shared by both workloads.
- `gateway.serviceAccount.name` / `dashboard.serviceAccount.name` are used only when no global
  `serviceAccount.name` is set, and apply per component.
- `serviceAccount.create: false` (or a component-level `create: false`) disables creation; the
  referenced SA must then be created out of band.

### Security contexts

Pod-level and container-level `securityContext` are rendered from separate values, matching the
Kubernetes API:

- `podSecurityContext` — pod-level fields such as `runAsUser`, `runAsGroup`, `runAsNonRoot`,
  `fsGroup`, `seccompProfile`.
- `containerSecurityContext` — container-level fields such as `capabilities`, 
  `readOnlyRootFilesystem`, `allowPrivilegeEscalation`.

Defaults run as non-root (`runAsUser: 1000`) with a read-only root filesystem, all capabilities
dropped, and privilege escalation disabled.

### Key parameters

| Parameter | Description | Default |
| --- | --- | --- |
| `gateway.enabled` | Deploy the gateway workload | `true` |
| `gateway.replicaCount` | Gateway replicas | `1` |
| `gateway.image.repository` | Gateway image repository | `ghcr.io/geee-be/hermes-gateway` |
| `gateway.image.tag` | Gateway image tag | `0.1.0` |
| `gateway.service.type` | Gateway service type | `ClusterIP` |
| `gateway.service.port` | Gateway service port | `8080` |
| `gateway.resources` | Gateway resource requests/limits | see `values.yaml` |
| `gateway.autoscaling.enabled` | Enable HPA for the gateway | `false` |
| `dashboard.enabled` | Deploy the dashboard workload | `true` |
| `dashboard.replicaCount` | Dashboard replicas | `1` |
| `dashboard.image.repository` | Dashboard image repository | `ghcr.io/geee-be/hermes-dashboard` |
| `dashboard.image.tag` | Dashboard image tag | `0.1.0` |
| `dashboard.service.port` | Dashboard service port | `3000` |
| `config.enabled` | Create the shared ConfigMap and wire it into both workloads | `true` |
| `config.data` | Shared config map data (exposed as env vars via `envFrom`) | `{}` |
| `secret.enabled` | Create a shared Secret and wire it into both workloads | `false` |
| `secret.stringData` | Secret values (base64-encoded in `secret.data` when pre-encoded) | `{}` |
| `ingress.enabled` | Create an Ingress | `false` |
| `ingress.hosts` | Ingress host/path rules | see `values.yaml` |
| `podDisruptionBudget.enabled` | Create PodDisruptionBudgets | `false` |
| `networkPolicy.enabled` | Create NetworkPolicies (default-deny, same-namespace traffic allowed) | `false` |
| `networkPolicy.extraIngressRules` | Extra ingress rules (beyond the default same-namespace rule) | `[]` |
| `networkPolicy.extraEgressRules` | Extra egress rules for outbound traffic | `[]` |
| `serviceAccount.name` | Global ServiceAccount name override | `""` |

Full parameter reference is in `chart/values.yaml`.

> **Autoscaling**: an HPA is only created when `autoscaling.enabled=true` **and** at least
> one of `targetCPUUtilizationPercentage` / `targetMemoryUtilizationPercentage` is set.
> Enabling autoscaling with both targets unset silently creates no HPA.
>
> **PodDisruptionBudget**: the default `podDisruptionBudget.minAvailable: 1` with
> `replicaCount: 1` blocks voluntary evictions (node drains, cluster autoscaling). Only
> enable PDBs when you run multiple replicas, or set `minAvailable: 0`.
>
> **Default images**: `ghcr.io/geee-be/hermes-gateway:0.1.0` and
> `ghcr.io/geee-be/hermes-dashboard:0.1.0` are assumed to be published and pullable by the
> cluster; if the images are private or unpublished, set `gateway.image.repository` /
> `dashboard.image.repository` to your published registry.

### Deploying with a custom gateway tag and 3 replicas

```bash
helm install hermes ./chart \
  --set gateway.image.tag=1.2.3 \
  --set gateway.replicaCount=3 \
  --set dashboard.image.tag=1.2.3
```

### Enabling ingress

Use a values file to keep hosts, paths, and TLS together — this is the most
robust form and avoids Helm `--set` array-replacement pitfalls:

```bash
helm install hermes ./chart \
  --set ingress.enabled=true \
  -f ingress-values.yaml
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
          port: http
```

You can also enable ingress with a single `--set` flag; any host without an
explicit `paths` list defaults to `/{Prefix}` routed to the gateway:

```bash
helm install hermes ./chart \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set 'ingress.hosts[0].host=hermes.example.com'
```

### Sealing the gateway behind the dashboard

NetworkPolicies are **default-deny** for both ingress and egress when
`networkPolicy.enabled=true`. The default rules keep the two workloads able to talk to each
other while denying everything else:

- **Ingress** — each workload allows traffic from any pod in the same namespace
  (`podSelector: {}`), so the dashboard can reach the gateway and vice-versa. Ingress from
  other namespaces is denied unless added via `networkPolicy.extraIngressRules`.
- **Egress** — DNS lookups (port 53 TCP/UDP) to any namespace, plus all traffic within the
  release namespace (so the dashboard can reach the gateway and vice-versa).

To restrict ingress to the dashboard namespace only, add an explicit
`networkPolicy.extraIngressRules` rule; the default same-namespace rule always applies, so
the app keeps working.

Any other outbound traffic (for example the gateway calling an external API) must be added
via `networkPolicy.extraEgressRules`, e.g.:

```bash
helm install hermes ./chart \
  --set networkPolicy.enabled=true \
  --set 'networkPolicy.extraEgressRules[0].to[0].ipBlock.cidr=0.0.0.0/0'
```

## Verifying the release

`helm test` runs a smoke pod per workload that wgets the workload's health endpoint
(`livenessProbe.path`, default `/healthz`) as an unprivileged user and succeeds only on a
2xx response:

```bash
helm test hermes
```

## Development

```bash
helm lint ./chart
helm template hermes ./chart
kubectl apply --dry-run=client --validate=true -f <(helm template hermes ./chart)
```
