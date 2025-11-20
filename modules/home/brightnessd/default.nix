{ pkgs, pkgs-unstable, ... }:

let
  brightnessdBin = pkgs.buildGoModule {
    pname = "brightnessd";
    version = "unstable-2024-11-14";
    src = ./.;
    vendorHash = "sha256-j1p8vZKM6y7xbITII4LrgrWyllQjVGeczXNEseKSeoU=";
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postInstall = ''
      wrapProgram $out/bin/brightnessd \
        --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs-unstable.swayosd ]}
    '';
  };
in
{
  home.packages = [
    brightnessdBin
  ];

  systemd.user.sockets.brightnessd = {
    Unit = {
      Description = "Socket for brightnessd control requests";
      WantedBy = [ "sockets.target" ];
    };
    Socket = {
      ListenStream = "%t/brightnessd.sock";
      SocketMode = "0660";
      RemoveOnStop = true;
    };
  };

  systemd.user.services.brightnessd = {
    Unit = {
      Description = "Brightness control daemon";
      Requires = [ "brightnessd.socket" ];
      After = [ "brightnessd.socket" ];
    };
    Service = {
      ExecStart = "${brightnessdBin}/bin/brightnessd";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
