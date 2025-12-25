#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# bootstrap_k3s.sh
#
# Usage examples:
#   # 1) DEV single-node (server only):
#   ROLE=server ./bootstrap_k3s.sh
#
#   # 2) PROD server:
#   ROLE=server ./bootstrap_k3s.sh
#   # Grab token on server: sudo cat /var/lib/rancher/k3s/server/node-token
#
#   # 3) PROD agent (join server):
#   ROLE=agent K3S_URL="https://<SERVER_IP>:6443" K3S_TOKEN="<NODE_TOKEN>" ./bootstrap_k3s.sh
#
# Optional envs:
#   TARGET_USER="dev" (user to create when running as root)
#   INSTALL_K9S=true|false (default true)
#   INSTALL_ARGOCD=true|false (default true, server only)
#   K3S_VERSION="v1.29.1+k3s1"
#   NAMESPACES="taperecorder botspace"
#
#   HELM_OCI_REGISTRY="ghcr.io"
#   GHCR_USER="<user_or_org>"
#   GHCR_TOKEN="<token>"   # for GHCR login (optional)
# ============================================================

ROLE="${ROLE:-server}"                       # server | agent
K3S_VERSION="${K3S_VERSION:-v1.29.1+k3s1}"
INSTALL_K9S="${INSTALL_K9S:-true}"
INSTALL_ARGOCD="${INSTALL_ARGOCD:-true}"

# Namespaces to create for apps
NAMESPACES="${NAMESPACES:-taperecorder botspace}"

# OCI Helm registry (recommended: GHCR)
HELM_OCI_REGISTRY="${HELM_OCI_REGISTRY:-ghcr.io}"
GHCR_USER="${GHCR_USER:-}"
GHCR_TOKEN="${GHCR_TOKEN:-}"

# For agent join
K3S_URL="${K3S_URL:-}"     # e.g. https://10.0.0.10:6443
K3S_TOKEN="${K3S_TOKEN:-}" # from server: /var/lib/rancher/k3s/server/node-token

# Target non-root user to run k3s tooling
TARGET_USER="${TARGET_USER:-dev}"

echo "==== BOOTSTRAP START (ROLE=${ROLE}) ===="

# ------------------------------------------------------------
# If running as root: create TARGET_USER with sudo and exit
# ------------------------------------------------------------
if [[ $EUID -eq 0 ]]; then
  echo "➡ Script running as root"
  echo "➡ Ensuring user '$TARGET_USER' exists and has sudo access..."

  if ! id -u "$TARGET_USER" &>/dev/null; then
    adduser --disabled-password --gecos "" "$TARGET_USER"
  fi

  usermod -aG sudo "$TARGET_USER"

  echo "➡ User '$TARGET_USER' added to sudo group"
  echo ""
  echo "❌ Please login as '$TARGET_USER' and rerun this script:"
  echo "   su - $TARGET_USER"
  echo "   ./bootstrap_k3s.sh"
  echo ""
  exit 0
fi

# ------------------------------------------------------------
# From here on, we expect a sudo-enabled non-root user
# ------------------------------------------------------------
sudo -v

echo "➡ Updating system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y

echo "➡ Installing base tools..."
sudo apt-get install -y \
  curl wget ca-certificates gnupg lsb-release \
  apt-transport-https software-properties-common \
  jq git unzip

# -----------------------------
# Docker
# -----------------------------
if ! command -v docker >/dev/null; then
  echo "➡ Installing Docker..."
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
else
  echo "✅ Docker already installed"
fi

# -----------------------------
# k3s server/agent install
# -----------------------------
install_k3s_server() {
  if command -v k3s >/dev/null; then
    echo "✅ k3s already installed (server assumed). Skipping."
    return
  fi

  echo "➡ Installing k3s SERVER (cluster control-plane)..."
  curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION="${K3S_VERSION}" \
    sh -s - \
    --write-kubeconfig-mode 644

  echo "✅ k3s server installed."
}

install_k3s_agent() {
  if command -v k3s >/dev/null; then
    echo "✅ k3s already installed (agent assumed). Skipping."
    return
  fi

  if [[ -z "$K3S_URL" || -z "$K3S_TOKEN" ]]; then
    echo "❌ ROLE=agent requires K3S_URL and K3S_TOKEN"
    echo "   Example: ROLE=agent K3S_URL='https://10.0.0.10:6443' K3S_TOKEN='K10....' ./bootstrap_k3s.sh"
    exit 1
  fi

  echo "➡ Installing k3s AGENT (node join)..."
  curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION="${K3S_VERSION}" \
    K3S_URL="${K3S_URL}" \
    K3S_TOKEN="${K3S_TOKEN}" \
    sh -s -

  echo "✅ k3s agent installed and join attempted."
}

