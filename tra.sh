#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "\n${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[x]${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Execute como root: sudo $0"

echo "
=========================
       TRASHBIN
   server setup script
========================="

# ── Sistema ──────────────────────────────────────────────────────────────────

log "Atualizando sistema..."
apt update && apt upgrade -y

log "Configurando atualizações automáticas de segurança..."
apt install -y unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades

# ── SSH ───────────────────────────────────────────────────────────────────────

log "Instalando e ativando SSH..."
apt install -y openssh-server
systemctl enable --now ssh

log "Hardening do SSH..."
cat > /etc/ssh/sshd_config.d/hardening.conf <<EOF
PermitRootLogin no
MaxAuthTries 3
LoginGraceTime 30
EOF
grep -q '^Include /etc/ssh/sshd_config.d/\*\.conf' /etc/ssh/sshd_config \
    || echo 'Include /etc/ssh/sshd_config.d/*.conf' >> /etc/ssh/sshd_config
systemctl restart ssh

# ── Notebook como servidor ────────────────────────────────────────────────────

log "Configurando tampa e energia do notebook..."
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/server.conf <<EOF
[Login]
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
HandleLidSwitchExternalPower=ignore
HandlePowerKey=ignore
HandleLidSwitchResumeFromSuspend=ignore
EOF

log "Desativando suspensão e hibernação..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

systemctl restart systemd-logind

# ── Estrutura de diretórios ───────────────────────────────────────────────────

log "Criando /srv..."
mkdir -p /srv/{data,backups,media,docker}

# ── Docker ────────────────────────────────────────────────────────────────────

log "Instalando Docker..."
if command -v docker &>/dev/null; then
    warn "Docker já instalado, pulando..."
else
    apt install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings

    . /etc/os-release
    curl -fsSL "https://download.docker.com/linux/${ID}/gpg" \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt update
    apt install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
fi

# Adiciona o usuário que chamou sudo ao grupo docker
if [[ -n "${SUDO_USER:-}" ]]; then
    usermod -aG docker "$SUDO_USER"
    warn "Usuário '$SUDO_USER' adicionado ao grupo docker (requer novo login para ter efeito)."
fi

log "Configurando log rotation do Docker..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "5"
  }
}
EOF
systemctl restart docker

# ── Portainer ─────────────────────────────────────────────────────────────────

log "Instalando Portainer..."
if docker ps -a --format '{{.Names}}' | grep -q '^portainer$'; then
    warn "Portainer já existe, pulando..."
else
    docker volume create portainer_data
    docker run -d \
        --name portainer \
        --restart=always \
        -p 9443:9443 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest
fi

# ── fail2ban ──────────────────────────────────────────────────────────────────

log "Instalando fail2ban..."
apt install -y fail2ban
cat > /etc/fail2ban/jail.d/ssh.conf <<EOF
[sshd]
enabled  = true
maxretry = 5
bantime  = 1h
findtime = 10m
EOF
systemctl enable --now fail2ban

# ── Tailscale ─────────────────────────────────────────────────────────────────

log "Instalando Tailscale..."
if command -v tailscale &>/dev/null; then
    warn "Tailscale já instalado, pulando..."
else
    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable --now tailscaled
fi

# ── ufw ───────────────────────────────────────────────────────────────────────

log "Configurando firewall (ufw)..."
apt install -y ufw
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh                          comment "SSH"
ufw allow 9443/tcp                     comment "Portainer"
ufw allow in on tailscale0             comment "Tailscale"
ufw --force enable

# ── Resumo ────────────────────────────────────────────────────────────────────

SERVER_IP=$(hostname -I | awk '{print $1}')

log "Status SSH"
systemctl status ssh --no-pager -l

echo ""
echo "================================="
echo " Servidor configurado!"
echo " IP: ${SERVER_IP}"
echo "================================="
warn "Proximos passos manuais:"
echo "  1. tailscale up"
echo "  2. Portainer: https://${SERVER_IP}:9443"
echo "  3. Depois de confirmar que sua chave SSH funciona, desative login por senha:"
echo "     PasswordAuthentication no  →  /etc/ssh/sshd_config.d/hardening.conf"
echo "     systemctl restart ssh"
echo "  4. Depois de confirmar acesso via Tailscale, restrinja o SSH a ele:"
echo "     ufw deny 22/tcp"
echo "     ufw allow in on tailscale0 to any port 22"

