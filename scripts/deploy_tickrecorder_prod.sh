#!/usr/bin/env bash
set -Eeuo pipefail

# Deploy tickrecorder from the infrastructure repository through production
# Argo CD. Do not enable shell tracing here: this script handles credentials.

APP_NAME="${APP_NAME:-tickrecorder}"
ARGO_PROJECT="${ARGO_PROJECT:-default}"
ARGO_REPO="${ARGO_REPO:-https://github.com/AppsByZubin/infrastructure.git}"
ARGO_REVISION="${ARGO_REVISION:-main}"
ARGO_PATH="${ARGO_PATH:-helm/tickrecorder}"
DEST_SERVER="${DEST_SERVER:-https://kubernetes.default.svc}"
NAMESPACE="${NAMESPACE:-botspace}"
SYNC_TIMEOUT_SECONDS="${SYNC_TIMEOUT_SECONDS:-300}"
IMAGE_PULL_TIMEOUT_SECONDS="${IMAGE_PULL_TIMEOUT_SECONDS:-300}"
IMAGE_PULL_SECRET="${IMAGE_PULL_SECRET:-dockerhub-registry}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

for command_name in argocd kubectl; do
  command -v "${command_name}" >/dev/null 2>&1 || die "${command_name} is not installed"
done

for variable_name in \
  FYERS_SYMBOLS \
  FYERS_APP_ID \
  FYERS_ACCESS_TOKEN \
  DO_S3_ACCESS_KEY_ID \
  DO_S3_SECRET_ACCESS_KEY; do
  [[ -n "${!variable_name:-}" ]] || die "${variable_name} is not set"
done

printf 'Kubernetes context: %s\n' "$(kubectl config current-context)"
printf 'Argo CD app: %s (%s@%s)\n' "${APP_NAME}" "${ARGO_REPO}" "${ARGO_REVISION}"

# Create the namespace first so an optional private-registry pull secret can be
# installed before Argo CD creates the Job.
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

helm_parameters=(
  --helm-set-string "env.FYERS_SYMBOLS=${FYERS_SYMBOLS}"
  --helm-set-string "env.FYERS_APP_ID=${FYERS_APP_ID}"
  --helm-set-string "env.FYERS_ACCESS_TOKEN=${FYERS_ACCESS_TOKEN}"
  --helm-set-string "env.DO_S3_ACCESS_KEY_ID=${DO_S3_ACCESS_KEY_ID}"
  --helm-set-string "env.DO_S3_SECRET_ACCESS_KEY=${DO_S3_SECRET_ACCESS_KEY}"
)

# Docker Hub credentials are only needed when bizzkpm/tickrecorder is private.
# These values must be available on the production host; GitHub Actions secrets
# cannot be read by this script.
if [[ -n "${DOCKERHUB_USERNAME:-}" || -n "${DOCKERHUB_TOKEN:-}" ]]; then
  [[ -n "${DOCKERHUB_USERNAME:-}" ]] || die "DOCKERHUB_USERNAME must accompany DOCKERHUB_TOKEN"
  [[ -n "${DOCKERHUB_TOKEN:-}" ]] || die "DOCKERHUB_TOKEN must accompany DOCKERHUB_USERNAME"

  kubectl -n "${NAMESPACE}" create secret docker-registry "${IMAGE_PULL_SECRET}" \
    --docker-server=https://index.docker.io/v1/ \
    --docker-username="${DOCKERHUB_USERNAME}" \
    --docker-password="${DOCKERHUB_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f -

  helm_parameters+=(--helm-set-string "imagePullSecrets[0].name=${IMAGE_PULL_SECRET}")
fi

argocd app create "${APP_NAME}" \
  --repo "${ARGO_REPO}" \
  --revision "${ARGO_REVISION}" \
  --path "${ARGO_PATH}" \
  --dest-server "${DEST_SERVER}" \
  --dest-namespace "${NAMESPACE}" \
  --project "${ARGO_PROJECT}" \
  --values values.yaml \
  --sync-policy automated \
  --auto-prune \
  --self-heal \
  --sync-option CreateNamespace=true \
  --upsert \
  "${helm_parameters[@]}"

# The chart's Job also carries Force=true,Replace=true. Passing the flags here
# makes a manual production deployment recreate the one-shot Job immediately.
argocd app sync "${APP_NAME}" --force --replace --assumeYes
argocd app wait "${APP_NAME}" --sync --timeout "${SYNC_TIMEOUT_SECONDS}"

pod_name=""
deadline=$((SECONDS + IMAGE_PULL_TIMEOUT_SECONDS))
while ((SECONDS < deadline)); do
  pod_name="$(
    kubectl -n "${NAMESPACE}" get pods \
      -l app=tickrecorder \
      --sort-by=.metadata.creationTimestamp \
      -o name 2>/dev/null | tail -n 1
  )"

  if [[ -n "${pod_name}" ]]; then
    image_id="$(kubectl -n "${NAMESPACE}" get "${pod_name}" -o jsonpath='{.status.containerStatuses[0].imageID}' 2>/dev/null || true)"
    wait_reason="$(kubectl -n "${NAMESPACE}" get "${pod_name}" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)"

    if [[ -n "${image_id}" ]]; then
      break
    fi

    if [[ "${wait_reason}" == "ErrImagePull" || "${wait_reason}" == "ImagePullBackOff" ]]; then
      kubectl -n "${NAMESPACE}" describe "${pod_name}" >&2 || true
      die "production could not pull the tickrecorder image"
    fi
  fi

  sleep 3
done

[[ -n "${pod_name}" ]] || die "Argo CD synced, but no tickrecorder pod was created"
image_id="$(kubectl -n "${NAMESPACE}" get "${pod_name}" -o jsonpath='{.status.containerStatuses[0].imageID}' 2>/dev/null || true)"
[[ -n "${image_id}" ]] || die "timed out waiting for production to pull the image"

deployed_image="$(kubectl -n "${NAMESPACE}" get "${pod_name}" -o jsonpath='{.spec.containers[0].image}')"
[[ "${deployed_image}" != *:latest ]] || die "refusing a production deployment that still uses the latest tag"

printf '\nDeployment complete.\n'
printf 'Application: %s\n' "${APP_NAME}"
printf 'Pod:         %s\n' "${pod_name#pod/}"
printf 'Image:       %s\n' "${deployed_image}"
printf 'Image ID:    %s\n' "${image_id}"
kubectl -n "${NAMESPACE}" get job tickrecorder
