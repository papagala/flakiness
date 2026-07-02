IMAGE       ?= oswaldodocker/flakiness
TAG         ?= v0.0.1
PLATFORMS   ?= linux/amd64,linux/arm64
CHART       ?= charts/flakiness
NAMESPACE   ?= flakiness
PERCENTAGE  ?= 20

# Use docker if present, else podman.
CONTAINER_TOOL ?= $(shell command -v docker 2>/dev/null || command -v podman 2>/dev/null)

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

.PHONY: run
run: ## Run the server locally (no container)
	python3 src/flaky_server.py --percentage-of-failures $(PERCENTAGE)

.PHONY: docker-build
docker-build: ## Build a single-arch image for local testing
	$(CONTAINER_TOOL) build -t $(IMAGE):$(TAG) .

.PHONY: docker-run
docker-run: ## Run the built image, e.g. make docker-run PERCENTAGE=50
	$(CONTAINER_TOOL) run --rm -p 8080:8080 $(IMAGE):$(TAG) --percentage-of-failures $(PERCENTAGE)

.PHONY: buildx-push
buildx-push: ## Build+push multi-arch with docker buildx
	docker buildx build --platform $(PLATFORMS) -t $(IMAGE):$(TAG) -t $(IMAGE):latest --push .

.PHONY: podman-push
podman-push: ## Build+push multi-arch with podman manifest
	-podman manifest rm $(IMAGE):$(TAG) 2>/dev/null
	podman build --platform $(PLATFORMS) --manifest $(IMAGE):$(TAG) .
	podman manifest push --all $(IMAGE):$(TAG) docker://docker.io/$(IMAGE):$(TAG)
	podman tag $(IMAGE):$(TAG) $(IMAGE):latest
	podman manifest push --all $(IMAGE):$(TAG) docker://docker.io/$(IMAGE):latest

.PHONY: helm-lint
helm-lint: ## Lint the chart
	helm lint $(CHART)

.PHONY: helm-template
helm-template: ## Render the chart with default values
	helm template flakiness $(CHART)

.PHONY: install-minimal
install-minimal: ## Install with the minimal values file
	helm upgrade --install flakiness $(CHART) -n $(NAMESPACE) --create-namespace -f $(CHART)/values-minimal.yaml

.PHONY: install-deployment
install-deployment: ## Install only the plain Deployment
	helm upgrade --install flakiness $(CHART) -n $(NAMESPACE) --create-namespace \
	  --set flakyDeployment.enabled=true --set flakyInferenceService.enabled=false --set flakyInferenceGraph.enabled=false

.PHONY: install-isvc
install-isvc: ## Install only the InferenceService
	helm upgrade --install flakiness $(CHART) -n $(NAMESPACE) --create-namespace \
	  --set flakyDeployment.enabled=false --set flakyInferenceService.enabled=true --set flakyInferenceGraph.enabled=false

.PHONY: install-graph
install-graph: ## Install only the InferenceGraph (+ backends)
	helm upgrade --install flakiness $(CHART) -n $(NAMESPACE) --create-namespace \
	  --set flakyDeployment.enabled=false --set flakyInferenceService.enabled=false --set flakyInferenceGraph.enabled=true

.PHONY: uninstall
uninstall: ## Uninstall the release
	helm uninstall flakiness -n $(NAMESPACE)
