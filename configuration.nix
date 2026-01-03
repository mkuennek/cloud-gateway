{ config, pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./networking.nix # generated at runtime by nixos-infect
    
  ];

  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;
  networking.hostName = "cloud-gateway";
  networking.domain = "";
  services.openssh = {
    enable = true;
    openFirewall = true;
    ports = [ 1008 ];
  };
  users.users.root.openssh.authorizedKeys.keys = [''ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC+6kiv9H4MVDjBTsaGfE/tFAphUSLgl/12IrcTbkuU1bHqsvyRQ7B+1nvhx/aBnB1ZlaeZDK+DlY6sz++ceSOuq93UKCMYWdWVXmvncO3Gp4GyRojt7M2fOxTmT3YduiPUdJ9ovSeqW21pPn8wyMeShgf6Ob1p8ohR0gjD32YTxEtarOhvYDjdfnqc+9ieFi2jvlZxZbsNB2OHO7u0diEblRBxW4iIgC3YrM9joYxTYeGz4+VT+yPETcZ2hGViJHrSv8R63eNKJ4b3jzXOXV9n3M2VCovYiLlcYyKPDh+vgBjiuJoBaYid4GP09ls/FKf8QD46iMsccvw0EWTirKc4H18v0eTJgFgu+kT2rUflQVO2htIleaF/QixrQEFFiFbBol3eUMDyuUngOWKR7t/vaKM03Cc5wT3J5U/EKAJwD8NiNnFk9qNlva1zMTZrselrd9MEIkaliTnvIyRLCHQCMzthPtllG8j+rf7AFzrd4HkLSHigBMyUtjVl5xvCpzQT/Y0es/sgnCZl98xMIxgAqDR88b8kFfXRJU3amJJ5Ct0qQgAGQjSQojRwqy2eDH3FAXPX6qNIcdC+kZze7f4X3s/qldbN+gOnM47u3wOKVCIdA2/5xKxkLstcAA0fC5AkVdn8mXEtIXZjVVWEwAtM/IAnogAYvHfBYlSmOEIyXQ=='' ];
  system.stateVersion = "23.11";

  # Enable the Flakes feature and the accompanying new nix command-line tool
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  environment.systemPackages = with pkgs; [
    # Flakes clones its dependencies through the git command,
    # so git must be installed first
    git
    neovim
    wget
    lazygit
    nix-search
  ];
  # Set the default editor to vim
  environment.variables.EDITOR = "nvim";

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
  };

  networking.firewall = {
    # enable the firewall
    enable = true;

    # always allow traffic from your Tailscale network
    trustedInterfaces = [ "tailscale0" ];

    # allow the Tailscale UDP port through the firewall
    allowedUDPPorts = [ config.services.tailscale.port ];
    allowedTCPPorts = [ 80 443 ];
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    clientMaxBodySize = "4g";
    virtualHosts."kuenneke.cloud" = {
      addSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://100.108.81.29:5040";
        proxyWebsockets = true;
      };
      locations."/webdav" = {
        proxyPass = "http://100.108.81.29:50004/";
        proxyWebsockets = true;
      };
    };
    virtualHosts."jellyfin.kuenneke.cloud" = {
      addSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://nixos.tailb573c.ts.net:8096";
        proxyWebsockets = true;
      };
    };
    virtualHosts."immich.kuenneke.cloud" = {
      addSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://nixos.tailb573c.ts.net:8088";
        proxyWebsockets = true;
      };
    };
  };
  security.acme = {
    acceptTerms = true;
    defaults.email = "michael@kuenneke.cloud";
  };

  environment.shellAliases = {
    g = "lazygit";
    v = "nvim";
    update = "nixos-rebuild switch";
  };
}
