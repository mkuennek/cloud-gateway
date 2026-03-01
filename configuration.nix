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
  users.users.root.extraGroups = [ "docker" ];
  system.stateVersion = "23.11";

  # Enable the Flakes feature and the accompanying new nix command-line tool
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    # Flakes clones its dependencies through the git command,
    # so git must be installed first
    git
    neovim
    wget
    lazygit
    nix-search
    opencode
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
    allowedTCPPorts = [ 80 443 6690 ];
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
        proxyPass = "http://100.108.81.29:5040/";
        proxyWebsockets = true;
      };
      locations."/webdav" = {
        proxyPass = "http://100.108.81.29:50004/";
        proxyWebsockets = true;
      };
      locations."/babysmash" = {
        proxyPass = "http://100.116.3.66:8080/";
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
    virtualHosts."homeassistant.kuenneke.cloud" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://100.96.83.1:8123";
        proxyWebsockets = true;
	extraConfig = ''
	proxy_set_header Host $host;
	proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
	proxy_set_header X-Forwarded-Proto $scheme;
	proxy_set_header Upgrade $http_upgrade;
	proxy_set_header Connection "upgrade";
	'';
      };
    };
    virtualHosts."harsewinkel.kuenneke.cloud" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://100.84.213.119:8123";
        proxyWebsockets = true;
	extraConfig = ''
	proxy_set_header Host $host;
	proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
	proxy_set_header X-Forwarded-Proto $scheme;
	proxy_set_header Upgrade $http_upgrade;
	proxy_set_header Connection "upgrade";
	'';
      };
    };
    virtualHosts."roadtrip-ai.de" = {
      addSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:3000";
        proxyWebsockets = true;
      };
      locations."/api" = {
        proxyPass = "http://localhost:8080";
        proxyWebsockets = true;
      };
    };
    streamConfig = ''
      server {
        listen 6690 ssl;
        proxy_pass 100.108.81.29:6690;

        ssl_certificate /var/lib/acme/kuenneke.cloud/fullchain.pem;
        ssl_certificate_key /var/lib/acme/kuenneke.cloud/key.pem;

        proxy_timeout 600s; 
      }
    '';
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

  virtualisation.docker.enable = true;
}
