#!/usr/bin/env bash

set -euo pipefail

readonly RELEASE_NAME="gadget"
readonly NAMESPACE="gadget"
readonly CHART_REF="oci://ghcr.io/inspektor-gadget/inspektor-gadget/charts/gadget"
readonly CHART_VERSION="${CHART_VERSION:-0.55.0}"

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly VALUES_FILE="${VALUES_FILE:-${REPO_DIR}/values.yaml}"
readonly PODMONITOR_FILE="${PODMONITOR_FILE:-${REPO_DIR}/manifests/podmonitor.yaml}"

for command in helm kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "error: required command not found: ${command}" >&2
    exit 1
  fi
done

for file in "${VALUES_FILE}" "${PODMONITOR_FILE}"; do
  if [[ ! -f "${file}" ]]; then
    echo "error: required file not found: ${file}" >&2
    exit 1
  fi
done

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "error: kubectl cannot reach the current cluster" >&2
  exit 1
fi

if ! kubectl api-resources --api-group=azmonitoring.coreos.com -o name |
  grep -qx 'podmonitors.azmonitoring.coreos.com'; then
  echo "error: Azure Monitor PodMonitor CRD is not installed" >&2
  exit 1
fi

if [[ -z "$(kubectl get nodes \
  --selector 'kubernetes.azure.com/accelerator=nvidia' \
  --output name)" ]]; then
  echo "error: no NVIDIA nodes match kubernetes.azure.com/accelerator=nvidia" >&2
  exit 1
fi

helm upgrade --install "${RELEASE_NAME}" "${CHART_REF}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --version "${CHART_VERSION}" \
  --values "${VALUES_FILE}" \
  --wait \
  --timeout 10m

kubectl apply --filename "${PODMONITOR_FILE}"
