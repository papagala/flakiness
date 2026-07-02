# flakiness

A tiny, dependency-free HTTP server that **fails a configurable percentage of requests**, plus a
Helm chart to deploy it as a plain Kubernetes **Deployment**, a KServe **InferenceService**, or a
KServe **InferenceGraph** (with retry config) — so you can exercise gateway/mesh **retry** behaviour
(e.g. Envoy Gateway) end-to-end.

Image: [`oswaldodocker/flakiness`](https://hub.docker.com/r/oswaldodocker/flakiness)

## The image

```bash
docker run -p 8080:8080 oswaldodocker/flakiness:v0.0.1 --percentage-of-failures 20
```

- Every `POST` (to any path, incl. `/`, `/v1/models/<name>:predict`, `/v2/models/<name>/infer`)
  fails with the configured percentage; failures return `503` (configurable), successes return `200`.
- Health/readiness `GET`s always return `200`: `/`, `/healthz`, `/readyz`, `/livez`,
  `/v1/models/<name>`, `/v2/health/ready`, `/v2/models/<name>`.
- Each request logs a line (`[flaky] POST ... -> 503 (roll=12.3 < 20)`) so retries are visible in
  `kubectl logs` / `stern`, and responses carry an `X-Flaky-Result: fail|ok` header.

### Flags

| Flag | Env | Default | Meaning |
|------|-----|---------|---------|
| `--percentage-of-failures` | `PERCENTAGE_OF_FAILURES` | `20` | Percent of POSTs to fail (0–100) |
| `--port` | `PORT` | `8080` | Listen port |
| `--fail-status` | `FAIL_STATUS` | `503` | Status returned on failure |
| `--model-name` | `MODEL_NAME` | `flaky` | Name reported in responses |

Try it:

```bash
for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code}\n" -X POST localhost:8080 -d '{}'; done | sort | uniq -c
```

## The Helm chart

Install any subset of the three components. The minimal values file only needs the image and the
enable/disable flags:

```yaml
# values-minimal.yaml
image:
  repository: oswaldodocker/flakiness
  tag: v0.0.1
flakyDeployment:       { enabled: true }
flakyInferenceService: { enabled: false }
flakyInferenceGraph:   { enabled: false }
```

```bash
helm install flakiness charts/flakiness -n flakiness --create-namespace -f values-minimal.yaml
```

Or toggle from the command line:

```bash
make install-deployment   # plain Deployment + Service only
make install-isvc         # KServe InferenceService only
make install-graph        # KServe InferenceGraph (+ flaky & stable backends) only
```

### Components

| Values key | Kind | Notes |
|------------|------|-------|
| `flakyDeployment` | `apps/v1 Deployment` + `Service` | No KServe required |
| `flakyInferenceService` | `serving.kserve.io/v1beta1 InferenceService` | Custom predictor container |
| `flakyInferenceGraph` | `serving.kserve.io/v1alpha1 InferenceGraph` | Retry on a flaky step; creates flaky + stable backends |

Failure percentage resolves per component (`<component>.percentageOfFailures`) and falls back to the
global `percentageOfFailures`. The InferenceGraph's flaky backend defaults to 50% and carries retry
config (`maxRetries`, `initialDelayMs`, `maxDelayMs`) matching the KServe
`feat/inferencegraph-retry-e2e-tests` branch schema.

See [`charts/flakiness/values.yaml`](charts/flakiness/values.yaml) for all options.

## Development

```bash
make run                    # run the server locally
make docker-build           # build a local single-arch image
make helm-lint helm-template
make podman-push            # or: make buildx-push  (multi-arch to Docker Hub)
```

CI (`.github/workflows/docker-publish.yml`) builds & pushes a multi-arch image on any `v*` tag,
using `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` repo secrets.
