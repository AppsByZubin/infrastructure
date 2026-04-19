# Infrastructure To setup projects

## VM setup Prod/Dev

execute setup script
```bash
./dev_vm_setup.sh
```
### dependencies that got installed
install Docker, k3s, kubectl, helm
install ArgoCD server into cluster
install ArgoCD CLI onto VM
set kubeconfig
create namespaces

## Argo setup
Shared infrastructure Helm charts live under `infrastructure/helm/`. Project-owned Helm charts should live in their project repositories.

## Helm charts

The repo currently carries Helm charts for:

- `helm/taperecorder`: market data recorder Job and optional PVC

The `taperecorder` Job is annotated with `Force=true,Replace=true` so ArgoCD deletes and recreates the Job during sync. With automated sync enabled, pushing a rendered Helm change to `main` reruns the Job without manually deleting it first.

Runtime credentials are expected under each chart's `secretEnv` values. Keep real tokens and access keys in a private values file or your GitOps secret mechanism rather than committing them to this repo. To use a pre-created Kubernetes Secret, set `secret.create=false` and keep `secret.enabled=true`.

```bash
helm lint helm/taperecorder
```

```
argocd repo add https://github.com/AppsByZubin/infrastructure.git \
  --username <YOUR_GITHUB_USERNAME> \
  --password <YOUR_GITHUB_PAT> \
  --name infrastructure
```

deploy argocd app
```
cat <<'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: taperecorder
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/AppsByZubin/infrastructure.git
    targetRevision: main
    path: helm/taperecorder    # <--- change this if necessary
    helm:
      valueFiles:
        - values.yaml          # or values-dev.yaml / values-prod.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: botspace
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

```
