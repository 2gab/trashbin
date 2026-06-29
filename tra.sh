#!/bin/bash

echo "
=========================
       TRASHBIN
   server setup script
=========================
"

echo "=== Atualizando sistema ==="
sudo apt update && sudo apt upgrade -y

echo "=== Instalando SSH ==="
sudo apt install openssh-server -y

echo "=== Ativando SSH ==="
sudo systemctl enable ssh
sudo systemctl start ssh

echo "=== Configurando tampa do notebook ==="

sudo mkdir -p /etc/systemd/logind.conf.d

sudo bash -c 'cat > /etc/systemd/logind.conf.d/lid.conf <<EOF
[Login]
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
HandleLidSwitchExternalPower=ignore
EOF'

echo "=== Desativando suspensão e hibernação ==="

sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

echo "=== Evitando desligar por falta de bateria ==="
sudo nano /etc/systemd/logind.conf

echo "=== Reiniciando systemd-logind ==="
sudo systemctl restart systemd-logind

echo "=== Status SSH ==="
systemctl status ssh --no-pager

echo "=== IP do servidor ==="
hostname -I

echo "Servidor configurado!"

# docker
# portainer
# fail2ban
# ufw
# tailscale
# uma pasta /srv
