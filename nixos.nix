# Boot-chain wiring for the Toradex Aquila AM69 (no image/partition layout — that
# lives in sd-image.nix / emmc-flash.nix). Mirrors nixos-xlnx/nixos.nix:
# generic-extlinux-compatible (U-Boot `bootflow scan` reads /boot/extlinux/
# extlinux.conf), the Aquila kernel, the k3-am69-aquila device tree, and a console
# on ttyS2 (matching the Toradex U-Boot environment: console=ttyS2,115200).
{
  config,
  lib,
  pkgs,
  ...
}:

{
  config = {
    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
    nixpkgs.overlays = [
      # All Aquila AM69 / TI K3 packages.
      (import ./overlay.nix)
      # profiles/base.nix pulls efivar/efibootmgr, which we don't use (U-Boot distro
      # boot, not EFI). Stub them out (mirrors the nixos-xlnx workaround).
      (self: super: {
        efivar = super.emptyDirectory;
        efibootmgr = super.emptyDirectory;
      })
    ];

    # U-Boot distro/extlinux boot, no GRUB/EFI.
    boot.loader.grub.enable = lib.mkDefault false;
    boot.loader.generic-extlinux-compatible.enable = lib.mkDefault true;

    boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_aquila;

    # Tezi U-Boot env uses console=ttyS2 @115200. earlycon helps first bring-up.
    # NB: kernelParams is a concatenated list; do NOT wrap in mkDefault or these get
    # dropped by priority filtering against the normal-priority defaults.
    boot.kernelParams = [
      "console=ttyS2,115200n8"
      "earlycon"
    ];

    # U-Boot's preboot sets fdtfile=k3-am69-aquila-dev.dtb; pin the same DTB here.
    # (dtbSource defaults to "${kernel}/dtbs"; the kernel installs ti/k3-am69-aquila-dev.dtb.)
    hardware.deviceTree = {
      enable = lib.mkDefault true;
      name = lib.mkDefault "ti/k3-am69-aquila-dev.dtb";
    };

    # eMMC/SD (sdhci-am654) and the serial UART are forced built-in in the kernel,
    # so the initrd only needs USB / NVMe / SATA for peripherals and alt boot media.
    boot.initrd.includeDefaultModules = false;
    boot.initrd.availableKernelModules = [
      "nvme"
      "ahci"
      "sr_mod"
      "xhci_hcd"
      "xhci_pci"
      "usb_storage"
      "uas"
      "usbhid"
      "hid_generic"
    ];
  };
}
