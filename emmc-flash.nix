# eMMC flashing for the Aquila AM69 over USB DFU. Provides `aquila-emmc-flash`,
# which loads the boot chain into RAM over the ROM/SPL DFU interface, then guides
# writing the three boot blobs to the eMMC boot0 partition and the rootfs to the
# user area. Offsets and U-Boot env command names match the reference Tezi image
# (image.json + u-boot-initial-env-sd).
#
# Recovery strap: put the module in USB peripheral (DFU) boot mode and connect the
# Type-C (USB0) port to the host. See README.md for the carrier-board specifics.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  r5 = pkgs.ubootAquilaR5;
  a72 = pkgs.ubootAquilaA72;

  flasher = pkgs.writeShellApplication {
    name = "aquila-emmc-flash";
    runtimeInputs = [ pkgs.dfu-util ];
    text = ''
      set -euo pipefail

      TIBOOT3="${r5}/tiboot3-am69-hs-fs-aquila.bin"
      TISPL="${a72}/tispl.bin"
      UBOOT="${a72}/u-boot.img"

      echo "==> Waiting for the board in ROM USB DFU mode (run with the module"
      echo "    strapped to USB peripheral boot, Type-C/USB0 connected)."
      dfu-util -l || true

      echo "==> [1/3] ROM DFU: loading tiboot3 (alt 'bootloader')"
      dfu-util -R -a bootloader -D "$TIBOOT3"

      echo "==> [2/3] SPL DFU: loading tispl.bin into RAM"
      sleep 2
      dfu-util -a tispl.bin -D "$TISPL"

      echo "==> [3/3] SPL DFU: loading u-boot.img into RAM and starting it"
      dfu-util -R -a u-boot.img -D "$UBOOT"

      cat <<EOF

      ==> U-Boot is now running from RAM. Finish the install at its prompt:

          # 1. Write the boot blobs to the eMMC boot0 hardware partition.
          #    Load each blob to \''${loadaddr} (DFU/tftp/fatload), then:
          mmc dev 0 1
          # tiboot3 -> sector 0x0 ; tispl -> 0x400 ; u-boot.img -> 0x1400
          run update_tiboot3      # after loading tiboot3-am69-hs-fs-aquila.bin
          run update_tispl        # after loading tispl.bin
          run update_uboot        # after loading u-boot.img
          mmc partconf 0 1 1 0    # boot from boot0 (ack=1, boot0 enabled)

          # 2. Write the NixOS rootfs to the eMMC user area. Expose it over USB:
          ums 0 mmc 0
          #    then on the host (eMMC user area appears as /dev/sdX), write the SD
          #    image you built (the same blob layout boots eMMC too):
          #      orb nix build .#nixosConfigurations.aquila-am69.config.system.build.sdImage
          #      zstdcat result/*.img.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
          #    Ctrl-C the 'ums' command when done.

          # 3. Reboot. U-Boot's 'bootflow scan -b' reads /boot/extlinux/extlinux.conf
          #    from the ext4 root and boots the NixOS generation.
      EOF
    '';
  };
in
{
  config = {
    environment.systemPackages = [ flasher ];

    # The bare ext4 rootfs (label NIXOS_SD), exposed for direct writes if preferred
    # over writing the whole sdImage.
    system.build.emmcRootfs = lib.mkDefault config.sdImage.rootFilesystemImage;
    system.build.aquilaFlasher = flasher;
  };
}
