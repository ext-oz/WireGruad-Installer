#!/usr/bin/env bash
set -Eeuo pipefail

# Lightweight full-tunnel WireGuard installer for Ubuntu.
# Run as root: sudo bash wireguard-install.sh [client-name]

CLIENT_NAME="${1:-phone}"
WG_IF="wg0"
WG_PORT="51820"
WG_NET="10.8.0.0/24"
WG_SERVER_ADDR="10.8.0.1/24"
WG_SERVER_IP="10.8.0.1"
BASE_DIR="/etc/wireguard"
CLIENT_DIR="/root/wireguard-clients"

if [[ $EUID -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash $0 [client-name]" >&2
  exit 1
fi

if [[ ! "$CLIENT_NAME" =~ ^[A-Za-z0-9_-]{1,32}$ ]]; then
  echo "Client name must contain only letters, numbers, _ or - (max 32 chars)." >&2
  exit 1
fi

if [[ -e "$BASE_DIR/$WG_IF.conf" ]]; then
  echo "$BASE_DIR/$WG_IF.conf already exists; refusing to overwrite it." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y wireguard wireguard-tools qrencode curl ufw

umask 077
install -d -m 700 "$BASE_DIR" "$CLIENT_DIR"

# Detect the interface used for the Droplet's default route.
WAN_IF="$(ip -4 route show default | awk 'NR==1 {print $5}')"
if [[ -z "$WAN_IF" ]]; then
  echo "Could not detect the default network interface." >&2
  exit 1
fi

# Detect the SSH port without changing SSH authentication settings.
SSH_PORT="$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2; exit}')"
SSH_PORT="${SSH_PORT:-22}"

# Preserve an existing UFW policy; if UFW is inactive, enable it safely.
if ufw status | grep -q '^Status: active'; then
  ufw allow "$SSH_PORT/tcp" >/dev/null
  ufw allow "$WG_PORT/udp" >/dev/null
else
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow "$SSH_PORT/tcp"
  ufw allow "$WG_PORT/udp"
  ufw --force enable
fi

# Generate server keys.
SERVER_PRIVATE="$(wg genkey)"
SERVER_PUBLIC="$(printf '%s' "$SERVER_PRIVATE" | wg pubkey)"
printf '%s\n' "$SERVER_PRIVATE" > "$BASE_DIR/server_private.key"
printf '%s\n' "$SERVER_PUBLIC" > "$BASE_DIR/server_public.key"
chmod 600 "$BASE_DIR"/*

# Enable IPv4 forwarding persistently.
cat >/etc/sysctl.d/99-wireguard-forwarding.conf <<'EOF'
net.ipv4.ip_forward=1
EOF
sysctl --system >/dev/null

# Create the server configuration. MASQUERADE provides full-tunnel internet access.
cat >"$BASE_DIR/$WG_IF.conf" <<EOF
[Interface]
Address = $WG_SERVER_ADDR
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIVATE

# Full-tunnel IPv4 NAT. The DROP rule prevents forwarding traffic from bypassing WireGuard.
PostUp = iptables -A FORWARD -i %i -o $WAN_IF -j ACCEPT; iptables -A FORWARD -i $WAN_IF -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -A POSTROUTING -s $WG_NET -o $WAN_IF -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -o $WAN_IF -j ACCEPT; iptables -D FORWARD -i $WAN_IF -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -s $WG_NET -o $WAN_IF -j MASQUERADE
EOF
chmod 600 "$BASE_DIR/$WG_IF.conf"

# Allocate the first unused peer address from 10.8.0.2 onward.
CLIENT_IP=""
for n in $(seq 2 254); do
  candidate="10.8.0.$n"
  if ! grep -Rqs "Address = $candidate/32" "$BASE_DIR" "$CLIENT_DIR" 2>/dev/null; then
    CLIENT_IP="$candidate"
    break
  fi
done
[[ -n "$CLIENT_IP" ]] || { echo "No free client addresses remain." >&2; exit 1; }

CLIENT_PRIVATE="$(wg genkey)"
CLIENT_PUBLIC="$(printf '%s' "$CLIENT_PRIVATE" | wg pubkey)"
ENDPOINT="$(curl -4fsS --max-time 10 https://icanhazip.com | tr -d '[:space:]')"
[[ -n "$ENDPOINT" ]] || { echo "Could not determine the Droplet's public IPv4. Set Endpoint manually in the client file." >&2; exit 1; }

cat >>"$BASE_DIR/$WG_IF.conf" <<EOF

# Peer: $CLIENT_NAME
[Peer]
PublicKey = $CLIENT_PUBLIC
AllowedIPs = $CLIENT_IP/32
EOF

CLIENT_FILE="$CLIENT_DIR/${CLIENT_NAME}.conf"
cat >"$CLIENT_FILE" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE
Address = $CLIENT_IP/32
DNS = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = $SERVER_PUBLIC
Endpoint = $ENDPOINT:$WG_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
chmod 600 "$CLIENT_FILE"

systemctl enable --now wg-quick@$WG_IF
wg syncconf "$WG_IF" <(wg-quick strip "$WG_IF")

# Print the QR code only to the terminal; save the profile root-only.
echo
echo "WireGuard is running."
echo "Server endpoint: $ENDPOINT:$WG_PORT"
echo "Client profile:  $CLIENT_FILE"
echo
echo "Scan this QR code in the WireGuard mobile app:"
qrencode -t ansiutf8 < "$CLIENT_FILE"
echo
echo "To show the profile later: sudo cat '$CLIENT_FILE'"
echo "To check status: sudo wg show"
echo "Note: this profile routes all IPv4 traffic through the Droplet. IPv6 is not included yet; disable IPv6 on the client or add IPv6 routing before relying on leak-free full tunneling."
