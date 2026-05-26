# Minimal reference NixOS host for the Toradex Aquila AM69. Pair this with the
# sd-image and emmc-flash modules (see the flake's nixosConfigurations.aquila-am69).
{ lib, ... }:

{
  networking.hostName = "aquila";

  # Serial console getty (matches console=ttyS2,115200 from the boot wiring).
  systemd.services."serial-getty@ttyS2".enable = true;

  # First-boot access. CHANGE THESE before deploying anywhere real.
  users.users.root.initialPassword = "nixos";
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = lib.mkDefault "yes";
  };

  # The root filesystem is provided by the sd-image module (label NIXOS_SD), which
  # also expands the partition on first boot.
  system.stateVersion = "25.11";
}
