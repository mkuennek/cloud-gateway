{ pkgs, lib, ... }:

let
  syncScript = pkgs.writeShellScript "sync-kuenneke-cloud-cert-to-synology" ''
    set -euo pipefail

    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gawk pkgs.openssh ]}:$PATH

    cert_dir="''${1:-/var/lib/acme/kuenneke.cloud}"
    state_dir="/var/lib/synology-cert-sync"
    ssh_key="$state_dir/id_ed25519"
    known_hosts="$state_dir/known_hosts"

    synology_user="Michael"
    synology_host="kuennekecloud.tailb573c.ts.net"
    synology_port="1008"
    remote_base="/var/services/homes/Michael/cert-sync"
    remote_dir="$remote_base/kuenneke.cloud"
    remote_tmp="$remote_base/kuenneke.cloud.tmp"
    remote_install="/usr/local/sbin/install-kuenneke-cloud-cert"

    for f in fullchain.pem chain.pem key.pem; do
      if [ ! -r "$cert_dir/$f" ]; then
        echo "Missing readable ACME file: $cert_dir/$f" >&2
        exit 1
      fi
    done

    if [ ! -r "$ssh_key" ]; then
      echo "Missing SSH key: $ssh_key" >&2
      exit 1
    fi

    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    # Synology expects cert.pem to be the leaf certificate, while NixOS ACME's
    # cert.pem for this host points at fullchain.pem. Extract the first PEM block.
    awk '
      /-----BEGIN CERTIFICATE-----/ { in_cert=1; count++ }
      in_cert && count == 1 { print }
      /-----END CERTIFICATE-----/ && count == 1 { exit }
    ' "$cert_dir/fullchain.pem" > "$tmpdir/cert.pem"

    install -m 0600 "$cert_dir/fullchain.pem" "$tmpdir/fullchain.pem"
    install -m 0600 "$cert_dir/chain.pem" "$tmpdir/chain.pem"
    install -m 0600 "$cert_dir/key.pem" "$tmpdir/privkey.pem"

    ssh_cmd() {
      ssh \
        -i "$ssh_key" \
        -p "$synology_port" \
        -o IdentitiesOnly=yes \
        -o IdentityAgent=none \
        -o BatchMode=yes \
        -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="$known_hosts" \
        "$@"
    }

    scp_cmd() {
      scp \
        -O \
        -i "$ssh_key" \
        -P "$synology_port" \
        -o IdentitiesOnly=yes \
        -o IdentityAgent=none \
        -o BatchMode=yes \
        -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="$known_hosts" \
        "$@"
    }

    target="$synology_user@$synology_host"

    ssh_cmd "$target" "rm -rf '$remote_tmp' && mkdir -p '$remote_base' '$remote_dir' '$remote_tmp' && chmod 700 '$remote_base' '$remote_dir' '$remote_tmp'"
    scp_cmd "$tmpdir/cert.pem" "$tmpdir/chain.pem" "$tmpdir/fullchain.pem" "$tmpdir/privkey.pem" "$target:$remote_tmp/"
    ssh_cmd "$target" "chmod 600 '$remote_tmp'/*.pem && rm -f '$remote_dir'/*.pem && mv '$remote_tmp'/*.pem '$remote_dir'/ && rmdir '$remote_tmp'"

    echo "Synology certificate files staged in $remote_dir"

    # Optional root-side installer. Install this on DSM and add a sudoers rule
    # if you want the copy to be activated for Synology Drive automatically.
    if ssh_cmd "$target" "sudo -n '$remote_install' '$remote_dir' 2>/dev/null"; then
      echo "Synology Drive certificate installer completed."
    else
      echo "Synology Drive installer was not run. Stage-only sync completed."
      echo "Expected optional installer: $remote_install"
    fi
  '';
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/synology-cert-sync 0700 root root - -"
  ];

  systemd.services.synology-cert-sync-kuenneke-cloud = {
    description = "Copy the kuenneke.cloud ACME certificate to KuennekeCloud/Synology";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    script = ''
      ${syncScript} /var/lib/acme/kuenneke.cloud
    '';
  };

  security.acme.certs."kuenneke.cloud".postRun = ''
    ${syncScript} "$PWD" || echo "WARNING: failed to sync kuenneke.cloud certificate to Synology" >&2
  '';
}
