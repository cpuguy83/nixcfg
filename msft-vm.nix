{ pkgs, ... }:
{
  systemd.user.services.msft-vm = let
    ga_sock_name = "msft-vm-ga.sock";
    qmp_sock_name = "msft-vm-qmp.sock";
    qmpSock = "%t/" + qmp_sock_name;
    qgaSock = "%t/" + ga_sock_name;

    scriptHeader = ''
#!${pkgs.runtimeShell}

set -eu

exec_cmd() {
  ${pkgs.socat}/bin/socat -v -u - UNIX-CONNECT:"$QGA_SOCKET"
  ${pkgs.socat}/bin/socat -U -T 0.5 - UNIX-CONNECT:"$QGA_SOCKET"
}

send_shutdown() {
  exec_cmd <<EOF
{ "execute": "guest-shutdown" }
EOF
}
'';

    qemuStopScript = pkgs.writeScript "stop-qemu-vm" ''
${scriptHeader}

send_shutdown
while [ -S "$QMP_SOCKET" ]; do
  sleep 1
done
'';
    qemuStartScript = pkgs.writeScript "start-qemu-vm" ''
${scriptHeader}

${pkgs.qemu}/bin/qemu-system-x86_64 \
  -m 16384 \
  -enable-kvm \
  -cpu host \
  -smp 4 \
  -vga none \
  -M q35,accel=kvm \
  -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::13389-:3389,hostfwd=udp::13389-:3389 \
  -device virtio-net-pci,netdev=net0 \
  -device vhost-vsock-pci,guest-cid=3 \
  -audio driver=pipewire,model=virtio \
  -audiodev pipewire,id=snd0,in.channels=1,out.channels=2,in.frequency=48000,out.frequency=48000 \
  -device virtio-sound,audiodev=snd0 \
  -device virtio-gpu-rutabaga,gfxstream-vulkan=on,cross-domain=on,hostmem=16G,wsi=surfaceless \
  -chardev socket,path=$QMP_SOCKET,server=on,wait=off,id=qmp0 \
  -mon chardev=qmp0,mode=control \
  -chardev socket,id=qga0,server=on,wait=off,path=$QGA_SOCKET \
  -device virtio-serial-pci,id=virtio-serial0 \
  -device virtserialport,bus=virtio-serial0.0,nr=1,chardev=qga0,id=channel0,name=org.qemu.guest_agent.0 \
    -drive file=/home/cpuguy83/VMs/ubuntu-msft.qcow2 \
    &

pid=$!

handle_exit() {
  if [ -S "$QGA_SOCKET" ]; then
    send_shutdown
  fi
  waitpid $pid
}

trap 'handle_exit' EXIT

ping() {
  exec_cmd <<<'{"execute":"guest-ping"}'
}

echo "Waiting for guest agent socket" >&2
until ping | grep -q "return"; do
  sleep 1
done

trap "echo VM started with PID $pid >&2" EXIT
${pkgs.systemd}/bin/systemd-notify --ready --pid=$pid
    '';

  in {
    description = "Microsoft in-tuned VM";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Environment = [
          "QMP_SOCKET=${qmpSock}"
          "QGA_SOCKET=${qgaSock}"
        ];
        ExecStart = "${qemuStartScript}";
        ExecStop = "${qemuStopScript}";
        Restart = "on-failure";
        Type = "notify";
        NotifyAccess = "all";
      };
    };

  # Make sure the systemd unit uses dockerd from our overlay instead of the
  # main pkgs.docker
  systemd.services.docker.serviceConfig.ExecStart = [
    ""
    "${pkgs.docker.moby}/bin/dockerd"
  ];
}
