# nixos-am69

NixOS for the **Toradex Aquila AM69** System-on-Module (TI AM69 / J784S4, K3
family), booted via U-Boot. Structure follows the Xilinx port (`nixos-xlnx`): a
flake + overlay + per-component derivations + NixOS modules.

## Boot chain (TI K3, multi-stage, assembled by U-Boot binman)

```
ROM → tiboot3.bin (R5 SPL + TIFS/sysfw)
    → tispl.bin   (A72 SPL + TF-A bl31 + OP-TEE bl32 + DM fw)
    → u-boot.img  (U-Boot proper)
    → kernel + k3-am69-aquila-dev.dtb  (via extlinux / `bootflow scan`)
```

There is no bootgen/BIF. U-Boot's **binman** pulls the firmware blobs in at build
time from `BINMAN_INDIRS` (sysfw + DM), `BL31=` (TF-A) and `TEE=` (OP-TEE), across
two U-Boot builds (R5 → `tiboot3`, A72 → `tispl` + `u-boot.img`).

## Component sources (pinned to the Toradex BSP 7.x era)

| Component | Repo / branch | Rev |
|---|---|---|
| Kernel | `git.toradex.com/linux-toradex` `toradex_ti-linux-6.6.y` | `81fb03d3…` (6.6.138) |
| U-Boot | `git.toradex.com/u-boot-toradex` `toradex_ti-u-boot-2024.04` | `11cb0162…` |
| TF-A | `github.com/TexasInstruments/arm-trusted-firmware` `ti-master` | `b11beb2b…` (2.12) |
| OP-TEE | `github.com/OP-TEE/optee_os` | `ef1ebdc2…` (4.5.0) |
| Firmware | `git.ti.com/git/processor-firmware/ti-linux-firmware` `ti-linux-firmware` | `c3ad8113…` (sysfw 11.00.07) |

## Building

All builds run on a native **aarch64-linux** Nix (OrbStack on Apple Silicon),
invoked with the `orb` prefix. Build bottom-up:

```sh
orb nix build .#ti-linux-firmware-k3     # sysfw + DM blobs
orb nix build .#armTrustedFirmwareK3     # bl31.bin
orb nix build .#opteeK3                  # tee-raw.bin
orb nix build .#ubootAquilaR5            # tiboot3-am69-hs-fs-aquila.bin
orb nix build .#ubootAquilaA72           # tispl.bin + u-boot.img
orb nix build .#linux_aquila             # Image + dtbs
orb nix build .#nixosConfigurations.aquila-am69.config.system.build.sdImage
```

The kernel (stock arm64 `defconfig`) builds a very large module tree. If the Nix
daemon's build dir is a small tmpfs (OrbStack's `/tmp` defaults to ~RAM/2), the
kernel/image builds fail with "No space left on device". `--option build-dir` is a
daemon-side setting and is *not* honored from the client, so point the **daemon's**
`TMPDIR` at a disk-backed path (reversible runtime override; reverts on reboot):

```sh
orb bash -lc '
  sudo mkdir -p /run/systemd/system/nix-daemon.service.d
  printf "[Service]\nEnvironment=TMPDIR=/var/tmp\n" | sudo tee /run/systemd/system/nix-daemon.service.d/tmpdir.conf
  sudo systemctl daemon-reload && sudo systemctl restart nix-daemon
'
```

To make it permanent, set `systemd.services.nix-daemon.environment.TMPDIR = "/var/tmp";`
in the builder's NixOS config.

## Flashing

### SD card (early bring-up)

The K3 ROM boots the same blob layout from SD as from eMMC, so the built image is
directly bootable:

```sh
zstdcat result/*.img.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

Insert into the carrier board, set the boot strap to SD, and watch the serial
console (`ttyS2`, 115200 8N1).

### eMMC over USB DFU (`aquila-emmc-flash`)

The boot blobs live in the eMMC **boot0** hardware partition; the rootfs lives in the
user area. Strap the module to USB peripheral (DFU) boot, connect Type-C/USB0 to the
host, then run the bundled tool (it is on the target image's PATH, or build it with
`orb nix build .#nixosConfigurations.aquila-am69.config.system.build.aquilaFlasher`):

```sh
aquila-emmc-flash
```

It loads `tiboot3` → `tispl` → `u-boot.img` into RAM over DFU, then prints the U-Boot
prompt commands to write boot0 (`run update_tiboot3 / update_tispl / update_uboot`,
offsets 0x0 / 0x400 / 0x1400) and to expose the eMMC user area (`ums 0 mmc 0`) for
writing the rootfs.

## Layout

```
flake.nix            inputs, overlay, modules, packages, nixosConfiguration
overlay.nix          wires every component into nixpkgs
nixos.nix            boot-chain wiring (kernel, extlinux, dtb, console, initrd)
sd-image.nix         SD raw image (blobs dd'd into the gap at K3 offsets)
emmc-flash.nix       DFU eMMC flasher + rootfs output
pkgs/                ti-linux-firmware, arm-trusted-firmware-k3, optee-os-k3,
                     u-boot-toradex (r5/a72), linux-toradex
examples/aquila-am69 reference host + standalone flake
```

## Status / known follow-ups

- HS-FS signing uses binman's built-in degenerate keys (HS-FS accepts any-key
  signatures per U-Boot `doc/board/ti/k3.rst`); no `ti-k3-secdev` needed.
- Suspend/resume (TF-A LPM patches) and remote-processor firmware loading are not
  wired up yet.
- Smoke-test built blobs against the reference Tezi build in
  `torizon-docker-aquila-am69-Tezi_7.6.1+build.38/`.
