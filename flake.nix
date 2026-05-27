{
  description = "NixOS for the Toradex Aquila AM69 SoM (TI J784S4 / K3), booted via U-Boot";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;

      # Build platforms this project can be built ON. The TARGET is always
      # aarch64-linux: on an aarch64 host everything builds natively; on x86_64-linux
      # everything cross-compiles (kernel, U-Boot R5/A72, TF-A, OP-TEE, rootfs, image).
      buildSystems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllBuild = lib.genAttrs buildSystems;

      # Native package set for the build host (host-side tooling like dfu-util/zstd
      # that must run where the board is plugged in).
      nativePkgsFor = bs: import nixpkgs { system = bs; };

      # aarch64-linux *target* package set, built on `bs`. Native when bs is aarch64,
      # cross otherwise. The overlay (all the Aquila/K3 packages) is applied here.
      targetPkgsFor =
        bs:
        import nixpkgs (
          {
            system = bs;
            overlays = [ self.overlays.default ];
          }
          // lib.optionalAttrs (bs != "aarch64-linux") {
            crossSystem = lib.systems.examples.aarch64-multiplatform;
          }
        );

      # A NixOS system targeting aarch64-linux, built on `bs` (cross when bs != aarch64).
      nixosFor =
        bs:
        nixpkgs.lib.nixosSystem {
          modules = [
            {
              nixpkgs.buildPlatform = bs;
              nixpkgs.hostPlatform = "aarch64-linux";
            }
            self.nixosModules.sd-image
            self.nixosModules.emmc-flash
            ./examples/aquila-am69/aquila.nix
          ];
        };

      # The serial-free USB-DFU installer. It runs on the build host, so its tooling is
      # NATIVE to `bs`, while the artifacts it writes (boot blobs + image) are the
      # aarch64 target outputs.
      flasherFor =
        bs:
        (nativePkgsFor bs).callPackage ./pkgs/aquila-emmc-flash.nix {
          inherit (targetPkgsFor bs)
            ubootAquilaR5
            ubootAquilaA72
            ubootAquilaA72Flasher
            ;
          image = (nixosFor bs).config.system.build.sdImage;
        };
    in
    {
      overlays.default = import ./overlay.nix;

      # aarch64-target package set per build host (cross from x86_64).
      legacyPackages = forAllBuild targetPkgsFor;

      # Individually buildable artifacts (boot blobs, kernel, image, flasher).
      packages = forAllBuild (
        bs:
        let
          tp = targetPkgsFor bs;
        in
        {
          inherit (tp)
            ti-linux-firmware-k3
            armTrustedFirmwareK3
            opteeK3
            ubootAquilaR5
            ubootAquilaA72
            ubootAquilaA72Flasher
            linux_aquila
            ;
          tiboot3 = tp.ubootAquilaR5;
          tispl-and-uboot = tp.ubootAquilaA72;

          # Bootable SD image (same blob layout boots eMMC).
          sdImage = (nixosFor bs).config.system.build.sdImage;

          # One-click, serial-free eMMC installer (host-side, USB DFU).
          aquila-emmc-flash = flasherFor bs;
        }
      );

      apps = forAllBuild (bs: {
        # Serial-free eMMC flash over USB DFU: `nix run .#flash`.
        flash = {
          type = "app";
          program = "${flasherFor bs}/bin/aquila-emmc-flash";
        };
      });

      nixosModules = {
        # Boot-chain wiring only (kernel, extlinux, device tree, initrd).
        aquila-am69 = import ./nixos.nix;
        # SD-card raw image (imports aquila-am69).
        sd-image = import ./sd-image.nix;
        # On-target eMMC boot0 bootloader updater.
        emmc-flash = import ./emmc-flash.nix;
        default = import ./nixos.nix;
      };

      # Reference systems. Build the image with e.g.:
      #   orb nix build .#nixosConfigurations.aquila-am69.config.system.build.sdImage
      # On an x86_64-linux host, build the cross variant (or just .#packages.x86_64-linux.sdImage):
      #   nix build .#nixosConfigurations.aquila-am69-x86.config.system.build.sdImage
      nixosConfigurations = {
        aquila-am69 = nixosFor "aarch64-linux";
        aquila-am69-x86 = nixosFor "x86_64-linux";
      };
    };
}
