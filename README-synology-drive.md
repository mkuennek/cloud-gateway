# Synology Drive on `kuenneke.cloud`

`cloud-gateway` is the public reverse proxy for DSM/Synology Drive on
`KuennekeCloud` (`100.108.81.29`). It also obtains the Let's Encrypt
certificate for `kuenneke.cloud` via NixOS ACME.

## Relevant NixOS files

- `/etc/nixos/configuration.nix`
  - Opens TCP `6690` in the firewall.
  - Proxies HTTPS `https://kuenneke.cloud/` to DSM on `100.108.81.29:5040`.
  - Uses nginx `streamConfig` to pass TCP `6690` to `100.108.81.29:6690`.
- `/etc/nixos/synology-cert-sync.nix`
  - Defines `synology-cert-sync-kuenneke-cloud.service`.
  - Adds an ACME `postRun` hook for `security.acme.certs."kuenneke.cloud"`.
  - Copies renewed cert files from `/var/lib/acme/kuenneke.cloud` to DSM.

Because `/etc/nixos` is a flake Git tree, new files must be `git add`ed before
`nixos-rebuild` can see them.

## Important: Drive desktop client port 6690

Synology Drive desktop clients do **not** speak normal TLS immediately on TCP
`6690`. The protocol starts in plaintext and then upgrades inside Synology
Drive. Therefore nginx must **not** use `listen 6690 ssl`.

Correct behavior:

```nginx
server {
  listen 6690;
  proxy_pass 100.108.81.29:6690;
}
```

The public certificate is installed on the Synology side instead of terminating
TLS on `cloud-gateway`.

`openssl s_client -connect kuenneke.cloud:6690` showing `no peer certificate
available` is expected for the initial handshake and does not mean Drive is
broken.

## Certificate sync flow

1. NixOS ACME writes/renews:
   - `/var/lib/acme/kuenneke.cloud/fullchain.pem`
   - `/var/lib/acme/kuenneke.cloud/chain.pem`
   - `/var/lib/acme/kuenneke.cloud/key.pem`
2. `synology-cert-sync-kuenneke-cloud.service` extracts/stages:
   - `cert.pem`
   - `chain.pem`
   - `fullchain.pem`
   - `privkey.pem`
3. Files are copied to DSM:
   - `/var/services/homes/Michael/cert-sync/kuenneke.cloud/`
4. If available via passwordless sudo, DSM runs:
   - `/usr/local/sbin/install-kuenneke-cloud-cert /var/services/homes/Michael/cert-sync/kuenneke.cloud`
5. The DSM installer copies files into:
   - `/usr/local/etc/certificate/SynologyDrive/SynologyDrive/`
   and restarts Synology Drive.

## DSM prerequisites

- `Michael` must accept the dedicated SSH key from cloud-gateway:
  - `/var/lib/synology-cert-sync/id_ed25519.pub`
- DSM sudoers must allow this exact command without a password:

```sudoers
Michael ALL=(root) NOPASSWD: /usr/local/sbin/install-kuenneke-cloud-cert /var/services/homes/Michael/cert-sync/kuenneke.cloud
```

## Useful checks

Manual sync:

```bash
systemctl start synology-cert-sync-kuenneke-cloud.service
journalctl -u synology-cert-sync-kuenneke-cloud.service -n 30 --no-pager
```

Expected successful log lines:

```text
Synology certificate files staged in /var/services/homes/Michael/cert-sync/kuenneke.cloud
Synology Drive certificate installer completed.
```

ACME timer:

```bash
systemctl list-timers acme-kuenneke.cloud.timer --all
systemctl cat acme-kuenneke.cloud.service
```

Drive TCP proxy log:

```bash
tail -f /var/log/nginx/stream-access.log
```

From the Synology Drive desktop client, use this server address:

```text
kuenneke.cloud
```

Do not use `https://kuenneke.cloud/drive`; that is the browser URL and the
desktop client treats it as an invalid address/port.
