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
- `helm/tickrecorder`: FYERS trade-tick recorder Job, PVC, and verified DigitalOcean upload
- `helm/reporter`: daily trade report CronJob scheduled for 8:17 PM IST

The `taperecorder` and `tickrecorder` Jobs are annotated with
`Force=true,Replace=true` so ArgoCD deletes and recreates them when their own
rendered Job changes. Each restart annotation uses that chart's version, so a
version bump in one recorder does not rerun the other recorder. Tickrecorder owns market timing in application code rather than in a Kubernetes CronJob.

The `reporter` and `taperecorder` charts pass most runtime values directly
through their `env:` blocks in `values.yaml`. The reporter Slack delivery values
are the exception: `SLACK_BOT_TOKEN` and `SLACK_CHANNEL_ID` come from a
Kubernetes Secret named `reporter-slack-secrets`.

The tickrecorder chart passes FYERS and DigitalOcean credentials as container
environment variables, matching taperecorder's Helm pattern. Keep the committed
defaults empty and provide real values only while installing the chart:

```bash
helm upgrade --install tickrecorder helm/tickrecorder \
  --namespace botspace \
  --set-string env.FYERS_SYMBOLS="$FYERS_SYMBOLS" \
  --set-string env.FYERS_APP_ID="$FYERS_APP_ID" \
  --set-string env.FYERS_ACCESS_TOKEN="$FYERS_ACCESS_TOKEN" \
  --set-string env.DO_S3_ACCESS_KEY_ID="$DO_S3_ACCESS_KEY_ID" \
  --set-string env.DO_S3_SECRET_ACCESS_KEY="$DO_S3_SECRET_ACCESS_KEY"
```

The Job may be triggered before market open, for example at 08:00. Tickrecorder
waits in-process until 09:15 Asia/Kolkata, opens the FYERS WebSockets, records
until 15:31, then disconnects, drains Parquet files, creates the date archive,
and uploads it to DigitalOcean Spaces. The pod's termination grace period covers
Parquet drain, gzip creation, Spaces upload, and full read-back checksum verification.

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
helm lint helm/tickrecorder \
  --set-string env.FYERS_SYMBOLS=NSE:TEST-EQ \
  --set-string env.FYERS_APP_ID=test-app-100 \
  --set-string env.FYERS_ACCESS_TOKEN=test-token \
  --set-string env.DO_S3_ACCESS_KEY_ID=test-key \
  --set-string env.DO_S3_SECRET_ACCESS_KEY=test-secret
helm lint helm/reporter
helm template tickrecorder helm/tickrecorder --namespace botspace \
  --set-string env.FYERS_SYMBOLS=NSE:TEST-EQ \
  --set-string env.FYERS_APP_ID=test-app-100 \
  --set-string env.FYERS_ACCESS_TOKEN=test-token \
  --set-string env.DO_S3_ACCESS_KEY_ID=test-key \
  --set-string env.DO_S3_SECRET_ACCESS_KEY=test-secret
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
