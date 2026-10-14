# WireGuard Full-Tunnel VPN Installer

A lightweight, security-conscious installer for setting up a personal **WireGuard full-tunnel VPN** on an Ubuntu server.

Once configured, client devices send their IPv4 internet traffic through the server. Websites therefore see the server's public IP address instead of the client's normal public IP address.

> **For personal use:** this project is intended for a small server and a few trusted devices. It is not designed to operate a commercial VPN service.

## What this project does

- Installs WireGuard on an Ubuntu server
- Configures a full-tunnel IPv4 VPN
- Enables IPv4 forwarding and NAT
- Detects the server's default network interface automatically
- Detects the current SSH port automatically
- Preserves existing password-based SSH access
- Configures UFW without intentionally blocking SSH
- Generates a separate client key and profile
- Prints a QR code for mobile setup
- Starts WireGuard automatically at boot
- Refuses to overwrite an existing `wg0` configuration

## Architecture

```text
Phone / laptop / tablet
          │
          │ encrypted WireGuard tunnel
          ▼
     Ubuntu server
          │
          │ IPv4 forwarding and NAT
          ▼
       Internet
```

## Requirements

### Server

- Ubuntu 22.04 or 24.04
- Root access, or an account with working `sudo`
- A public IPv4 address or a DNS hostname that resolves to the server
- Ability to allow inbound UDP traffic on port `51820`
- A firewall or security-group rule allowing the server's SSH port

The installer is intentionally written for **Ubuntu servers**. The client devices can use Android, iPhone/iPad, Windows, macOS, or Linux.

### Client

Install the official WireGuard application or package for the device you want to connect:

