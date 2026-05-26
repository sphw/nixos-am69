# Bootable raw image for early bring-up. For SD/MMC (non-boot-partition) media the
# K3 ROM loads `tiboot3.bin` *as a file* from the first FAT partition (raw sector-0
# placement is the eMMC-boot0 method — see emmc-flash.nix — and would clobber the
# MBR here). So we put tiboot3.bin / tispl.bin / u-boot.img as files in the FAT
# firmware partition, and the NixOS rootfs (with /boot/extlinux/extlinux.conf) on
# the ext4 partition. U-Boot's `bootflow scan` then boots the extlinux entry.
# Flash with:
#   zstdcat result/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
#
# Mirrors nixos-xlnx/sd-image.nix.
{
  config,
  pkgs,
  modulesPath,
  options,
  lib,
  ...
}:

{
  imports = [
    "${modulesPath}/profiles/base.nix"
    "${modulesPath}/installer/sd-card/sd-image.nix"
    ./nixos.nix
  ];
  disabledModules = [ "${modulesPath}/profiles/all-hardware.nix" ];

  config = {
    sdImage = {
      # FAT firmware partition holds the boot chain as files for the ROM/SPL.
      # ~2.6 MiB of blobs; give headroom.
      firmwareSize = 32;
      # The ROM/SPL load these by exact filename from the first FAT partition.
      populateFirmwareCommands = ''
        cp ${pkgs.ubootAquilaR5}/tiboot3-am69-hs-fs-aquila.bin firmware/tiboot3.bin
        cp ${pkgs.ubootAquilaA72}/tispl.bin                     firmware/tispl.bin
        cp ${pkgs.ubootAquilaA72}/u-boot.img                    firmware/u-boot.img
      '';
      populateRootCommands = ''
        mkdir -p ./files/boot
        ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
          -c ${config.system.build.toplevel} -d ./files/boot
      '';
    };

    # all-hardware.nix moved to an option in recent nixpkgs; keep backwards-compatible.
    hardware = lib.optionalAttrs (options.hardware ? enableAllHardware) {
      enableAllHardware = lib.mkForce false;
    };
  };
}
