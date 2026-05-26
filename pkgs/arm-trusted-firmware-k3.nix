# TF-A bl31 for the TI K3 (J784S4) secure world. Built natively on aarch64.
# Mirrors the override pattern used by nixos-xlnx/pkgs/arm-trusted-firmware-xlnx.nix
# (replace makeFlags wholesale so buildArmTrustedFirmware's default M0 cross prefix
# doesn't leak the wrong CROSS_COMPILE).
#
# Flags follow U-Boot doc/board/ti/k3.rst + meta-ti trusted-firmware-a-ti.inc:
#   PLAT=k3 TARGET_BOARD=j784s4 SPD=opteed K3_USART=0x8
# Source + rev match the Toradex-pinned meta-ti (e4075fa…): TI's TF-A fork,
# branch ti-master, 2.12+git.
{
  lib,
  stdenv,
  fetchFromGitHub,
  buildArmTrustedFirmware,
  openssl,
}:

(buildArmTrustedFirmware rec {
  version = "2.12";
  src = fetchFromGitHub {
    owner = "TexasInstruments";
    repo = "arm-trusted-firmware";
    rev = "b11beb2b6bd30b75c4bfb0e9925c0e72f16ca53f"; # ti-master, from meta-ti SRCREV_tfa
    hash = "sha256-of5+mD5Plb12pIsx0yqk8warV3MhV3fJJZtFcxKCyM8=";
  };
  platform = "k3";
  extraMakeFlags = [ "bl31" ];
  extraMeta.platforms = [ "aarch64-linux" ];
  # TI k3 plat writes bl31 under build/k3/<TARGET_BOARD>/release/bl31.bin.
  filesToInstall = [ "build/k3/j784s4/release/bl31.bin" ];
}).overrideAttrs
  (old: {
    makeFlags = [
      "bl31"
      "PLAT=k3"
      "TARGET_BOARD=j784s4" # TFA_BOARD (j784s4.inc)
      "SPD=opteed" # TFA_SPD (trusted-firmware-a-ti.inc)
      "K3_USART=0x8" # TFA_K3_USART (am69-sk.conf) — main UART = ttyS2
      "ARCH=aarch64"

      "HOSTCC=$(CC_FOR_BUILD)"
      "CROSS_COMPILE=${stdenv.cc.targetPrefix}" # empty on native aarch64
      # 2.11+ toolchain guessing wants these explicit:
      "CC=${stdenv.cc.targetPrefix}cc"
      "LD=${stdenv.cc.targetPrefix}cc"
      "AS=${stdenv.cc.targetPrefix}cc"
      "OC=${stdenv.cc.targetPrefix}objcopy"
      "OD=${stdenv.cc.targetPrefix}objdump"
      "OPENSSL_DIR=${openssl}"
    ];
  })
