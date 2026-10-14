# WireGuard Full-Tunnel VPN Installer

A lightweight, security-conscious installer for setting up a personal **WireGuard full-tunnel VPN** on an Ubuntu DigitalOcean Droplet.

All internet traffic from the configured client is routed through the Droplet, so websites see the Droplet's public IP address instead of the client's normal IP address.

> **Recommended for personal use.** This project is designed for a small Ubuntu server and a few personal devices—not for operating a commercial VPN service.

## Features

- Installs WireGuard on Ubuntu
- Configures a full-tunnel IPv4 VPN
- Enables IPv4 forwarding and NAT
- Detects the Droplet's default network interface automatically
- Detects the current SSH port automatically
- Preserves password-based SSH access
- Configures UFW without intentionally blocking SSH
- Generates a separate client key and profile
- Prints a QR code for easy mobile setup
- Starts WireGuard automatically at boot
- Refuses to overwrite an existing `wg0` configuration

## Requirements

- Ubuntu 22.04 or 24.04
- Root access, or an account with working `sudo`
- A public IPv4 address
- A UDP firewall rule for port `51820`
- A client device with the official WireGuard app

A small Droplet with **1 vCPU, 512 MB RAM, and 10 GB disk** is sufficient for personal use. Network bandwidth and the provider's traffic policy are more likely to be limiting factors than CPU or memory.

## Quick installation

### Download from GitHub

Replace `OWNER/REPOSITORY` with the repository path:

```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/REPOSITORY/main/wireguard-install.sh -o /tmp/wireguard-install.sh
```

### Run the installer

As `root`:

```bash
bash /tmp/wireguard-install.sh phone
```

As a normal user with `sudo`:

```bash
sudo bash /tmp/wireguard-install.sh phone
```

Replace `phone` with a short device name such as `laptop` or `tablet`. The name may contain letters, numbers, underscores, and hyphens.

The installer will run `apt-get update` and install the required packages. It does **not** perform a full Ubuntu system upgrade.

## DigitalOcean firewall

If a DigitalOcean Cloud Firewall is enabled, add this inbound rule:

| Protocol | Port | Source |
|---|---:|---|
| UDP | `51820` | `0.0.0.0/0` |

Keep the existing SSH rule unchanged. If you use IPv6, configure an appropriate IPv6 firewall rule separately; this installer initially configures IPv4 only.

## Android setup

The installer prints a QR code containing the client profile. On another screen, open the official WireGuard Android app:

1. Tap **Add a tunnel**.
2. Choose **Scan from QR code**.
3. Scan the QR code shown by the installer.
4. Save the tunnel.
5. Activate it and approve Android's VPN permission prompt.

If the QR code is shown on the same phone, display it on another phone or computer. Alternatively, manually copy the profile values from:

```bash
cat /root/wireguard-clients/phone.conf
```

A generated client profile has this general structure:

```ini
[Interface]
PrivateKey = <client-private-key>
Address = 10.8.0.2/32
DNS = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = <server-public-key>
Endpoint = <droplet-ip>:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

### Important client settings

- `AllowedIPs = 0.0.0.0/0` routes all IPv4 traffic through the VPN.
- `PersistentKeepalive = 25` is optional. It can help phones maintain a connection behind mobile-carrier or Wi-Fi NAT. Remove it if the client reports that it is unnecessary.
- Do not change or share the client `PrivateKey`.

## Verify the connection

On the client device, visit:

```text
https://icanhazip.com
```

The result should be the Droplet's public IPv4 address.

On the server, check WireGuard:

```bash
wg show
```

A connected client should show:

- A recent `latest handshake`
- Increasing receive and send transfer counters

Check the service status:

```bash
systemctl status wg-quick@wg0 --no-pager
```

## Updating Ubuntu

The installer updates the package index but does not upgrade the entire operating system. Perform system upgrades separately:

```bash
apt update && apt full-upgrade -y
apt autoremove -y
```

Reboot only if Ubuntu reports that a reboot is required:

```bash
reboot
```

## Security notes

### Protect private keys

The following files contain sensitive key material and must never be committed to GitHub or shared publicly:

```text
/root/wireguard-clients/*.conf
/etc/wireguard/server_private.key
/etc/wireguard/*.conf
```

The client profile contains the client's private key. Anyone who obtains it may be able to authenticate as that WireGuard peer.

### SSH access

This installer does not disable password authentication or change the SSH port. After confirming that key-based SSH login works, consider hardening SSH separately:

- Create and test an SSH key
- Disable root SSH login where appropriate
- Disable password authentication only after key login has been verified
- Keep the SSH firewall rule open before enabling UFW changes

### IPv6 warning

The generated profile routes IPv4 traffic through the VPN using `0.0.0.0/0`. IPv6 is not configured by this installer. If the client has IPv6 connectivity, IPv6 traffic may bypass the tunnel.

Until IPv6 routing is configured, enable the WireGuard app's **block connections without VPN** option if available, or disable IPv6 on the client. Do not add `::/0` to the profile unless the server has been configured to forward and route IPv6 correctly.

### Datacenter IP limitations

A DigitalOcean address is a datacenter IP, not a residential IP. Some websites and streaming services may rate-limit or block it. This setup does not provide anonymity, rotating locations, or residential proxy behavior.

## Troubleshooting

### No handshake appears

Check the following:

```bash
systemctl status wg-quick@wg0 --no-pager
wg show
ufw status verbose
ss -lunp | grep 51820
```

Then confirm that:

- The client endpoint uses the correct public IPv4 address.
- UDP port `51820` is allowed in the DigitalOcean firewall.
- UDP port `51820` is allowed by UFW.
- The client tunnel is enabled.
- The client public key is present in `/etc/wireguard/wg0.conf`.

### The tunnel connects but browsing does not work

Check forwarding and NAT:

```bash
sysctl net.ipv4.ip_forward
iptables -t nat -S POSTROUTING
```

IPv4 forwarding should return:

```text
net.ipv4.ip_forward = 1
```

Restart the tunnel if necessary:

```bash
systemctl restart wg-quick@wg0
```

### SSH stopped working

Do not repeatedly enable or reset the firewall remotely. Use the DigitalOcean console if necessary, then allow your SSH port before enabling UFW:

```bash
ufw allow 22/tcp
ufw allow 51820/udp
ufw status verbose
```

Replace `22` with your actual SSH port.

## Uninstall

To stop and disable the WireGuard service:

```bash
systemctl disable --now wg-quick@wg0
```

To remove the configuration and generated keys, verify the paths carefully before deleting:

```bash
rm -f /etc/wireguard/wg0.conf
rm -f /etc/wireguard/server_private.key /etc/wireguard/server_public.key
rm -rf /root/wireguard-clients
rm -f /etc/sysctl.d/99-wireguard-forwarding.conf
sysctl --system
```

If WireGuard was installed only for this project, remove the packages with:

```bash
apt remove --purge -y wireguard wireguard-tools qrencode
apt autoremove -y
```

## License

Choose and add a license before publishing this repository. For a small personal utility, the MIT License is a common permissive choice.
