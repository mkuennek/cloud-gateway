{ pkgs, ... }:
let
  update = pkgs.writeShellScript "gateway-nightly-update" ''
    set -euo pipefail
    export GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -i /root/.ssh/gateway-update -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=20"
    cd /etc/nixos
    exec 9>/run/gateway-maintenance.lock
    ${pkgs.util-linux}/bin/flock -n 9
    test -z "$(git status --porcelain)" || { echo 'Dirty checkout; refusing update'; exit 1; }
    git fetch origin main
    test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" || { echo 'Remote/local divergence; refusing update'; exit 1; }
    git push --dry-run origin HEAD:main
    old=$(readlink -f /run/current-system)
    committed=0
    trap 'rc=$?; if [ "$rc" != 0 ] && [ "$committed" = 0 ]; then git restore -- flake.lock; fi; exit "$rc"' EXIT
    nix flake update
    new=$(nix build --no-link --print-out-paths .#nixosConfigurations.cloud-gateway.config.system.build.toplevel)
    if [ "$new" != "$old" ]; then
      nix-env --profile /nix/var/nix/profiles/system --set "$new"
      if ! "$new/bin/switch-to-configuration" switch; then
        nix-env --profile /nix/var/nix/profiles/system --set "$old"
        "$old/bin/switch-to-configuration" switch
        exit 1
      fi
    fi
    healthy=0
    for attempt in $(seq 1 12); do
      if systemctl is-active --quiet nginx && systemctl is-active --quiet tailscaled && curl -fsS --max-time 10 --resolve jellyfin.kuenneke.cloud:443:127.0.0.1 https://jellyfin.kuenneke.cloud/health >/dev/null; then healthy=1; break; fi
      sleep 10
    done
    if [ "$healthy" != 1 ]; then
      nix-env --profile /nix/var/nix/profiles/system --set "$old"
      "$old/bin/switch-to-configuration" switch
      exit 1
    fi
    if ! git diff --quiet -- flake.lock; then
      git add -- flake.lock
      git commit -m "chore: nightly flake dependency update"
      committed=1
      git push origin HEAD:main
    fi
    git fetch origin main
    test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
    echo 'Nightly update and remote synchronization verified'
  '';
in {
  systemd.services.gateway-nightly-update = {
    description = "Build, activate, health-check and publish gateway updates";
    path = [ pkgs.git pkgs.nix pkgs.coreutils pkgs.curl pkgs.systemd ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = update;
      TimeoutStartSec = "2h";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
  systemd.timers.gateway-nightly-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00 Europe/Berlin";
      Persistent = false;
      Unit = "gateway-nightly-update.service";
    };
  };
  services.journald.extraConfig = ''
    SystemMaxUse=512M
    SystemKeepFree=2G
    MaxRetentionSec=30day
  '';
  nix.gc = {
    automatic = true;
    dates = "Sun *-*-* 05:30:00 Europe/Berlin";
    options = "--delete-older-than 30d";
  };
}

