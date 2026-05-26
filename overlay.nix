# Wires every Aquila AM69 / TI K3 component into nixpkgs. The K3 boot chain is
# assembled by U-Boot's binman across two U-Boot builds:
#
#   ROM -> tiboot3.bin (R5 SPL + TIFS/sysfw)
#       -> tispl.bin   (A72 SPL + TF-A bl31 + OP-TEE bl32 + DM fw)
#       -> u-boot.img  (A72 U-Boot proper)
#       -> kernel + dtb
#
# Unlike the Xilinx port there is no bootgen/BIF; binman pulls the firmware blobs
# in from BINMAN_INDIRS / BL31= / TEE= at U-Boot build time.
final: prev: {
  # Prebuilt TIFS/sysfw + Device Manager firmware blobs (no compile) consumed by
  # binman via BINMAN_INDIRS.
  ti-linux-firmware-k3 = prev.callPackage ./pkgs/ti-linux-firmware.nix { };

  # TF-A bl31 (PLAT=k3, TARGET_BOARD=j784s4, SPD=opteed) -> bl31.bin.
  armTrustedFirmwareK3 = prev.callPackage ./pkgs/arm-trusted-firmware-k3.nix { };

  # OP-TEE OS (PLATFORM=k3-j784s4) -> tee-raw.bin.
  opteeK3 = prev.callPackage ./pkgs/optee-os-k3.nix { };

  # R5 U-Boot build: produces tiboot3-am69-hs-fs-aquila.bin (32-bit ARM cross).
  ubootAquilaR5 = prev.callPackage ./pkgs/u-boot-toradex.nix {
    variant = "r5";
    tiLinuxFirmware = final.ti-linux-firmware-k3;
  };

  # A72 U-Boot build: produces tispl.bin + u-boot.img (native aarch64).
  ubootAquilaA72 = prev.callPackage ./pkgs/u-boot-toradex.nix {
    variant = "a72";
    tiLinuxFirmware = final.ti-linux-firmware-k3;
    bl31 = "${final.armTrustedFirmwareK3}/bl31.bin";
    tee = "${final.opteeK3}/tee-raw.bin";
  };

  # Flasher A72 U-Boot: same build, but auto-enters `dfu 0 mmc 0` (no serial). Loaded
  # transiently into RAM by the host flash tool to write the eMMC over USB DFU.
  ubootAquilaA72Flasher = prev.callPackage ./pkgs/u-boot-toradex.nix {
    variant = "a72";
    flasher = true;
    tiLinuxFirmware = final.ti-linux-firmware-k3;
    bl31 = "${final.armTrustedFirmwareK3}/bl31.bin";
    tee = "${final.opteeK3}/tee-raw.bin";
  };

  # Toradex 6.6 TI-based kernel with the k3-am69-aquila device trees.
  # Pass kernelPatches = [ ] explicitly so callPackage doesn't inject nixpkgs'
  # top-level `kernelPatches` *set* (buildLinux wants a list).
  linux_aquila = prev.callPackage ./pkgs/linux-toradex {
    defconfig = "defconfig";
    kernelPatches = [ ];
  };
  linuxPackages_aquila = prev.linuxKernel.packagesFor final.linux_aquila;
}
