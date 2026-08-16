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
| `config.data` | Shared config map data | `{}` |
| `secret.enabled` | Create a shared secret | `false` |
| `secret.stringData` | Secret values (base64-encoded in `secret.data` when pre-encoded) | `{}` |
| `ingress.enabled` | Create an Ingress | `false` |
| `ingress.hosts` | Ingress host/path rules | see `values.yaml` |
| `podDisruptionBudget.enabled` | Create PodDisruptionBudgets | `false` |
| `networkPolicy.enabled` | Create NetworkPolicies (default-deny ingress+egress) | `false` |
| `networkPolicy.extraEgressRules` | Extra egress rules for outbound traffic | `[]` |
| `serviceAccount.name` | Global ServiceAccount name override | `""` |

Full parameter reference is in `chart/values.yaml`.

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

The `networkPolicy.extraIngressRules` parameter allows you to restrict ingress to each
workload. Combined with the shared labels, you can allow the dashboard namespace to reach
the gateway only.

NetworkPolicies are **default-deny** for both ingress and egress when
`networkPolicy.enabled=true`. The default egress rule allows:

- DNS lookups (port 53 TCP/UDP) to any namespace,
- all traffic within the release namespace (so the dashboard can reach the gateway and
  vice-versa).

Any other outbound traffic (for example the gateway calling an external API) must be added
via `networkPolicy.extraEgressRules`, e.g.:

```bash
helm install hermes ./chart \
  --set networkPolicy.enabled=true \
  --set 'networkPolicy.extraEgressRules[0].to[0].ipBlock.cidr=0.0.0.0/0'
```

## Verifying the release

```bash
helm test hermes
```

## Development

```bash
helm lint ./chart
helm template hermes ./chart
kubectl apply --dry-run=client --validate=true -f <(helm template hermes ./chart)
```
