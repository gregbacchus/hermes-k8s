# hermes-k8s

Helm chart for running the **Hermes gateway** and **Hermes dashboard** on Kubernetes.

## Contents

- `chart/` — the `hermes` Helm chart (application chart, Helm v3).

## Prerequisites

- Kubernetes 1.25+
- Helm v3.x

## Installing

```bash
helm repo add hermes https://example.com/chart-repo  # or point at this chart path
helm install hermes ./chart
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
| `networkPolicy.enabled` | Create NetworkPolicies | `false` |

Full parameter reference is in `chart/values.yaml`.

### Deploying with a custom gateway tag and 3 replicas

```bash
helm install hermes ./chart \
  --set gateway.image.tag=1.2.3 \
  --set gateway.replicaCount=3 \
  --set dashboard.image.tag=1.2.3
```

### Enabling ingress

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
