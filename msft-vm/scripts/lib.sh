exec_cmd() {
	socat -v -u - UNIX-CONNECT:"$QGA_SOCKET"
	socat -U -T 0.5 - UNIX-CONNECT:"$QGA_SOCKET"
}

send_shutdown() {
	exec_cmd <<EOF
{ "execute": "guest-shutdown" }
EOF
}

