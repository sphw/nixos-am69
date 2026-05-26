# Toradex U-Boot for the Aquila AM69, built twice (one derivation, two variants).
# U-Boot's binman assembles the K3 boot blobs at build time:
#
#   variant = "r5"  -> aquila-am69_r5_defconfig  (32-bit ARM Cortex-R5F SPL)
#                      + BINMAN_INDIRS=<ti-linux-firmware>
#                      => tiboot3-am69-hs-fs-aquila.bin   (R5 SPL + TIFS/sysfw)
#
#   variant = "a72" -> aquila-am69_a72_defconfig (aarch64 Cortex-A72)
#                      + BINMAN_INDIRS, BL31=<tfa>/bl31.bin, TEE=<optee>/tee-raw.bin
#                      => tispl.bin  (A72 SPL + TF-A bl31 + OP-TEE + DM fw)
#                      => u-boot.img (U-Boot proper)
#
# Mirrors the per-platform switch in nixos-xlnx/pkgs/u-boot-xlnx.nix. Source/rev =
# Toradex fork toradex_ti-u-boot-2024.04 (verified to contain both defconfigs and the
# k3-am69-aquila-dev-binman.dtsi that names the hs-fs output blob).
{
  lib,
  stdenv,
  buildUBoot,
  fetchgit,
  pkgsCross,
  buildPackages,

  variant, # "r5" | "a72"
  tiLinuxFirmware, # ti-linux-firmware-k3 derivation
  bl31 ? null, # store-path string (a72 only)
  tee ? null, # store-path string (a72 only)
}:

assert lib.elem variant [
  "r5"
  "a72"
];
assert variant == "a72" -> (bl31 != null && tee != null);

let
  src = fetchgit {
    url = "https://git.toradex.com/u-boot-toradex.git";
    rev = "11cb0162a795f19fefa660ad0fc62f7688f2e227";
    branchName = "toradex_ti-u-boot-2024.04";
    hash = "sha256-qlSZIxu3iFMgCZjwTBrVKywMGjtregVzsesRbMb1+Bg=";
  };

  # The R5 SPL is 32-bit ARM (armv7 hardfloat, matching k3.rst's arm-linux-gnueabihf-).
  # The A72 stage builds natively on aarch64. Switching stdenv makes buildUBoot set
  # CROSS_COMPILE=${stdenv.cc.targetPrefix} appropriately.
  ubStdenv = if variant == "r5" then pkgsCross.armv7l-hf-multiplatform.stdenv else stdenv;

  defconfig = if variant == "r5" then "aquila-am69_r5_defconfig" else "aquila-am69_a72_defconfig";

  # binman needs more Python than buildUBoot's stock env ships (pyyaml at minimum;
  # jsonschema/yamllint for the schema checks). Build a complete env and swap it in.
  binmanPython = buildPackages.python3.withPackages (
    p: with p; [
      libfdt
      setuptools
      pyelftools
      pyyaml
      jsonschema
      yamllint
    ]
  );
in
(buildUBoot {
  inherit src defconfig;
  stdenv = ubStdenv;
  version = "2024.04-toradex-aquila-${variant}";
  # The R5 SPL is cross-built to armv7l (its hostPlatform); the A72 stage is aarch64.
  extraMeta.platforms = if variant == "r5" then [ "armv7l-linux" ] else [ "aarch64-linux" ];

  extraMakeFlags =
    [ "BINMAN_INDIRS=${tiLinuxFirmware}" ]
    ++ lib.optionals (variant == "a72") [
      "BL31=${bl31}"
      "TEE=${tee}"
      # The A72 binman also describes combined firmware-aquila-am69-*.bin images that
      # bundle the R5 tiboot3 (built separately); allow those external blobs to be
      # missing so the build still emits tispl.bin + u-boot.img (which we install).
      "BINMAN_ALLOW_MISSING=1"
    ];

  filesToInstall =
    if variant == "r5" then
      # Install the HS-FS blob by its real name (the plain tiboot3.bin is a binman
      # symlink to the GP variant); this is exactly what Tezi flashes to boot0.
      [ "tiboot3-am69-hs-fs-aquila.bin" ]
    else
      [
        "tispl.bin"
        "u-boot.img"
      ];
}).overrideAttrs
  (old: {
    # Replace the stock python3 env (libfdt/setuptools/pyelftools only) with one that
    # also has pyyaml/jsonschema/yamllint for binman.
    nativeBuildInputs =
      (builtins.filter (p: !(lib.hasInfix "python3" "${p.name or ""}")) old.nativeBuildInputs)
      ++ [ binmanPython ];
  })
