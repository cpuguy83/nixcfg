import QtQuick
import Quickshell
import Quickshell.Networking

// The single Control Center entry point on the bar (§9.8, stage 7 — the
// final one). Governing rule: the normal state is one glyph and nothing
// else; every badge and every tooltip line below exists only to report
// something abnormal or genuinely informative, never to pad this out.
BarPill {
  id: root

  required property var screen

  // Bound rather than toggled imperatively, so the button reads as "pressed"
  // for as long as its own screen's panel is open — and, as a side effect,
  // this binding is what forces the ControlCenter singleton into existence at
  // bar-construction time (§9.2) rather than deferring it to the first click.
  highlighted: ControlCenter.open && ControlCenter.screenName === (root.screen?.name ?? "")

  // No wired link and no connected WiFi network reads as "no connectivity at
  // all" — the same definition NetworkSection's own "Offline" summary uses.
  // A host with no network devices enumerated at all (Networking.devices
  // empty) also has no connectivity, so this falls out of the same check
  // with no extra branch.
  // `hasLink` is carrier-detect only ("cable plugged in"), not connectivity —
  // a cable into a dead switch reads as linked with nothing actually
  // reaching the network. `connected` is NetworkManager's own signal for the
  // device having live connectivity, which is what this badge/colour axis is
  // meant to report.
  readonly property bool networkConnected: (NetworkState.wiredDevice?.connected ?? false) || NetworkState.sortedNetworks.some(net => net.connected)

  // Prefix badges, fixed priority (§9.8), only when abnormal — this is what
  // keeps "one glyph" true for the common case. Each condition is gated on
  // its section actually being available (I5): a host with no `mine.audio`
  // wired up must never show a stale "latency" badge just because
  // `AudioState.currentModeId` sits at its unpolled default.
  //
  // "Abnormal" means something you would want to notice without opening the
  // panel. A connected VPN is not abnormal — it is the normal state of a
  // working day — so it gets no badge and no colour; it lives in the tooltip
  // and in its own section. A non-default latency tier is the same: it is a
  // deliberate setting, not a fault, and badging it just added an icon to the
  // bar that meant "you changed a setting on purpose".
  readonly property var badges: {
    const list = [];
    if (!root.networkConnected)
      list.push(Icons.networkOffline);
    if (AudioState.sink?.audio?.muted ?? false)
      list.push(Icons.volumeMuted);
    if (AudioState.source?.audio?.muted ?? false)
      list.push(Icons.micMuted);
    return list;
  }

  // The resting glyph is deliberately neutral and never changes with audio
  // state. An earlier revision used the default sink's icon as the primary
  // glyph, which meant the button silently became a headphone icon on
  // plugging headphones in — misrepresenting a control that also owns VPN,
  // Bluetooth and network. Sink mute is reported as a badge above instead,
  // which is the part actually worth noticing at a glance.
  text: ` ${root.badges.map(glyph => glyph + " ").join("")}${Icons.controlCenter} `

  // Colour is reserved for "something is wrong", not "a subsystem is active".
  // A VPN-connected button painted green read as an alert for a state that is
  // entirely normal, so that axis is gone; only a total loss of connectivity
  // colours the button now.
  textColor: root.networkConnected ? Theme.foreground : Theme.statusError

  // Composite tooltip (§9.8/§9.2): every section's headline state in one
  // place. Reading `Pipewire`/`Bluetooth`/`Networking`/`AudioState`/
  // `VpnState` here at bar-construction time — before any human can click —
  // is what forces every one of those service singletons into existence
  // ~1.5-3s early (§2.3, §9.2), so the panel is never empty on first open.
  // THIS ENUMERATION IS THE WARM-UP: a future "simplify the tooltip" pass
  // that trims it back down to just the sink would silently reintroduce
  // that empty-first-open bug.
  tooltipText: root.buildTooltip()

  function percentOf(node: var): int {
    return Math.round((node?.audio?.volume ?? 0) * 100);
  }

  function capitalize(value: string): string {
    return value.length > 0 ? value.charAt(0).toUpperCase() + value.slice(1) : value;
  }

  // Composite multi-line tooltip, in the style the retired `BluetoothPill`
  // used: one line per section, omitted entirely when that section is
  // unavailable rather than printing "unknown" — a missing corpnet config or
  // a missing Bluetooth adapter is not "abnormal", it is just absent (I5).
  function buildTooltip(): string {
    const lines = [];

    if (AudioState.sink)
      lines.push(`${AudioState.sink.description} — ${root.percentOf(AudioState.sink)}%${(AudioState.sink.audio?.muted ?? false) ? " [muted]" : ""}`);

    if (AudioState.source)
      lines.push(`${AudioState.source.description} — ${root.percentOf(AudioState.source)}%${(AudioState.source.audio?.muted ?? false) ? " [muted]" : ""}`);

    if (AudioState.available) {
      let latency = `Latency: ${AudioState.currentModeLabel}`;
      if (AudioState.currentQuantum !== null && AudioState.currentRate !== null)
        latency += ` (${AudioState.currentQuantum} @ ${AudioState.currentRate})`;
      lines.push(latency);
    }

    if (VpnState.available) {
      let vpn = `VPN: ${root.capitalize(VpnState.state)}`;
      if (VpnState.region)
        vpn += ` (${VpnState.region})`;
      lines.push(vpn);
    }

    // Unconditional, unlike NetworkSection's own `visible` — that gate hides
    // a shell that can never show anything real (I5), but the badge/colour
    // above already fold zero-devices into "not connected", so the tooltip
    // must agree rather than silently going quiet exactly where the button
    // is reddest.
    {
      let network = "Offline";
      if (NetworkState.wiredDevice?.connected) {
        network = NetworkState.wiredDevice.name;
      } else {
        const connected = NetworkState.sortedNetworks.find(net => net.connected);
        if (connected)
          network = connected.name;
      }
      lines.push(`Network: ${network}`);
    }

    if (BluetoothState.adapter) {
      const connected = BluetoothState.connectedDevices;
      lines.push("");
      // Restores the adapter name/id line the retired `BluetoothPill`
      // tooltip used to show — dropped when this block was written fresh
      // for the panel, rather than an intentional trim.
      lines.push(BluetoothState.adapter.name || BluetoothState.adapter.adapterId || "Bluetooth");
      lines.push(`${connected.length} connected`);
      for (const device of connected) {
        const label = device.deviceName || device.name || device.address;
        lines.push(device.batteryAvailable ? `${label}\t${Math.round(device.battery * 100)}%` : label);
      }
    }

    return lines.join("\n");
  }

  onClicked: ControlCenter.toggle(root, root.screen?.name ?? "")

  // Gestures preserved from the retired pills (parity gate, §12): right
  // click mutes the default sink, wheel adjusts its volume by
  // `Theme.volumeStep` per notch, and — new here — middle click mutes the
  // default source (the retired mic pill's own gesture), needing the
  // `middleClicked` signal added to `BarPill` this stage.
  onRightClicked: AudioState.toggleMute(AudioState.sink)
  onScrolled: steps => AudioState.adjustVolume(AudioState.sink, steps)
  onMiddleClicked: AudioState.toggleMute(AudioState.source)

  // Registers this screen's own button so the global shortcut (§12 stage 7)
  // can anchor to it exactly as a click would, rather than always falling
  // back to the screen's top-right corner — see `ControlCenter.toggleGlobal()`.
  Component.onCompleted: ControlCenter.registerButton(root.screen?.name ?? "", root)

  Component.onDestruction: ControlCenter.unregisterButton(root.screen?.name ?? "")
}
