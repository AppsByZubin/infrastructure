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
Create the project helm under infrastructure/helm/

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