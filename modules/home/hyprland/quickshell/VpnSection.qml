import QtQuick

// VPN section (control-center.md sec. 9.6, stage 4, revised): an accordion
// member, following the exact shape `BluetoothSection` uses. All state lives
// in `VpnState`/`ControlCenter` - singletons, per §10 I2's corollary that a
// section holds no state the rest of the system can observe - so this is a
// pure view over them.
//
// Revised shape: the header toggle owns connect/disconnect, replacing the
// old Connect/Disconnect row. The gateway rows pick which region the toggle
// targets — and, when a tunnel is already up, switch to it directly, since
// `corpnet-vpn-switch` performs that as one guarded stop-then-start rather
// than a disconnect the user then has to undo.
ControlCenterSection {
  id: root

  glyph: Icons.vpn
  // Named for what it actually is. This section is corpnet-specific end to
  // end — it shells out to `corpnet-vpn-indicator` and lists that config's
  // gateways — so a bare "VPN" overpromised, implying it managed any VPN on
  // the machine rather than this one profile.
  title: "MSFT Corpnet VPN"
  expanded: ControlCenter.expandedSection === "vpn"
  onHeaderClicked: ControlCenter.expandedSection = root.expanded ? "" : "vpn"

  // I5: no corpnet config on this host (CORPNET_VPN_INDICATOR absent from
  // the unit environment) hides the whole section rather than showing a
  // shell that can never report anything real.
  visible: VpnState.available

  // Region only — never the connection state. The header toggle already
  // signifies on/off, so a "Connected" label duplicated it, and the header
  // (long title + summary + toggle + chevron in 360px) is too tight to carry
  // both: the state word was being elided anyway. What the toggle *cannot*
  // show is which gateway, so that is what this says.
  summary: VpnState.region ?? ""

  // No `summaryColor` override: the green was carrying "connected", which is
  // now the toggle's job. A region name is neutral information, so it reads
  // as dimmed like every other section's summary rather than as a status
  // light competing with the switch beside it.

  // True whenever a tunnel exists, is coming up, or a setter's own re-poll
  // has not landed yet — i.e. whenever the header toggle should read as "on".
  // `pending` folds in the optimistic window right after a click, before
  // either the setter's own immediate re-poll or the unit's state-file hook
  // has landed; without it the toggle would visually snap back to its
  // pre-click position for that window, inviting a second click.
  readonly property bool vpnUp: VpnState.state === "connected" || VpnState.state === "connecting" || VpnState.pending

  // Narrower than vpnUp: only the in-flight window itself. Both the toggle
  // and the gateway rows stay live while merely *connected* — the toggle
  // because turning it off is the only way to disconnect, the rows because
  // picking a different region while connected is a switch. Neither may fire
  // mid-transition, which is what this guards.
  readonly property bool vpnBusy: VpnState.state === "connecting" || VpnState.pending

  // The only thing that connects or disconnects (§9.6, revised). `checked`
  // is optimistic - it includes "connecting" and `pending` so the switch
  // moves the instant you click and stays moved through gpclient's browser
  // SAML auth, rather than sitting visually off (and inviting a second
  // click) for however long that takes. `ControlCenterToggle` never writes
  // `checked` itself (its MouseArea only ever emits `toggled`), so this
  // binding cannot fight with anything.
  headerAccessory: ControlCenterToggle {
    checked: root.vpnUp
    enabled: !root.vpnBusy
    onToggled: value => {
      if (value) {
        // Guards the startup window before VpnState's first poll has ever
        // landed (§2.3: singletons populate asynchronously) - `vpnRegion`
        // is seeded from that poll, so it can briefly still be "" then.
        if (ControlCenter.vpnRegion !== "")
          VpnState.connect(ControlCenter.vpnRegion);
      } else {
        VpnState.disconnect();
      }
    }
  }

  Repeater {
    model: VpnState.gateways

    ControlCenterRow {
      id: gatewayRow

      required property var modelData

      // Checkmark tracks the daemon's own `active` flag whenever a tunnel is
      // really up, so it can never show a region that disagrees with reality.
      // The `pending` window is the exception: right after a click `active`
      // still names the *old* region for as long as the switch takes, so
      // during that window it optimistically shows the selection instead —
      // otherwise the checkmark would visibly sit on the region you just
      // moved away from.
      readonly property bool selected: (root.vpnUp && !VpnState.pending) ? gatewayRow.modelData.active : gatewayRow.modelData.region === ControlCenter.vpnRegion

      width: parent.width
      label: gatewayRow.modelData.region
      sublabel: gatewayRow.modelData.gateway
      // Only inert mid-transition, so a click cannot land between a stop and
      // the start that follows it.
      enabled: !root.vpnBusy

      // Selecting always sets the target. If a tunnel is already up, that
      // target is applied immediately — `corpnet-vpn-switch` stops whatever
      // is active and starts the new unit as one guarded operation, so this
      // is a switch rather than a disconnect-then-reconnect race. Clicking
      // the region that is already active is a deliberate no-op: tearing the
      // tunnel down and rebuilding it identically would cost a full SAML
      // round trip for no change.
      onClicked: {
        ControlCenter.vpnRegion = gatewayRow.modelData.region;
        if (VpnState.state === "connected" && !gatewayRow.modelData.active)
          VpnState.connect(gatewayRow.modelData.region);
      }

      Text {
        visible: gatewayRow.selected
        text: Icons.menuCheck
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
      }
    }
  }
}