case "$ROLE" in
  server) install_k3s_server ;;
  agent)  install_k3s_agent  ;;
  *) echo "❌ ROLE must be 'server' or 'agent'"; exit 1 ;;
esac

# -----------------------------
# kubectl (standalone)
# -----------------------------
if ! command -v kubectl >/dev/null; then
  echo "➡ Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
else
  echo "✅ kubectl already installed"
fi

# -----------------------------
# Helm
# -----------------------------
if ! command -v helm >/dev/null; then
  echo "➡ Installing Helm..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
  echo "✅ Helm already installed"
fi

# -----------------------------
# k9s (optional)
# -----------------------------
if [[ "$INSTALL_K9S" == "true" ]]; then
  if ! command -v k9s >/dev/null; then
    echo "➡ Installing k9s..."
    K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | jq -r .tag_name)
    curl -Lo /tmp/k9s.tar.gz "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz"
    tar -xzf /tmp/k9s.tar.gz -C /tmp k9s
    sudo install -m 0755 /tmp/k9s /usr/local/bin/k9s
    rm -f /tmp/k9s /tmp/k9s.tar.gz
  else
    echo "✅ k9s already installed"
  fi
fi

# -----------------------------
# kubeconfig (server only)
# -----------------------------
if [[ "$ROLE" == "server" ]]; then
  echo "➡ Setting kubeconfig for current user..."
  mkdir -p "$HOME/.kube"
  sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
  sudo chown "$USER:$USER" "$HOME/.kube/config"
  grep -q 'export KUBECONFIG=$HOME/.kube/config' "$HOME/.bashrc" || \
    echo 'export KUBECONFIG=$HOME/.kube/config' >> "$HOME/.bashrc"
fi

# -----------------------------
# Post-install cluster setup (server only)
# -----------------------------
if [[ "$ROLE" == "server" ]]; then
  echo "➡ Waiting for node to be Ready..."
  kubectl wait --for=condition=Ready node --all --timeout=180s || true

  echo "➡ Creating namespaces: $NAMESPACES"
  for ns in $NAMESPACES; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  done

  # Helm OCI / GHCR login (optional)
  if [[ -n "$GHCR_USER" && -n "$GHCR_TOKEN" ]]; then
    echo "➡ Logging into Helm OCI registry (${HELM_OCI_REGISTRY}) for pulling charts..."
    echo "$GHCR_TOKEN" | helm registry login "$HELM_OCI_REGISTRY" -u "$GHCR_USER" --password-stdin

    echo "➡ Creating ghcr-pull imagePullSecret in namespaces (optional)..."
    for ns in $NAMESPACES; do
      kubectl -n "$ns" create secret docker-registry ghcr-pull \
        --docker-server="$HELM_OCI_REGISTRY" \
        --docker-username="$GHCR_USER" \
        --docker-password="$GHCR_TOKEN" \
        --docker-email="${GHCR_EMAIL:-devnull@example.com}" \
        --dry-run=client -o yaml | kubectl apply -f -
    done
  else
    echo "ℹ️ Skipping GHCR login (GHCR_USER/GHCR_TOKEN not set)."
  fi

  # -----------------------------
  # ArgoCD installation (server only)
  # -----------------------------
  if [[ "$INSTALL_ARGOCD" == "true" ]]; then
    echo "➡ Installing ArgoCD in 'argocd' namespace..."

    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

    # Official ArgoCD install manifest (stable)
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    echo "➡ Waiting for ArgoCD pods to become Ready..."
    kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s || true

    echo ""
    echo "✅ ArgoCD installed."
    echo "➡ To get ArgoCD admin password:"
    echo "   kubectl -n argocd get secret argocd-initial-admin-secret \\"
    echo "     -o jsonpath=\"{.data.password}\" | base64 -d; echo"
    echo ""
    echo "➡ To access ArgoCD UI (port-forward):"
    echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "   Then open: https://localhost:8080"
  else
    echo "ℹ️ Skipping ArgoCD install (INSTALL_ARGOCD=false)."
  fi

  echo ""
  echo "✅ Server setup complete."
  echo "➡ Cluster nodes:"
  kubectl get nodes -o wide
  echo ""
  echo "➡ If you want to add agents, run on agent VM:"
  echo "   ROLE=agent K3S_URL='https://<SERVER_IP>:6443' K3S_TOKEN='<NODE_TOKEN>' ./bootstrap_k3s.sh"
  echo ""
  echo "➡ Node token on server is:"
  echo "   sudo cat /var/lib/rancher/k3s/server/node-token"
fi

echo ""
echo "✅ Bootstrap complete!"
echo "ℹ️ Logout & login again to activate docker group membership (if Docker just installed)."
echo "==== BOOTSTRAP END ===="
