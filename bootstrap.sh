#!/usr/bin/env bash
# Prepares a fresh Ubuntu 22.04/24.04 server (Oracle Cloud or any VPS).
# Run once:  sudo bash bootstrap.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo:  sudo bash bootstrap.sh"; exit 1; }
export DEBIAN_FRONTEND=noninteractive
TARGET_USER="${SUDO_USER:-ubuntu}"
is_oracle(){ grep -qi oracle /sys/class/dmi/id/chassis_asset_tag 2>/dev/null; }

echo "==> Updating packages"
apt-get update -y && apt-get upgrade -y
apt-get install -y ca-certificates curl openssl fail2ban unattended-upgrades netcat-openbsd

echo "==> Firewall"
if is_oracle; then
  # Oracle images ship iptables rules that block 80/443; open them (ufw is not used on Oracle).
  apt-get install -y iptables-persistent
  allow(){ iptables -C INPUT -p "$1" --dport "$2" -j ACCEPT 2>/dev/null \
           || iptables -I INPUT 5 -p "$1" --dport "$2" -j ACCEPT 2>/dev/null \
           || iptables -I INPUT 1 -p "$1" --dport "$2" -j ACCEPT; }
  allow tcp 80; allow tcp 443; allow udp 443
  netfilter-persistent save
  echo "    Reminder: also open ports 80 and 443 in the Oracle console (VCN Security List)."
else
  apt-get install -y ufw
  ufw default deny incoming; ufw default allow outgoing
  ufw allow 22/tcp; ufw allow 80/tcp; ufw allow 443/tcp; ufw allow 443/udp
  ufw --force enable
fi

echo "==> Brute-force protection and automatic security updates"
systemctl enable --now fail2ban
dpkg-reconfigure -f noninteractive unattended-upgrades || true

echo "==> Docker"
if ! command -v docker >/dev/null; then curl -fsSL https://get.docker.com | sh; fi
systemctl enable --now docker
usermod -aG docker "$TARGET_USER"

MEM_MB=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
if [ "$MEM_MB" -lt 8000 ] && ! swapon --show | grep -q .; then
  echo "==> Adding 4 GB swap (RAM is ${MEM_MB} MB)"
  fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo
echo "Server ready. Architecture: $(uname -m), RAM: ${MEM_MB} MB"
echo "Log out and back in (so the docker group applies), then:"
echo "  cd divine-ollama && bash make-env.sh && docker compose up -d --build"
