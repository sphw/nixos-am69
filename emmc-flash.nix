# On-target helper to refresh the eMMC boot0 bootloaders from a running NixOS system
# (e.g. after a U-Boot bump). The *initial* serial-free install is done from the host
# over USB DFU — see the flake's `aquila-emmc-flash` package / `nix run .#flash`.
#
# References only the boot blobs (never the system image), so it adds nothing
# circular to the system closure.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  r5 = pkgs.ubootAquilaR5;
  a72 = pkgs.ubootAquilaA72;

  updater = pkgs.writeShellApplication {
    name = "aquila-bootloader-update";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      set -euo pipefail
      BOOT0=/dev/mmcblk0boot0
      [ -e "$BOOT0" ] || { echo "no $BOOT0 (is this an Aquila AM69 with eMMC?)"; exit 1; }
      # boot0 is read-only by default; clear force_ro for the write.
      echo 0 > /sys/block/mmcblk0boot0/force_ro
      echo ">> writing tiboot3 / tispl / u-boot to $BOOT0 (offsets 0 / 0x400 / 0x1400)"
      dd if=${r5}/tiboot3-am69-hs-fs-aquila.bin of=$BOOT0 bs=512 seek=0    conv=fsync
      dd if=${a72}/tispl.bin                     of=$BOOT0 bs=512 seek=1024 conv=fsync
      dd if=${a72}/u-boot.img                    of=$BOOT0 bs=512 seek=5120 conv=fsync
      echo 1 > /sys/block/mmcblk0boot0/force_ro || true
      echo ">> done."
    '';
  };
in
{
  config = {
    environment.systemPackages = [ updater ];
    system.build.aquilaBootloaderUpdate = updater;
  };
}
