# GPU observability with Inspektor Gadget

This repository installs Inspektor Gadget `0.55.0` on NVIDIA GPU nodes and
configures:

- the `gpu-ebpf-bridge` sidecar;
- Prometheus metrics from `gpu_top`, `gpu_top_per_pid`, and
  `top_cuda_memory`;
- CUDA memory profiles from `profile_cuda` exported to Pyroscope;
- an Azure Monitor `PodMonitor` that scrapes each Gadget pod on port `2224`.

## Prerequisites

- Kubernetes access through the current `kubectl` context;
- Helm 3;
- NVIDIA drivers, the NVIDIA device plugin, and NVIDIA Container Toolkit;
- AKS GPU nodes labeled `kubernetes.azure.com/accelerator=nvidia`;
- the Azure Monitor `PodMonitor` CRD (`azmonitoring.coreos.com/v1`);
- a Pyroscope OTLP-gRPC service reachable as `pyroscope:4040` from the
  `gadget` namespace.

The GPU bridge uses `hostpath`, which supports AKS GPU node pools without
reserving a GPU for the telemetry sidecar. If the cluster uses the NVIDIA GPU
Operator and runtime hook, `bridges.gpu.accessMode` can instead be set to
`toolkit-env`.

## Install or upgrade

```bash
./scripts/install.sh
```

The script performs the equivalent of:

```bash
helm upgrade --install gadget \
  oci://ghcr.io/inspektor-gadget/inspektor-gadget/charts/gadget \
  --namespace gadget \
  --create-namespace \
  --version 0.55.0 \
  --values values.yaml \
  --wait \
  --timeout 10m

kubectl apply --filename manifests/podmonitor.yaml
```

`CHART_VERSION`, `VALUES_FILE`, and `PODMONITOR_FILE` can override the defaults.
The release and namespace remain fixed as `gadget` to match the monitoring
resource.

## Data collection

The Helm values start four Gadget Instances:

| Instance | Output |
| --- | --- |
| `gpu-top` | Device-level GPU utilization, memory, and related gauges |
| `gpu-top-per-pid` | Per-process GPU memory and utilization gauges with Kubernetes context |
| `gpu-memory-metrics` | CUDA runtime and driver memory metrics with Kubernetes context |
| `gpu-memory-profiles` | OpenTelemetry CUDA allocation profiles sent to `pyroscope:4040` |

The GPU Gadget Instances add `metrics.collect=true` at runtime and assign unique
OpenTelemetry metric scopes. The daemon exposes Prometheus metrics at
`http://<pod-ip>:2224/metrics`. `gpu-memory-profiles` exports CUDA allocation
profiles through `pyroscope-exporter`, collects user and OpenTelemetry stacks,
and uses the `otel-ebpf-profiler` symbolizer. Pod and namespace enrichment
fields are exported as metric keys or profile sample attributes. All
workload-enriched instances enable `operator.KubeManager.all-namespaces` so
Kubernetes enrichment covers workloads outside the `gadget` namespace.

## Verify

```bash
helm status gadget --namespace gadget
kubectl get pods --namespace gadget --selector k8s-app=gadget -o wide
kubectl get configmaps --namespace gadget --selector type=gadget-instance
kubectl get podmonitor --namespace gadget inspektor-gadget
```

Confirm the Gadget pod contains both containers:

```bash
kubectl get pods --namespace gadget --selector k8s-app=gadget \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'
```

Inspect metrics from one pod:

```bash
pod="$(kubectl get pods --namespace gadget --selector k8s-app=gadget \
  -o jsonpath='{.items[0].metadata.name}')"
kubectl port-forward --namespace gadget "pod/${pod}" 2224:2224
curl --silent http://127.0.0.1:2224/metrics
```

Check Gadget daemon logs for instance or exporter failures:

```bash
kubectl logs --namespace gadget --selector k8s-app=gadget \
  --container gadget --prefix
```

## Customize

- Change `nodeSelector` if GPU nodes use a different discovery label.
- Change `config.operator.otel-profiles.exporters.pyroscope-exporter.endpoint`
  if Pyroscope uses another Kubernetes service name or namespace.
- Add metric allow-list rules under `metricRelabelings` in
  `manifests/podmonitor.yaml` to reduce ingestion.
- Keep the Helm chart and gadget OCI image versions aligned when upgrading.

## Uninstall

```bash
kubectl delete --filename manifests/podmonitor.yaml --ignore-not-found
helm uninstall gadget --namespace gadget
kubectl delete namespace gadget
```
