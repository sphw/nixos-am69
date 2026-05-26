# Toradex TI-based kernel (6.6 LTS) carrying the k3-am69-aquila device trees.
# Mirrors nixos-xlnx/pkgs/linux-xlnx/default.nix: buildLinux over a vendor fork with
# a stock arch defconfig plus a structuredExtraConfig that forces the symbols NixOS
# needs for eMMC root and the serial console.
#
# Source/rev = Toradex fork toradex_ti-linux-6.6.y (verified Makefile: 6.6.138).
{
  lib,
  buildLinux,
  fetchgit,
  stdenv,
  defconfig ? "defconfig", # stock arch/arm64 defconfig (includes TI K3 drivers)
  kernelPatches ? [ ],
  ...
}@args:

let
  linuxVersion = "6.6.138"; # from arch/.../Makefile (VERSION.PATCHLEVEL.SUBLEVEL)
  version = "${linuxVersion}-toradex-ti";
in
buildLinux (
  args
  // {
    inherit version;
    modDirVersion = linuxVersion;

    src = fetchgit {
      url = "https://git.toradex.com/linux-toradex.git";
      rev = "81fb03d3794671a801d80fa78adfe4fb108af5a8";
      branchName = "toradex_ti-linux-6.6.y";
      hash = "sha256-fHVXW5j0R+Em6yuYb3qBS5ojtxQQx3sCEOSLM8HfbOc=";
    };

    inherit defconfig kernelPatches;

    # Force the symbols required to mount the eMMC root and drive the serial console,
    # regardless of how the stock defconfig sets them (built-in => boots even with a
    # minimal initrd).
    structuredExtraConfig = with lib.kernel; {
      DEBUG_INFO_BTF = lib.mkForce no; # avoid pahole/BTF build friction

      # eMMC / SD on J784S4 (TI sdhci-am654 controller)
      MMC = yes;
      MMC_BLOCK = yes;
      MMC_SDHCI = yes;
      MMC_SDHCI_PLTFM = yes;
      MMC_SDHCI_AM654 = yes;

      # Console: ttyS2 = MAIN UART0 (8250-omap)
      SERIAL_8250 = yes;
      SERIAL_8250_CONSOLE = yes;
      SERIAL_8250_OMAP = yes;

      EXT4_FS = yes;
    };

    extraMeta.platforms = [ "aarch64-linux" ];

    ignoreConfigErrors = true;
  }
  // (args.argsOverride or { })
)