- [Android](https://www.wireguard.com/install/)
- [iPhone and iPad](https://www.wireguard.com/install/)
- [Windows](https://www.wireguard.com/install/)
- [macOS](https://www.wireguard.com/install/)
- [Linux](https://www.wireguard.com/install/)

## Quick installation

### 1. Download the installer

Run this on the Ubuntu server:

```bash
curl -fsSL https://raw.githubusercontent.com/ext-oz/WireGruad-Installer/main/wireguard-install.sh -o /tmp/wireguard-install.sh
```

The repository is hosted at:

<https://github.com/ext-oz/WireGruad-Installer>

### 2. Run the installer

If you are logged in as `root`:

```bash
bash /tmp/wireguard-install.sh phone
```

If you are logged in as a normal user with `sudo`:

```bash
sudo bash /tmp/wireguard-install.sh phone
```

Replace `phone` with a short device name such as `laptop`, `tablet`, `windows-pc`, or `macbook`. The name may contain letters, numbers, underscores, and hyphens.

The installer will:

1. Refresh the Ubuntu package index with `apt-get update`.
2. Install WireGuard, UFW, QR-code support, and required tools.
3. Enable IPv4 forwarding.
4. Configure IPv4 NAT through the server's default interface.
5. Create a server key pair.
6. Create one client profile.
7. Enable WireGuard at boot.

It does **not** perform a full Ubuntu system upgrade.

## Firewall configuration

Allow the WireGuard UDP port in every firewall layer in front of the server:

| Protocol | Port | Source |
|---|---:|---|
| UDP | `51820` | `0.0.0.0/0` |

Also keep the server's existing SSH rule unchanged. If IPv6 is enabled, configure a separate IPv6 rule only after IPv6 routing has been configured for WireGuard.

On the Ubuntu server, the installer allows SSH and WireGuard through UFW. Review the resulting rules with:

```bash
ufw status verbose
```

## Import the generated client profile

The generated profile is saved on the server at:

```text
/root/wireguard-clients/<client-name>.conf
```

For example:

```text
/root/wireguard-clients/phone.conf
```

The installer also prints a QR code containing the profile.

> **Protect this file.** It contains the client's private WireGuard key. Never commit it to Git, paste it into a public issue, or share it with anyone you do not trust.

### Android

1. Open the WireGuard app.
2. Tap **Add a tunnel**.
3. Choose **Scan from QR code**.
4. Scan the QR code printed by the installer.
5. Save the tunnel and activate it.
6. Approve the Android VPN permission request.

If the QR code is displayed on the same phone, show the terminal on another screen. You can also transfer the `.conf` file securely and import it into the app.

### iPhone and iPad

1. Install and open WireGuard.
2. Tap **Add a Tunnel**.
3. Choose **Create from QR code** or **Import tunnel(s) from file**.
4. Scan the server's QR code or select the transferred `.conf` file.
5. Save the tunnel and switch it on.
6. Approve the iOS VPN permission request.

### Windows

1. Install the official WireGuard application.
2. Open WireGuard.
3. Select **Import tunnel(s) from file**.
4. Choose the generated `.conf` file.
5. Select the tunnel and click **Activate**.

Alternatively, create a tunnel from the profile text using **Add Tunnel → Add empty tunnel**, then copy the values into the corresponding fields.

### macOS

1. Install the official WireGuard application.
2. Open WireGuard.
3. Choose **Import tunnel(s) from file**.
4. Select the generated `.conf` file.
5. Select the tunnel and activate it.

### Linux

Install WireGuard using your distribution's package manager. On Ubuntu or Debian:

```bash
sudo apt update
sudo apt install wireguard
```

Copy the client profile securely to `/etc/wireguard/wg-client.conf`, then protect it:

```bash
sudo chmod 600 /etc/wireguard/wg-client.conf
```

Start the tunnel:

```bash
sudo wg-quick up wg-client
```

Stop it:

```bash
sudo wg-quick down wg-client
```

To start it automatically at boot:

```bash
sudo systemctl enable wg-quick@wg-client
```

## Client configuration

A generated profile has this general structure:

```ini
[Interface]
PrivateKey = <client-private-key>
Address = 10.8.0.2/32
DNS = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = <server-public-key>
Endpoint = <server-public-ip-or-hostname>:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

### Important settings

- `AllowedIPs = 0.0.0.0/0` routes all IPv4 traffic through the VPN.
- `PersistentKeepalive = 25` is optional. It can help mobile devices maintain a connection behind carrier or Wi-Fi NAT. If the client says it is unnecessary, it can be removed.
- Do not change or share the client `PrivateKey`.
- Keep the server's public key in the `[Peer]` section exactly as generated.

## Add another device

Run the installer with a different client name on a fresh server configuration, or add a new peer manually to the existing server configuration.

For an existing `wg0` setup, do **not** rerun the installer: it intentionally refuses to overwrite `/etc/wireguard/wg0.conf`.

A new peer needs:

```ini
[Peer]
PublicKey = <new-client-public-key>
AllowedIPs = 10.8.0.<unused-number>/32
```

The new client profile needs its own private key and a unique VPN address. Never reuse a private key or client address between devices.

## Verify the connection

On the client device, visit:

```text
https://icanhazip.com
```

The result should be the server's public IPv4 address.

On the server, check WireGuard:

```bash
wg show
```

A connected client should show:

- A recent `latest handshake`
- Increasing receive and send transfer counters

Check the service:

```bash
systemctl status wg-quick@wg0 --no-pager
```

## Update Ubuntu separately

The installer refreshes package lists but does not upgrade the entire operating system. Run system upgrades separately when appropriate:

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

Anyone who obtains a client profile may be able to authenticate as that WireGuard peer. If a profile is exposed, remove that peer from the server configuration and create a replacement key pair.

### SSH access

This installer does not disable password authentication or change the SSH port. After confirming that key-based SSH login works, consider hardening SSH separately:

- Create and test an SSH key.
- Disable root SSH login where appropriate.
- Disable password authentication only after key login has been verified.
- Keep the SSH firewall rule open before enabling or changing firewall rules.

### IPv6 warning

The generated profile routes IPv4 traffic through the VPN using `0.0.0.0/0`. IPv6 is not configured by this installer. If the client has IPv6 connectivity, IPv6 traffic may bypass the tunnel.

Until IPv6 routing is configured, enable the WireGuard app's **block connections without VPN** or **kill switch** option if available, or disable IPv6 on the client. Do not add `::/0` unless the server has been configured to forward and route IPv6 correctly.

### Datacenter and hosting-provider limitations

This VPN uses the server's public IP address. Some websites and services may rate-limit or block hosting-provider IP ranges. This setup does not provide anonymity, rotating locations, or residential proxy behavior.

## Troubleshooting

### No handshake appears

Run:

```bash
systemctl status wg-quick@wg0 --no-pager
wg show
ufw status verbose
ss -lunp | grep 51820
```

Then confirm that:

- The client endpoint uses the correct public IPv4 address or hostname.
- UDP port `51820` is allowed by the upstream firewall or security group.
- UDP port `51820` is allowed by UFW.
- The client tunnel is enabled.
- The client public key is present in `/etc/wireguard/wg0.conf`.
- The server clock is correct.

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

Do not repeatedly reset the firewall remotely. Use your hosting provider's console or out-of-band access if available, then allow your actual SSH port before changing UFW rules:

```bash
ufw allow 22/tcp
ufw allow 51820/udp
ufw status verbose
```

Replace `22` with the SSH port configured on your server.

## Uninstall

Stop and disable WireGuard:

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

Add a license before publishing or distributing this repository. The MIT License is a common permissive choice for a small utility project.
