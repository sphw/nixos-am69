# One-click, serial-free eMMC installer for the Aquila AM69, driven entirely over
# USB DFU from the host. Run it on the machine the module is plugged into, with the
# module strapped to USB peripheral (recovery/DFU) boot and USB0 (Type-C) connected.
#
# Flow (no serial console required at any point):
#   Stage A — bootstrap into RAM via the ROM/SPL DFU chain:
#     ROM(alt "bootloader")  <- tiboot3            (production R5 SPL + TIFS)
#     R5 SPL(alt "tispl.bin") <- tispl             (production A72 SPL + TFA/OPTEE/DM)
#     A72 SPL(alt "u-boot.img") <- FLASHER u-boot  (auto-runs `dfu 0 mmc 0`)
#   Stage B — the flasher U-Boot serves the eMMC over DFU; write the real images:
#     tiboot3.bin.raw -> eMMC boot0 @ 0x0
#     tispl.bin.raw   -> eMMC boot0 @ 0x400
#     u-boot.img.raw  -> eMMC boot0 @ 0x1400
#     sdcard.raw      -> eMMC user area (whole disk: MBR + ext4 rootfs)
#   then detach; power-cycle and the module boots NixOS from eMMC.
{
  lib,
  writeShellApplication,
  dfu-util,
  zstd,
  coreutils,
  ubootAquilaR5,
  ubootAquilaA72,
  ubootAquilaA72Flasher,
  image, # the sdImage derivation (contains sd-image/*.img.zst)
}:

writeShellApplication {
  name = "aquila-emmc-flash";
  runtimeInputs = [
    dfu-util
    zstd
    coreutils
  ];
  text = ''
    set -euo pipefail

    TIBOOT3="${ubootAquilaR5}/tiboot3-am69-hs-fs-aquila.bin"
    TISPL="${ubootAquilaA72}/tispl.bin"
    UBOOT="${ubootAquilaA72}/u-boot.img"
    FLASHER="${ubootAquilaA72Flasher}/u-boot.img"
    IMAGE_ZST=$(echo ${image}/sd-image/*.img.zst)

    # Wait until a DFU interface exposing the given alt name appears.
    wait_for_alt() {
      local alt="$1" n=0
      echo ">> waiting for DFU alt '$alt' ..."
      until dfu-util -l 2>/dev/null | grep -q "name=\"$alt\""; do
        sleep 1; n=$((n + 1))
        if [ "$n" -gt 180 ]; then
          echo "!! timed out waiting for DFU alt '$alt'"; exit 1
        fi
      done
    }

    echo "=============================================================="
    echo " Aquila AM69 eMMC flash (USB DFU, no serial required)"
    echo " Strap the module to USB peripheral/recovery boot and connect"
    echo " the Type-C (USB0) port to this host, then power it on."
    echo "=============================================================="

    # ---- Stage A: bootstrap the boot chain into RAM ----
    wait_for_alt bootloader
    echo ">> [A1] ROM <- tiboot3"
    dfu-util -R -a bootloader -D "$TIBOOT3"

    wait_for_alt tispl.bin
    echo ">> [A2] R5 SPL <- tispl"
    dfu-util -R -a tispl.bin -D "$TISPL"

    wait_for_alt u-boot.img
    echo ">> [A3] A72 SPL <- flasher u-boot (auto-enters dfu 0 mmc 0)"
    dfu-util -R -a u-boot.img -D "$FLASHER"

    # ---- Stage B: flasher U-Boot serves the eMMC over DFU ----
    wait_for_alt tiboot3.bin.raw
    echo ">> [B1] eMMC boot0 <- tiboot3 / tispl / u-boot"
    dfu-util -a tiboot3.bin.raw -D "$TIBOOT3"
    dfu-util -a tispl.bin.raw  -D "$TISPL"
    dfu-util -a u-boot.img.raw -D "$UBOOT"

    echo ">> [B2] decompressing rootfs image (this is the big one) ..."
    TMPIMG=$(mktemp --suffix=.img)
    trap 'rm -f "$TMPIMG"' EXIT
    zstd -dq -f "$IMAGE_ZST" -o "$TMPIMG"

    echo ">> [B3] eMMC user area <- whole disk image (slow over DFU; be patient)"
    dfu-util -a sdcard.raw -D "$TMPIMG"

    echo ">> done; detaching"
    dfu-util -a sdcard.raw -e || true

    echo "=============================================================="
    echo " Flash complete. Power-cycle the module (remove recovery strap)"
    echo " and it will boot NixOS from eMMC. Console: ttyS2 @ 115200."
    echo "=============================================================="
  '';
}
