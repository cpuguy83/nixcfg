{ pkgs
, lib
, config
, ...
}:
let
  cfg = config.mine.desktop.hyprland;
in
{
  config = lib.mkIf cfg.enable {
    # hyprlock has no PAM service of its own (unlike swaylock), so it falls through
    # to /etc/pam.d/other which denies everything. Declare one here, and scope a
    # yubikey (u2f) rule to *only* this service so the corporate auth stack
    # (greetd/login/sudo/polkit) is untouched -- Intune dislikes u2f there, which is
    # why security.pam.u2f.enable stays false globally.
    # Note: the rule is named "yubikey" rather than "u2f" on purpose. "u2f" is a
    # predefined NixOS PAM rule gated by security.pam.u2f.enable (kept false for the
    # corporate stack), which would disable it here. A custom name is independent of
    # that global gate.
    security.pam.services.hyprlock.rules.auth.yubikey = {
      control = "sufficient";
      modulePath = "${pkgs.pam_u2f}/lib/security/pam_u2f.so";
      # Run before pam_unix so a touch unlocks without typing a password.
      order = config.security.pam.services.hyprlock.rules.auth.unix.order - 100;
      settings.cue = true;
    };
  };
}
