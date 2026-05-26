{
  description = "NixOS for the Toradex Aquila AM69 SoM (TI J784S4 / K3), booted via U-Boot";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      # Builds run on a native aarch64-linux Nix (OrbStack on Apple Silicon,
      # invoked as `orb nix build ...`). x86_64-linux is exposed for convenience
      # (everything cross-compiles), but real builds happen natively on aarch64.
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = lib.genAttrs systems;
      pkgsFor = system: import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
      };
    in
    {
      overlays.default = import ./overlay.nix;

      legacyPackages = forAllSystems pkgsFor;

      # Individually buildable artifacts (the boot blobs and their inputs).
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          inherit (pkgs)
            ti-linux-firmware-k3
            armTrustedFirmwareK3
            opteeK3
            ubootAquilaR5
            ubootAquilaA72
            linux_aquila
            ;
          inherit (pkgs) ubootAquilaA72Flasher;
          # Convenient aliases for the three boot blobs.
          tiboot3 = pkgs.ubootAquilaR5;
          tispl-and-uboot = pkgs.ubootAquilaA72;

          # The bootable SD-card image (early bring-up; same blob layout boots eMMC).
          sdImage = self.nixosConfigurations.aquila-am69.config.system.build.sdImage;

          # One-click, serial-free eMMC installer (host-side, USB DFU). Run it on the
          # machine the module is plugged into: `nix run .#flash` (or build & run this).
          aquila-emmc-flash = pkgs.callPackage ./pkgs/aquila-emmc-flash.nix {
            image = self.nixosConfigurations.aquila-am69.config.system.build.sdImage;
          };
        }
      );

      apps = forAllSystems (system: {
        # Serial-free eMMC flash over USB DFU.
        flash = {
          type = "app";
          program = "${self.packages.${system}.aquila-emmc-flash}/bin/aquila-emmc-flash";
        };
      });

      nixosModules = {
        # Boot-chain wiring only (kernel, extlinux, device tree, initrd).
        aquila-am69 = import ./nixos.nix;
        # SD-card raw image (imports aquila-am69).
        sd-image = import ./sd-image.nix;
        # Boot blobs + DFU eMMC flasher.
        emmc-flash = import ./emmc-flash.nix;
        default = import ./nixos.nix;
      };

      # A ready-to-build reference system. Build the image with:
      #   orb nix build .#nixosConfigurations.aquila-am69.config.system.build.sdImage
      nixosConfigurations.aquila-am69 = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          self.nixosModules.sd-image
          self.nixosModules.emmc-flash
          ./examples/aquila-am69/aquila.nix
        ];
      };
    };
}
