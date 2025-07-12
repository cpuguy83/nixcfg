{ pkgs, pkgs-unstable, ... }:
let
  vmScripts = pkgs.stdenv.mkDerivation {
    name = "msft-vm-scripts";
    src = ./scripts;

    nativeBuildInputs = [ pkgs.makeWrapper ];
    installPhase = ''
      mkdir -p $out/bin
      cp start.sh stop.sh lib.sh $out/bin/
      chmod +x $out/bin/start.sh
      chmod +x $out/bin/stop.sh

      wrapProgram $out/bin/start.sh \
        --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.qemu pkgs.coreutils pkgs.systemd pkgs.socat pkgs.util-linux ]}

      wrapProgram $out/bin/stop.sh \
        --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.socat ]}
    '';
  };
in
  {
    environment.systemPackages = ([
      vmScripts
    ]) 
    
    ++

    (with pkgs; [
      virt-viewer
      usbredir
      waypipe
    ])

    ++

    (with pkgs-unstable; [
      qemu
      qemu_kvm
      virglrenderer
      mesa
      libglvnd
      libGL
    ])
    ;

    virtualisation.spiceUSBRedirection.enable = true;

    systemd.user.services.msft-vm = let
      qmpSock = "%t/msft-vm-ga.sock";
      qgaSock = "%t/msft-vm-qmp.sock";
    in {
      description = "Microsoft in-tuned VM";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Environment = [
          "QMP_SOCKET=${qmpSock}"
          "QGA_SOCKET=${qgaSock}"
        ];
        ExecStart = "${vmScripts}/bin/start.sh";
        ExecStop = "${vmScripts}/bin/stop.sh";
        Restart = "on-failure";
        Type = "notify";
        NotifyAccess = "all";
      };
    };
}
