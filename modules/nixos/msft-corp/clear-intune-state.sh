#!/usr/bin/env bash

set -x

shutdown_services() {
	sudo systemctl stop microsoft-identity-device-broker.service
	sudo systemctl stop intune-daemon.service intune-daemon.socket
	systemctl stop --user microsoft-identity-broker.service
	systemctl stop --user intune-agent.service
	systemctl --user stop 'dbus-:1.2-com.microsoft.identity.broker1@*.service'
	systemctl reload --user dbus
	sudo systemctl reload dbus
}

remove_state() {
	sudo rm -rf /run/intune
	sudo rm -rf /var/lib/microsoft-identity-device-broker
	sudo rm -rf /var/lib/intune
	sudo rm -rf /run/microsoft-identity-device-broker

	rm -rf ~/.local/state/intune
	rm -rf ~/.local/share/intune-portal
	rm -rf ~/.local/state/microsoft-identity-broker
	rm -rf ~/.cache/intune-portal
	rm -rf ~/.Microsoft
	rm -rf ~/.config/intune

	: ${XDG_RUNTIME_DIR:="/run/user/$(id -u)"}
	rm -rf ${XDG_RUNTIME_DIR}/intune
	rm -rf ${XDG_RUNTIME_DIR}/microsoft-identity-broker
}

restart_services() {
	sudo systemctl start intune-daemon.service intune-daemon.socket
	sudo systemctl start microsoft-identity-device-broker.service
	systemctl start --user microsoft-identity-broker.service
}


do_restart=""
case "$1" in
	--restart)
		do_restart="1"
		;;
	"")
		;;
	*)
		echo "Unknown argument: $1" >&2
		exit 1
		;;
esac

shutdown_services
remove_state

if [ "$do_restart" = "1" ]; then
	echo "Restarting services..." >&2
	restart_services
fi
