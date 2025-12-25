#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# bootstrap_k3s.sh
#
# Usage:
#   ROLE=server ./bootstrap_k3s.sh
#   ROLE=agent K3S_URL="https://SERVER_IP:6443" K3S_TOKEN="NODE_TOKEN" ./bootstrap_k3s.sh
#
# Behavior:
#   - If run as root: creates TARGET_USER then exits (asks to rerun as that user)
#   - As sudo user: installs Docker, k3s, kubectl, helm, ArgoCD, ArgoCD CLI
# ============================================================

ROLE="${ROLE:-server}"                       # server | agent
K3S_VERSION="${K3S_VERSION:-v1.29.1+k3s1}"
INSTALL_K9S="${INSTALL_K9S:-true}"
INSTALL_ARGOCD="${INSTALL_ARGOCD:-true}"

# 🔹 default user now 'dev'
TARGET_USER="${TARGET_USER:-dev}"

# 🔹 only one namespace now
NAMESPACES="${NAMESPACES:-botspace}"

# For k3s agent join
K3S_URL="${K3S_URL:-}"
K3S_TOKEN="${K3S_TOKEN:-}"

echo "==== BOOTSTRAP START (ROLE=${ROLE}) ===="

# ------------------------------------------------------------
# If running as root → create sudo user and exit
# ------------------------------------------------------------
if [[ $EUID -eq 0 ]]; then
  echo "➡ Script running as root"
  echo "➡ Ensuring user '$TARGET_USER' exists and has sudo access..."

  if ! id -u "$TARGET_USER" &>/dev/null; then
    adduser --disabled-password --gecos "" "$TARGET_USER"
  fi

  usermod -aG sudo "$TARGET_USER"

  echo ""
  echo "✅ User '$TARGET_USER' ensured with sudo rights."
  echo "❌ Please login as '$TARGET_USER' and rerun this script:"
  echo "   su - $TARGET_USER"
  echo "   ./bootstrap_k3s.sh"
  echo ""
  exit 0
fi

# ------------------------------------------------------------
# Require sudo on non-root
# ------------------------------------------------------------
sudo -v

echo "➡ Updating system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y

echo "➡ Installing base tools..."
sudo apt-get install -y \
  curl wget ca-certificates gnupg lsb-release \
  apt-transport-https software-properties-common \
  jq git unzip tar

# ------------------------------------------------------------
# Docker
# ------------------------------------------------------------
if ! command -v docker >/dev/null; then
  echo "➡ Installing Docker..."
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
else
  echo "✅ Docker already installed"
fi

# ------------------------------------------------------------
# k3s Install
# ------------------------------------------------------------
install_k3s_server() {
  if command -v k3s >/dev/null; then
    echo "✅ k3s already installed (server assumed)"
    return
  fi

  echo "➡ Installing k3s SERVER..."
  curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION="${K3S_VERSION}" \
    sh -s - \
    --write-kubeconfig-mode 644

  echo "✅ k3s server installed"
}

install_k3s_agent() {
  if [[ -z "$K3S_URL" || -z "$K3S_TOKEN" ]]; then
    echo "❌ ROLE=agent requires K3S_URL and K3S_TOKEN"
    exit 1
  fi

  echo "➡ Installing k3s AGENT..."
  curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION="${K3S_VERSION}" \
    K3S_URL="${K3S_URL}" \
    K3S_TOKEN="${K3S_TOKEN}" \
    sh -s -

  echo "✅ k3s agent installed"
}

case "$ROLE" in
  server) install_k3s_server ;;
  agent)  install_k3s_agent  ;;
  *) echo "❌ ROLE must be 'server' or 'agent'"; exit 1 ;;
esac

# ------------------------------------------------------------
# kubectl install
# ------------------------------------------------------------
if ! command -v kubectl >/dev/null; then
  echo "➡ Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
else
  echo "✅ kubectl already installed"
fi

# ------------------------------------------------------------
# Helm install
# ------------------------------------------------------------
if ! command -v helm >/dev/null; then
  echo "➡ Installing Helm..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
  echo "✅ Helm already installed"
fi

# ------------------------------------------------------------
# k9s (optional)
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# Kubeconfig for user (server only)
# ------------------------------------------------------------
if [[ "$ROLE" == "server" ]]; then
  echo "➡ Setting kubeconfig for ${USER}"
  mkdir -p "$HOME/.kube"
  sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
  sudo chown "$USER:$USER" "$HOME/.kube/config"
fi

# ------------------------------------------------------------
# Create ONLY botspace namespace
# ------------------------------------------------------------
if [[ "$ROLE" == "server" ]]; then
  echo "➡ Creating namespace: botspace"
  kubectl create namespace botspace --dry-run=client -o yaml | kubectl apply -f -
fi

# ------------------------------------------------------------
# Install ArgoCD SERVER (in cluster)
# ------------------------------------------------------------
if [[ "$ROLE" == "server" && "$INSTALL_ARGOCD" == "true" ]]; then
  echo "➡ Installing ArgoCD into cluster..."

  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  echo "➡ Waiting for ArgoCD server to be available..."
  kubectl wait deployment/argocd-server -n argocd --for=condition=Available --timeout=300s || true

  echo "✅ ArgoCD server installed in cluster"
fi

# ------------------------------------------------------------
# Install ArgoCD CLI on VM
# ------------------------------------------------------------
echo "➡ Installing ArgoCD CLI..."

TMP_DL="$HOME/argocd-linux-amd64"
curl -sSL -o "$TMP_DL" https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64

chmod +x "$TMP_DL"
sudo mv "$TMP_DL" /usr/local/bin/argocd

if file /usr/local/bin/argocd | grep -q "ELF 64-bit"; then
  echo "✅ ArgoCD CLI installed: $(argocd version --client || true)"
else
  echo "⚠️ Warning: ArgoCD CLI file does not look like ELF binary. Check network/proxy."
fi

# ------------------------------------------------------------
# Final info
# ------------------------------------------------------------
if [[ "$ROLE" == "server" ]]; then
  echo ""
  echo "============ ArgoCD Info ============"
  echo "➡ To get ArgoCD admin password:"
  echo "   kubectl -n argocd get secret argocd-initial-admin-secret \\"
  echo "     -o jsonpath='{.data.password}' | base64 -d; echo"
  echo ""
  echo "➡ To port-forward ArgoCD UI/API:"
  echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
  echo "   Open: https://localhost:8080"
  echo ""
  echo "➡ To login via CLI:"
  echo "   argocd login localhost:8080 --username admin --password <PASSWORD> --insecure"
  echo ""
fi

echo "==== BOOTSTRAP COMPLETE ===="
echo "ℹ️ Logout/login again if Docker group was newly added."
