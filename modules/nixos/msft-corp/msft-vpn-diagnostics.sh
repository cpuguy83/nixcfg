#!/usr/bin/env bash

VPN_GATEWAY=${VPN_GATEWAY:-msftvpn-alt.ras.microsoft.com}
VPN_PROTOCOL=${VPN_PROTOCOL:-gp}
VPN_REPORTED_OS=${VPN_REPORTED_OS:-win}
AUTH_STACK=${AUTH_STACK:-intune}
NM_DAEMON=${NM_DAEMON:-NetworkManager}
EXPECTED_BROWSER=${EXPECTED_BROWSER:-zen-beta.desktop}

failures=0
warnings=0

section() {
  printf '\n== %s ==\n' "$1"
}

pass() {
  printf 'PASS: %s\n' "$1"
}

warn() {
  warnings=$((warnings + 1))
  printf 'WARN: %s\n' "$1"
}

fail() {
  failures=$((failures + 1))
  printf 'FAIL: %s\n' "$1"
}

have_systemd_system() {
  [ -d /run/systemd/system ] && systemctl list-units >/dev/null 2>&1
}

require_cmd() {
  local cmd="$1"
  local label="$2"

  if command -v "$cmd" >/dev/null 2>&1; then
    pass "$label is available at $(command -v "$cmd")"
  else
    fail "$label is not available on PATH"
  fi
}

check_command_available() {
  local cmd="$1"
  local label="$2"

  if command -v "$cmd" >/dev/null 2>&1; then
    pass "$label is available at $(command -v "$cmd")"
  else
    warn "$label is not available on PATH"
  fi
}

check_system_service_active() {
  local unit="$1"
  local label="$2"

  if have_systemd_system; then
    if systemctl is-active --quiet "$unit"; then
      pass "$label is active ($unit)"
    else
      warn "$label is not active ($unit); it may be socket/D-Bus activated or not used yet"
    fi
  else
    warn "No live systemd system manager; skipped $label ($unit)"
  fi
}

check_user_service_active() {
  local unit="$1"
  local label="$2"

  if systemctl --user list-units >/dev/null 2>&1; then
    if systemctl --user is-active --quiet "$unit"; then
      pass "$label is active ($unit)"
    else
      warn "$label is not active ($unit); it may be D-Bus activated or not used yet"
    fi
  else
    warn "No user systemd manager; skipped $label ($unit)"
  fi
}

check_resolved() {
  local nm_config

  if command -v "$NM_DAEMON" >/dev/null 2>&1 || [ -x "$NM_DAEMON" ]; then
    if nm_config=$("$NM_DAEMON" --print-config 2>&1); then
      if printf '%s\n' "$nm_config" | grep -Eq '^[[:space:]]*dns=systemd-resolved([[:space:]]|$)'; then
        pass "NetworkManager is configured for systemd-resolved DNS"
      else
        fail "NetworkManager is not reporting dns=systemd-resolved"
      fi
    else
      warn "Could not inspect NetworkManager DNS config with NetworkManager --print-config: $nm_config"
    fi
  else
    fail "NetworkManager daemon is missing: $NM_DAEMON"
  fi

  require_cmd resolvectl resolvectl

  if have_systemd_system; then
    if systemctl is-active --quiet systemd-resolved.service; then
      pass "systemd-resolved.service is active"
    else
      fail "systemd-resolved.service is not active"
    fi

    if resolvectl status >/dev/null 2>&1; then
      pass "resolvectl can query resolver status"
    else
      fail "resolvectl could not query resolver status"
    fi
  else
    warn "No live systemd system manager; skipped active systemd-resolved checks"
  fi
}

check_mime_default() {
  local scheme="$1"
  local actual

  if actual=$(xdg-mime query default "x-scheme-handler/$scheme" 2>/dev/null); then
    if [ "$actual" = "$EXPECTED_BROWSER" ]; then
      pass "xdg-mime default for $scheme is $EXPECTED_BROWSER"
    elif [ "$(id -u)" -eq 0 ]; then
      warn "xdg-mime default for $scheme is '$actual' for root; rerun as the desktop user for the real check"
    else
      warn "xdg-mime default for $scheme is '$actual', expected $EXPECTED_BROWSER; VPN auth may use a browser without broker support"
    fi
  elif [ "$(id -u)" -eq 0 ]; then
    warn "Could not query xdg-mime default for $scheme as root; rerun as the desktop user"
  else
    warn "Could not query xdg-mime default for $scheme"
  fi
}

