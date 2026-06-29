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
- `helm/reporter`: daily trade report CronJob scheduled for 7:00 PM IST

The `taperecorder` Job is annotated with `Force=true,Replace=true` so ArgoCD deletes and recreates the Job during sync. With automated sync enabled, pushing a rendered Helm change to `main` reruns the Job without manually deleting it first.

The `reporter` and `taperecorder` charts pass most runtime values directly
through their `env:` blocks in `values.yaml`. The reporter Slack delivery values
are the exception: `SLACK_BOT_TOKEN` and `SLACK_CHANNEL_ID` come from a
Kubernetes Secret named `reporter-slack-secrets`.

The reporter CronJob uploads to Slack by default. `SLACK_BOT_TOKEN` needs the
Slack `files:write` scope, and the app must be invited to `SLACK_CHANNEL_ID`.
Production reports also require `UPSTOX_API_ACCESS_TOKEN` so the reporter can
hydrate production order rows from Upstox order details. Mock reports do not use
Upstox and write `<YYYYMMDD>_mock_report.xlsx`.

```bash
kubectl -n botspace create secret generic reporter-slack-secrets \
  --from-literal=SLACK_BOT_TOKEN="$SLACK_BOT_TOKEN" \
  --from-literal=SLACK_CHANNEL_ID="$SLACK_CHANNEL_ID" \
  --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install reporter helm/reporter \
  --namespace botspace \
  --set-string env.DO_S3_REGION="$DO_S3_REGION" \
  --set-string env.DO_S3_ACCESS_KEY_ID="$DO_S3_ACCESS_KEY_ID" \
  --set-string env.DO_S3_SECRET_ACCESS_KEY="$DO_S3_SECRET_ACCESS_KEY" \
  --set-string env.DO_S3_BUCKET_NAME="$DO_S3_BUCKET_NAME" \
  --set-string env.DO_S3_ENDPOINT_URL="$DO_S3_ENDPOINT_URL" \
  --set-string env.UPSTOX_API_ACCESS_TOKEN="$UPSTOX_API_ACCESS_TOKEN"
```

The daily Upstox token is now just `env.UPSTOX_API_ACCESS_TOKEN` for both
charts. Update that deploy-time value before the Job or CronJob starts.

Email is still optional. Add `--sendmail` to `helm/reporter/values.yaml` args
and provide `env.EMAIL_TO`, `env.EMAIL_FROM`, and `env.GMAIL_APP_PASSWORD` only
if you want the report emailed too. `EMAIL_TO` can contain one
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
