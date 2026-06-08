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
- `helm/reporter`: daily trade report CronJob scheduled for 4 PM IST

The `taperecorder` Job is annotated with `Force=true,Replace=true` so ArgoCD deletes and recreates the Job during sync. With automated sync enabled, pushing a rendered Helm change to `main` reruns the Job without manually deleting it first.

The `reporter` chart expects runtime credentials in a Kubernetes Secret named `reporter-secrets` by default. Keep real tokens, access keys, and Gmail app passwords in your GitOps secret mechanism rather than committing them to this repo. You can also set `secret.create=true` only when the rendered values are managed safely, such as through SOPS, SealedSecrets, or ExternalSecrets.

```bash
helm lint helm/taperecorder
helm lint helm/reporter
helm template reporter helm/reporter
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
  name: reporter
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/AppsByZubin/infrastructure.git
    targetRevision: main
    path: helm/reporter
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: botspace
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

```
