# OP-TEE OS (secure-world bl32) for TI K3 J784S4. Produces $out/tee-raw.bin, which
# U-Boot's binman consumes via TEE= (see doc/board/ti/k3.rst). Built natively on
# aarch64 (arm64 core); a 32-bit ARM cross compiler is supplied for the arm32 build
# pieces the K3 platform Makefile still references.
#
# Pin matches the Toradex-pinned meta-ti (e4075fa…): upstream OP-TEE 4.5.0+git,
# SRCREV ef1ebdc2. OPTEEMACHINE=k3-j784s4 => PLATFORM=k3-j784s4; OPTEE_K3_USART=0x8.
{
  lib,
  fetchFromGitHub,
  buildOptee,
  pkgsCross,
}:

(buildOptee {
  version = "4.5.0";
  src = fetchFromGitHub {
    owner = "OP-TEE";
    repo = "optee_os";
    rev = "ef1ebdc23034a804a72da2207f1a825ce96a1464";
    hash = "sha256-MHzKOrPGvJtuVlXMqXq3hswyYiVWMdhUTtVptX4ftMA=";
  };
  platform = "k3-j784s4";
  extraMakeFlags = [
    # Builder already adds O=out, CFG_ARM64_core=y, CROSS_COMPILE64=<native aarch64>.
    # K3 also references a 32-bit toolchain; point it at a real gnueabihf prefix.
    "CROSS_COMPILE32=${pkgsCross.armv7l-hf-multiplatform.stdenv.cc.targetPrefix}"
    "CFG_CONSOLE_UART=0x8" # OPTEE_K3_USART (am69-sk.conf)
    "CFG_TEE_CORE_LOG_LEVEL=1"
  ];
  extraMeta.platforms = [ "aarch64-linux" ];
}).overrideAttrs
  (old: {
    # Make the 32-bit cross gcc available on PATH (strictDeps build).
    nativeBuildInputs = old.nativeBuildInputs ++ [
      pkgsCross.armv7l-hf-multiplatform.stdenv.cc
    ];
  })
