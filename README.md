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
- `helm/reporter`: daily trade report CronJob scheduled for 10:20 PM IST

The `taperecorder` Job is annotated with `Force=true,Replace=true` so ArgoCD deletes and recreates the Job during sync. With automated sync enabled, pushing a rendered Helm change to `main` reruns the Job without manually deleting it first.

The `reporter` chart expects runtime credentials in a Kubernetes Secret named `reporter-secrets` by default. Keep real tokens, access keys, and optional email credentials in your GitOps secret mechanism rather than committing them to this repo. You can also set `secret.create=true` only when the rendered values are managed safely, such as through SOPS, SealedSecrets, or ExternalSecrets.

Create the prod secret out-of-band before running the CronJob:

The reporter CronJob uploads to Slack by default. `SLACK_BOT_TOKEN` needs the
Slack `files:write` scope, and the app must be invited to `SLACK_CHANNEL_ID`.
Production reports also require `UPSTOX_API_ACCESS_TOKEN` so the reporter can
hydrate production order rows from Upstox order details. Mock reports do not use
Upstox and write `<YYYYMMDD>_mock_report.xlsx`.

```bash
kubectl -n botspace get secret reporter-secrets

kubectl -n botspace create secret generic reporter-secrets \
  --from-literal=DO_S3_REGION="$DO_S3_REGION" \
  --from-literal=DO_S3_ACCESS_KEY_ID="$DO_S3_ACCESS_KEY_ID" \
  --from-literal=DO_S3_SECRET_ACCESS_KEY="$DO_S3_SECRET_ACCESS_KEY" \
  --from-literal=DO_S3_BUCKET_NAME="$DO_S3_BUCKET_NAME" \
  --from-literal=DO_S3_ENDPOINT_URL="$DO_S3_ENDPOINT_URL" \
  --from-literal=SLACK_BOT_TOKEN="$SLACK_BOT_TOKEN" \
  --from-literal=SLACK_CHANNEL_ID="$SLACK_CHANNEL_ID" \
  --from-literal=UPSTOX_API_ACCESS_TOKEN="$UPSTOX_API_ACCESS_TOKEN"
```

Email is still optional. Add `--sendmail` to `helm/reporter/values.yaml` args
and include `EMAIL_TO`, `EMAIL_FROM`, and `GMAIL_APP_PASSWORD` in the same
secret only if you want the report emailed too. `EMAIL_TO` can contain one
recipient or a comma-separated list, for example `a@a.com,b@b.com`.

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
kubectl apply -f argocd/applications/reporter.yaml
```