check_browser_defaults() {
  require_cmd xdg-mime xdg-mime

  if [ "$(id -u)" -eq 0 ]; then
    warn "Running as root; browser default checks are advisory. Rerun as the desktop user."
  fi

  check_mime_default http
  check_mime_default https
}

check_auth_stack() {
  section "Auth stack: $AUTH_STACK"

  case "$AUTH_STACK" in
    himmelblau)
      check_command_available himmelblau_broker "Himmelblau broker command"
      check_command_available himmelblaud "Himmelblau daemon command"
      check_command_available himmelblaud_tasks "Himmelblau task daemon command"
      check_command_available aad-tool "Himmelblau aad-tool command"
      check_system_service_active himmelblaud.service "Himmelblau daemon service"
      check_system_service_active himmelblaud-tasks.service "Himmelblau tasks service"
      check_user_service_active himmelblau-broker.service "Himmelblau broker user service"

      if busctl --user --list >/dev/null 2>&1; then
        if busctl --user --list | grep -Fq com.microsoft.identity.broker1; then
          pass "User D-Bus has com.microsoft.identity.broker1"
        else
          warn "User D-Bus does not currently show com.microsoft.identity.broker1; broker may start on demand"
        fi
      else
        warn "Could not inspect user D-Bus for com.microsoft.identity.broker1"
      fi
      ;;
    intune)
      check_command_available intune-portal "Intune portal command"
      check_command_available intune-agent "Intune agent command"
      check_command_available intune-daemon "Intune daemon command"
      check_command_available microsoft-identity-broker "Microsoft identity broker command"
      check_command_available microsoft-identity-device-broker "Microsoft identity device broker command"
      check_command_available linux-entra-sso-host "Linux Entra SSO native messaging host"
      check_system_service_active intune-daemon.service "Intune daemon service"
      check_user_service_active intune-agent.service "Intune agent user service"
      ;;
    *)
      warn "Unknown auth stack '$AUTH_STACK'"
      ;;
  esac
}

print_guidance() {
  cat <<GUIDANCE

== Manual connection guidance ==
Use the external-browser gpclient flow because NetworkManager's OpenConnect dialog uses an embedded browser without broker/YubiKey support:
  msft-vpn-diagnostics connect

OpenConnect smoke test only:
  openconnect --protocol=$VPN_PROTOCOL --os=$VPN_REPORTED_OS $VPN_GATEWAY
GUIDANCE
}

gpclient_os() {
  case "$VPN_REPORTED_OS" in
    win | windows | Windows)
      printf 'Windows'
      ;;
    mac | Mac)
      printf 'Mac'
      ;;
    linux | Linux)
      printf 'Linux'
      ;;
    *)
      printf '%s' "$VPN_REPORTED_OS"
      ;;
  esac
}

connect_external_browser() {
  section "External browser connect"

  if [ "$(id -u)" -eq 0 ]; then
    fail "Run this as your desktop user, not root, so the auth flow can open your broker-enabled browser"
    return 1
  fi

  require_cmd gpclient gpclient

  if [ "$failures" -gt 0 ]; then
    return 1
  fi

  printf 'Opening your default browser for GlobalProtect SAML auth. Use Zen for broker/YubiKey support.\n'

  if gpclient connect --default-browser --os "$(gpclient_os)" "$VPN_GATEWAY"; then
    pass "gpclient connected to $VPN_GATEWAY"
  else
    fail "External-browser gpclient connection failed"
    return 1
  fi
}

run_diagnostics() {
  failures=0
  warnings=0

  section "Required tools"
  require_cmd openconnect openconnect

  section "systemd-resolved integration"
  check_resolved

  section "Browser defaults"
  check_browser_defaults

  check_auth_stack

  printf '\nSummary: %s hard failure(s), %s warning(s)\n' "$failures" "$warnings"

  if [ "$failures" -gt 0 ]; then
    return 1
  fi

  return 0
}

usage() {
  cat <<USAGE
Usage: $(basename "$0") [diagnose|check|connect|help]

diagnose/check  Run VPN prerequisite diagnostics and print manual guidance.
connect         Connect with gpclient using your default external browser.
help            Show this help.
USAGE
}

main() {
  local command_arg=diagnose
  local status=0

  if [ "$#" -gt 0 ]; then
    command_arg="$1"
  fi

  case "$command_arg" in
    diagnose | check)
      run_diagnostics || status=$?
      print_guidance
      exit "$status"
      ;;
    connect)
      run_diagnostics || status=$?
      print_guidance
      connect_external_browser || status=$?
      exit "$status"
      ;;
    help | --help | -h)
      usage
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "$@"
