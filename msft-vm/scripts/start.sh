#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source ${SCRIPT_DIR}/lib.sh

qemu-system-x86_64 \
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

notify() {
	systemd-notify --pid=$pid $@
}

notify --status="booting vm"

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

wait_vm() {
	ec=0
	waitpid -t 1 $pid || ec=$?
	# Check if the pid is still running
	# Don't rely on waitpid since we are using a timeout (-t).
	if kill -0 $pid; then
		return 0
	fi
	return $ec
}

wait_ping() {
	until [ -S "$QGA_SOCKET" ]; do
			wait_vm
	done
	until ping | grep -q "return"; do
		# Wait up to one sec for the pid to exit
		# This is better than sleep because if the process exits this will know
		# And we'll also get the exit code
		notify --status="waiting for guest" EXTEND_TIMEOUT_USEC=12000000 # extend startup timeout by 1.2s
		wait_vm
	done
}

echo "Waiting for guest agent socket" >&2
wait_ping

trap "echo VM started with PID $pid >&2" EXIT
notify --ready --status="ready"

