# Prebuilt TI K3 firmware blobs (TIFS/sysfw + Device Manager) consumed by U-Boot's
# binman via BINMAN_INDIRS. No compilation (mirrors meta-ti ti-linux-fw.inc, whose
# do_compile is a no-op). The binman image descriptions in the Toradex u-boot fork
# reference these exact paths:
#   ti-sysfw/ti-fs-firmware-j784s4-hs-fs-{enc,cert}.bin   (HS-FS sysfw)
#   ti-sysfw/ti-fs-firmware-j784s4-{hs,gp}*.bin           (HS / GP variants)
#   ti-dm/j784s4/ipc_echo_testb_mcu1_0_release_strip.xer5f (Device Manager fw)
#
# Pin matches the Toradex-pinned meta-ti (e4075fa…): TI_LINUX_FW_SRCREV c3ad8113,
# branch ti-linux-firmware (sysfw 11.00.07 / dm 11.00.09).
{
  lib,
  stdenvNoCC,
  fetchgit,
}:

stdenvNoCC.mkDerivation {
  pname = "ti-linux-firmware-k3-j784s4";
  version = "11.00.07"; # TI_SYSFW_VERSION (Toradex BSP 7.x era)

  src = fetchgit {
    url = "https://git.ti.com/git/processor-firmware/ti-linux-firmware.git";
    rev = "c3ad8113c766bee7b8ddfae222e9b8017b565ea3";
    branchName = "ti-linux-firmware";
    # Only the blobs binman needs; keeps the (multi-GB) firmware repo checkout lean.
    sparseCheckout = [
      "ti-sysfw"
      "ti-dm"
    ];
    hash = "sha256-Pji7G7I/H6Cd3OwyuhbQan7Eix0a5T5s9f5lrx5XgAI=";
  };

  dontConfigure = true;
  dontBuild = true;

  # Install as a flat tree whose layout is exactly what BINMAN_INDIRS expects:
  #   <out>/ti-sysfw/...   <out>/ti-dm/j784s4/...
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r ti-sysfw "$out/ti-sysfw"
    cp -r ti-dm "$out/ti-dm"
    runHook postInstall
  '';

  meta = {
    description = "TI K3 (J784S4) TIFS/sysfw + Device Manager firmware blobs for binman";
    homepage = "https://git.ti.com/cgit/processor-firmware/ti-linux-firmware";
    license = lib.licenses.unfreeRedistributableFirmware; # TI TFL (see TI-TFL.txt)
    platforms = [ "aarch64-linux" "x86_64-linux" ];
  };
}
