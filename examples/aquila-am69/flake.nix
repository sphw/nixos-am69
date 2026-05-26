{
  description = "Example NixOS system for the Toradex Aquila AM69";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixos-am69.url = "path:../..";
    nixos-am69.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, nixpkgs, nixos-am69 }:
    {
      nixosConfigurations.aquila = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          nixos-am69.nixosModules.sd-image
          nixos-am69.nixosModules.emmc-flash
          ./aquila.nix
        ];
      };

      # Build with:
      #   orb nix build .#sdImage
      packages.aarch64-linux.sdImage =
        self.nixosConfigurations.aquila.config.system.build.sdImage;
    };
}
