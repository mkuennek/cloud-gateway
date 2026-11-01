{
  description = "A simple NixOS flake";

  inputs = {
    # Supported stable NixOS release; keep flake.lock updated for security fixes.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations.cloud-gateway = nixpkgs.lib.nixosSystem {
      modules = [
        # Import the previous configuration.nix we used,
        # so the old configuration file still takes effect
        ./configuration.nix
      ];
    };
  };
}
